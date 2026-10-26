import json
import logging
import uuid

from fastapi import APIRouter, Depends, Header, Request, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, checkin, notices
from ..chargily import Chargily, get_chargily
from ..clock import clock
from ..db import get_db
from ..deps import verified_patient
from ..errors import ApiError
from ..models import (
    Appointment,
    AppointmentStatus,
    Payment,
    PaymentMethod,
    PaymentStatus,
    User,
)

log = logging.getLogger("benmahdia.payments")

router = APIRouter(tags=["payments"])


class CheckoutIn(BaseModel):
    method: PaymentMethod


class CheckoutOut(BaseModel):
    payment_id: uuid.UUID
    checkout_url: str


@router.post("/v1/appointments/{appointment_id}/checkout", response_model=CheckoutOut, status_code=201)
def checkout(
    appointment_id: uuid.UUID,
    body: CheckoutIn,
    request: Request,
    patient: User = Depends(verified_patient),
    db: Session = Depends(get_db),
    chargily: Chargily = Depends(get_chargily),
) -> CheckoutOut:
    """Opens a Chargily checkout for a held slot. The appointment is confirmed
    later, only by Chargily's signed webhook (PRD 4.4)."""
    if body.method not in (PaymentMethod.cib, PaymentMethod.edahabia):
        raise ApiError(400, "payment_method_unavailable")
    a = db.get(Appointment, appointment_id)
    if a is None or a.patient_id != patient.id:
        raise ApiError(404, "appointment_not_found")
    if a.status != AppointmentStatus.awaiting_payment:
        raise ApiError(409, "not_a_hold")
    if a.hold_expires_at is None or a.hold_expires_at <= clock.now():
        raise ApiError(409, "hold_expired")
    co = chargily.create_checkout(
        amount_dzd=a.price_dzd,
        method=body.method.value,
        locale=patient.language,
        appointment_id=str(a.id),
        description=f"BenMahdia {a.id}",
    )
    payment = Payment(
        id=uuid.uuid4(),
        appointment_id=a.id,
        patient_id=patient.id,
        amount_dzd=a.price_dzd,
        method=body.method,
        chargily_id=co.id,
    )
    db.add(payment)
    audit.record(db, "payment.checkout", actor_id=patient.id, target=str(payment.id), request=request)
    db.commit()
    return CheckoutOut(payment_id=payment.id, checkout_url=co.url)


@router.post("/v1/payments/chargily/webhook", status_code=200)
async def webhook(
    request: Request,
    signature: str | None = Header(default=None),
    db: Session = Depends(get_db),
    chargily: Chargily = Depends(get_chargily),
) -> Response:
    """Chargily's event about a checkout. Unsigned or wrongly signed calls are
    refused; the same event twice changes nothing the second time."""
    raw = await request.body()
    if not chargily.signature_ok(raw, signature):
        raise ApiError(403, "bad_signature")
    try:
        event = json.loads(raw)
        kind = event["type"]
        checkout_id = str(event["data"]["id"])
    except (ValueError, KeyError, TypeError):
        raise ApiError(400, "bad_event")

    payment = db.scalar(select(Payment).where(Payment.chargily_id == checkout_id))
    if payment is None or payment.status != PaymentStatus.pending:
        # Not ours, or already handled: acknowledge so Chargily stops retrying.
        return Response(status_code=200)

    now = clock.now()
    a = db.get(Appointment, payment.appointment_id) if payment.appointment_id else None
    if kind == "checkout.paid":
        payment.status = PaymentStatus.paid
        payment.paid_at = now
        if a is not None and a.status == AppointmentStatus.awaiting_payment:
            a.status = AppointmentStatus.confirmed
            a.method = payment.method
            a.hold_expires_at = None
            a.paid_at = now
            checkin.issue(db, a)
            notices.booking_alert(db, a, notices.CONFIRMED)
            audit.record(db, "appointment.confirmed", target=str(a.id))
        else:
            # The slot was lost before the money arrived: the clinic refunds.
            log.warning("paid checkout without a held slot: payment %s", payment.id)
            audit.record(db, "payment.needs_refund", target=str(payment.id))
    elif kind in ("checkout.failed", "checkout.canceled", "checkout.expired"):
        payment.status = PaymentStatus.failed
        if a is not None and a.status == AppointmentStatus.awaiting_payment:
            # A failed or abandoned payment gives the slot back (PRD 4.4).
            db.delete(a)
    else:
        return Response(status_code=200)
    audit.record(db, f"payment.{payment.status.value}", target=str(payment.id))
    db.commit()
    return Response(status_code=200)


@router.get("/v1/payments/return", response_class=HTMLResponse, include_in_schema=False)
def payment_return(result: str = "success") -> HTMLResponse:
    """Where Chargily sends the browser after paying. The app learns the real
    outcome from the server, never from this page."""
    ok = result == "success"
    ar = "تم الدفع، يمكنك العودة إلى التطبيق." if ok else "لم يتم الدفع. عد إلى التطبيق للمحاولة مجددا."
    fr = "Paiement reçu, vous pouvez revenir à l'application." if ok else "Paiement non abouti. Revenez à l'application pour réessayer."
    html = (
        "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width'>"
        f"<title>BenMahdia</title><p dir='rtl' lang='ar'>{ar}</p><p lang='fr'>{fr}</p>"
    )
    return HTMLResponse(html)
