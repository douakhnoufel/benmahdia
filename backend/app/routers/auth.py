"""Accounts and sessions for patients (PRD 4.1, 12.1).

Phone sign-up:  POST /otp/request → /otp/verify → /register
Password reset: POST /otp/request → /otp/verify → /password/reset
Google / Apple: POST /google or /apple, then (if no phone yet)
                /otp/request → /otp/verify → PUT /v1/me/phone
"""

import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from .. import audit, schemas, security, tokens
from ..clock import clock
from ..config import Settings, get_settings
from ..db import get_db
from ..errors import ApiError
from ..models import Identity, OtpCode, OtpPurpose, Provider, User
from ..phone import normalize_phone
from ..sms import SmsSender, get_sms_sender
from ..social import (
    AppleTokens,
    SocialNotConfigured,
    SocialTokenInvalid,
    SocialVerifier,
    get_apple_tokens,
    get_social_verifier,
)

router = APIRouter(prefix="/v1/auth", tags=["auth"])


def _phone(raw: str) -> str:
    phone = normalize_phone(raw)
    if phone is None:
        raise ApiError(422, "phone_invalid")
    return phone


def _user_by_phone(db: Session, phone: str) -> User | None:
    return db.scalar(select(User).where(User.phone == phone))


def _check_password(password: str) -> None:
    problems = security.password_problems(password)
    if problems:
        raise ApiError(422, "password_weak", rules=problems)


@router.post("/otp/request", status_code=202, response_model=schemas.OtpTicket)
def request_code(
    body: schemas.OtpRequest,
    request: Request,
    db: Session = Depends(get_db),
    sms: SmsSender = Depends(get_sms_sender),
    settings: Settings = Depends(get_settings),
) -> schemas.OtpTicket:
    """Sends a code. Sign-up and add-phone refuse a number that already has an
    account. A reset for an unknown number answers the same but sends
    nothing, so this endpoint never reveals who has an account."""
    phone = _phone(body.phone)
    now = clock.now()
    existing = _user_by_phone(db, phone)
    if existing is not None and body.purpose != OtpPurpose.reset_password:
        raise ApiError(409, "phone_taken")

    last = db.scalar(
        select(OtpCode)
        .where(OtpCode.phone == phone)
        .order_by(OtpCode.sent_at.desc())
        .limit(1)
    )
    if last is not None:
        wait = last.sent_at + timedelta(seconds=settings.otp_resend_seconds) - now
        if wait > timedelta(0):
            raise ApiError(429, "rate_limited", retry_after=max(1, int(wait.total_seconds())))
    sent_last_hour = db.scalar(
        select(func.count())
        .select_from(OtpCode)
        .where(OtpCode.phone == phone, OtpCode.sent_at > now - timedelta(hours=1))
    )
    if sent_last_hour >= settings.otp_max_per_hour:
        oldest = db.scalar(
            select(func.min(OtpCode.sent_at)).where(
                OtpCode.phone == phone, OtpCode.sent_at > now - timedelta(hours=1)
            )
        )
        wait = oldest + timedelta(hours=1) - now
        raise ApiError(429, "rate_limited", retry_after=max(1, int(wait.total_seconds())))

    ticket = schemas.OtpTicket(
        resend_after=settings.otp_resend_seconds,
        expires_in=settings.otp_minutes * 60,
    )
    send = existing is not None or body.purpose != OtpPurpose.reset_password
    code = security.new_code(settings.otp_length)
    db.execute(
        update(OtpCode)
        .where(OtpCode.phone == phone, OtpCode.purpose == body.purpose, OtpCode.verified_at.is_(None))
        .values(superseded=True)
    )
    # A row is kept even when nothing is sent, so the rate limits match.
    db.add(
        OtpCode(
            phone=phone,
            purpose=body.purpose,
            code_hash=security.hash_code(phone, body.purpose.value, code) if send else "-",
            sent_at=now,
            expires_at=now + timedelta(minutes=settings.otp_minutes),
            superseded=not send,
        )
    )
    audit.record(db, "otp.requested", actor_id=existing.id if existing else None,
                 target=body.purpose.value, request=request)
    db.commit()
    if send:
        language = existing.language if existing else "ar"
        sms.send_code(phone, code, language)
    return ticket


@router.post("/otp/verify", response_model=schemas.PhoneProof)
def verify_code(
    body: schemas.OtpVerify,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> schemas.PhoneProof:
    """Checks a code; returns a single-use proof (10 minutes) that this phone
    received it. Five wrong tries kill the code."""
    phone = _phone(body.phone)
    now = clock.now()
    otp = db.scalar(
        select(OtpCode)
        .where(
            OtpCode.phone == phone,
            OtpCode.purpose == body.purpose,
            OtpCode.superseded.is_(False),
            OtpCode.verified_at.is_(None),
        )
        .order_by(OtpCode.sent_at.desc())
        .limit(1)
    )
    if otp is None or otp.expires_at <= now:
        raise ApiError(410, "code_expired")
    if otp.attempts >= settings.otp_max_attempts:
        raise ApiError(429, "too_many_attempts")
    code = body.code.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789"))
    if not security.codes_match(otp.code_hash, security.hash_code(phone, body.purpose.value, code)):
        otp.attempts += 1
        db.commit()
        if otp.attempts >= settings.otp_max_attempts:
            raise ApiError(429, "too_many_attempts")
        raise ApiError(400, "code_wrong", attempts_left=settings.otp_max_attempts - otp.attempts)
    otp.verified_at = now
    db.commit()
    return schemas.PhoneProof(
        phone_proof=security.phone_proof(otp.id, phone, body.purpose.value, now)
    )


def spend_proof(db: Session, proof: str, purpose: OtpPurpose) -> str:
    """Marks a phone proof used and returns its phone. Each proof works once."""
    now = clock.now()
    claims = security.decode(proof, "phone_proof", now)
    if claims is None or claims.get("purpose") != purpose.value:
        raise ApiError(410, "code_expired")
    otp = db.get(OtpCode, uuid.UUID(claims["jti"]))
    if otp is None or otp.verified_at is None or otp.used_at is not None or otp.phone != claims["phone"]:
        raise ApiError(410, "code_expired")
    otp.used_at = now
    return otp.phone


@router.post("/register", status_code=201, response_model=schemas.Session)
def register(
    body: schemas.Register, request: Request, db: Session = Depends(get_db)
) -> schemas.Session:
    _check_password(body.password)
    phone = spend_proof(db, body.phone_proof, OtpPurpose.sign_up)
    if _user_by_phone(db, phone) is not None:
        raise ApiError(409, "phone_taken")
    now = clock.now()
    user = User(
        phone=phone,
        phone_verified_at=now,
        password_hash=security.hash_password(body.password),
        language=body.language,
    )
    db.add(user)
    db.flush()
    audit.record(db, "account.created", actor_id=user.id, target="phone", request=request)
    session = tokens.issue(db, user)
    db.commit()
    return session


@router.post("/login", response_model=schemas.Session)
def login(
    body: schemas.Login,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> schemas.Session:
    """Phone + password. Five failures lock the account for 15 minutes."""
    phone = normalize_phone(body.phone)
    user = _user_by_phone(db, phone) if phone else None
    now = clock.now()
    if user is not None and user.locked_until is not None and user.locked_until > now:
        audit.record(db, "login.locked", actor_id=user.id, request=request)
        db.commit()
        raise ApiError(423, "account_locked", retry_after=int((user.locked_until - now).total_seconds()))
    ok = security.verify_password(body.password, user.password_hash if user else None)
    if user is None or not ok or not user.active:
        if user is not None and user.active:
            user.failed_logins += 1
            if user.failed_logins >= settings.login_max_failures:
                user.failed_logins = 0
                user.locked_until = now + timedelta(minutes=settings.lock_minutes)
                audit.record(db, "login.failed", actor_id=user.id, request=request)
                audit.record(db, "account.locked", actor_id=user.id, request=request)
                db.commit()
                raise ApiError(423, "account_locked", retry_after=settings.lock_minutes * 60)
        audit.record(db, "login.failed", actor_id=user.id if user else None, request=request)
        db.commit()
        raise ApiError(401, "wrong_credentials")
    user.failed_logins = 0
    user.locked_until = None
    audit.record(db, "login.succeeded", actor_id=user.id, target="password", request=request)
    session = tokens.issue(db, user)
    db.commit()
    return session


@router.post("/password/reset", response_model=schemas.Session)
def reset_password(
    body: schemas.ResetPassword, request: Request, db: Session = Depends(get_db)
) -> schemas.Session:
    """New password from a reset proof. Signs out every other session."""
    _check_password(body.password)
    phone = spend_proof(db, body.phone_proof, OtpPurpose.reset_password)
    user = _user_by_phone(db, phone)
    if user is None or not user.active:
        raise ApiError(410, "code_expired")
    user.password_hash = security.hash_password(body.password)
    user.failed_logins = 0
    user.locked_until = None
    tokens.revoke_all(db, user.id)
    audit.record(db, "password.reset", actor_id=user.id, request=request)
    session = tokens.issue(db, user)
    db.commit()
    return session


def _social_session(
    db: Session,
    request: Request,
    verifier: SocialVerifier,
    provider: Provider,
    token: str,
    language: str,
    apple_refresh: str | None = None,
) -> schemas.Session:
    try:
        identity = verifier.verify(provider, token)
    except SocialNotConfigured:
        raise ApiError(503, "social_unavailable") from None
    except SocialTokenInvalid:
        raise ApiError(401, "social_token_invalid") from None
    link = db.scalar(
        select(Identity).where(Identity.provider == provider, Identity.subject == identity.subject)
    )
    if link is None:
        user = User(email=identity.email, language=language)
        db.add(user)
        db.flush()
        link = Identity(user_id=user.id, provider=provider, subject=identity.subject)
        db.add(link)
        audit.record(db, "account.created", actor_id=user.id, target=provider.value, request=request)
    else:
        user = link.user
        if not user.active:
            raise ApiError(403, "account_deleted")
    if apple_refresh:
        link.apple_refresh_token = apple_refresh
    db.flush()
    db.refresh(user)
    audit.record(db, "login.succeeded", actor_id=user.id, target=provider.value, request=request)
    session = tokens.issue(db, user)
    db.commit()
    return session


@router.post("/google", response_model=schemas.Session)
def google(
    body: schemas.GoogleSignIn,
    request: Request,
    db: Session = Depends(get_db),
    verifier: SocialVerifier = Depends(get_social_verifier),
) -> schemas.Session:
    return _social_session(db, request, verifier, Provider.google, body.id_token, body.language)


@router.post("/apple", response_model=schemas.Session)
def apple(
    body: schemas.AppleSignIn,
    request: Request,
    db: Session = Depends(get_db),
    verifier: SocialVerifier = Depends(get_social_verifier),
    apple_tokens: AppleTokens = Depends(get_apple_tokens),
) -> schemas.Session:
    refresh = apple_tokens.exchange(body.authorization_code) if body.authorization_code else None
    return _social_session(
        db, request, verifier, Provider.apple, body.identity_token, body.language, refresh
    )


@router.post("/refresh", response_model=schemas.Session)
def refresh(body: schemas.Refresh, request: Request, db: Session = Depends(get_db)) -> schemas.Session:
    """Swaps a refresh token for a new pair. A token is good once: using a
    spent one (a sign of theft) signs out that whole login."""
    now = clock.now()
    row = tokens.find(db, body.refresh_token)
    if row is None or row.expires_at <= now:
        raise ApiError(401, "token_invalid")
    if row.revoked_at is not None:
        db.execute(
            update(type(row))
            .where(type(row).family_id == row.family_id, type(row).revoked_at.is_(None))
            .values(revoked_at=now)
        )
        audit.record(db, "token.reused", actor_id=row.user_id, request=request)
        db.commit()
        raise ApiError(401, "token_invalid")
    user = db.get(User, row.user_id)
    if user is None or not user.active:
        raise ApiError(401, "token_invalid")
    row.revoked_at = now
    session = tokens.issue(db, user, family_id=row.family_id)
    db.commit()
    return session


@router.post("/logout", status_code=204)
def logout(body: schemas.Refresh, db: Session = Depends(get_db)) -> Response:
    row = tokens.find(db, body.refresh_token)
    if row is not None and row.revoked_at is None:
        row.revoked_at = clock.now()
        db.commit()
    return Response(status_code=204)
