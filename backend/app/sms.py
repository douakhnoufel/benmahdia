import logging
from typing import Protocol

from .config import get_settings

log = logging.getLogger("benmahdia.sms")


class SmsSender(Protocol):
    def send_code(self, phone: str, code: str, language: str) -> None: ...


class ConsoleSmsSender:
    """Development only: prints the code to the API log instead of sending an
    SMS. Refused in production by Settings."""

    sent: list[tuple[str, str]]

    def __init__(self) -> None:
        self.sent = []

    def send_code(self, phone: str, code: str, language: str) -> None:
        self.sent.append((phone, code))
        log.warning("DEV SMS to %s: code %s", phone, code)


# TODO(sms): add the Algerian SMS gateway (PRD 4.1) as another SmsSender and
# select it with SMS_PROVIDER. Message text must stay generic: no clinic or
# medical wording.
_console = ConsoleSmsSender()


def get_sms_sender() -> SmsSender:
    provider = get_settings().sms_provider
    if provider == "console":
        return _console
    raise RuntimeError(f"Unknown SMS_PROVIDER {provider!r}")
