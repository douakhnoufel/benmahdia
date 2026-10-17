import uuid
from typing import Literal

from pydantic import BaseModel, Field

from .models import AccountStatus, OtpPurpose, Role

Language = Literal["ar", "fr"]


class OtpRequest(BaseModel):
    phone: str = Field(max_length=32)
    purpose: OtpPurpose


class OtpTicket(BaseModel):
    resend_after: int
    expires_in: int


class OtpVerify(BaseModel):
    phone: str = Field(max_length=32)
    purpose: OtpPurpose
    code: str = Field(min_length=4, max_length=8)


class PhoneProof(BaseModel):
    phone_proof: str


class Register(BaseModel):
    phone_proof: str
    password: str = Field(max_length=256)
    language: Language = "ar"


class Login(BaseModel):
    phone: str = Field(max_length=32)
    password: str = Field(max_length=256)


class ResetPassword(BaseModel):
    phone_proof: str
    password: str = Field(max_length=256)


class GoogleSignIn(BaseModel):
    id_token: str
    language: Language = "ar"


class AppleSignIn(BaseModel):
    identity_token: str
    # One-time code, exchanged for a token we can revoke on account deletion.
    authorization_code: str | None = None
    language: Language = "ar"


class Refresh(BaseModel):
    refresh_token: str


class DeleteAccount(BaseModel):
    # Required for accounts with a password.
    password: str | None = Field(default=None, max_length=256)


class Me(BaseModel):
    id: uuid.UUID
    role: Role
    status: AccountStatus
    phone: str | None
    language: str
    has_password: bool
    providers: list[str]


class Session(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: Me
