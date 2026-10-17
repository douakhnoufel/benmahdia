from datetime import datetime, timezone


class Clock:
    """Current UTC time, naive (the database stores UTC without a zone).
    Tests freeze it with `clock.frozen = ...`."""

    frozen: datetime | None = None

    def now(self) -> datetime:
        if self.frozen is not None:
            return self.frozen
        return datetime.now(timezone.utc).replace(tzinfo=None)


clock = Clock()
