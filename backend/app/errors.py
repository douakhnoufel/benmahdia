from fastapi import HTTPException


class ApiError(HTTPException):
    """An error with a stable machine-readable code the app translates:
    {"detail": {"code": "...", ...}}."""

    def __init__(self, status: int, code: str, **extra: object) -> None:
        headers = None
        if "retry_after" in extra:
            headers = {"Retry-After": str(extra["retry_after"])}
        super().__init__(status_code=status, detail={"code": code, **extra}, headers=headers)
