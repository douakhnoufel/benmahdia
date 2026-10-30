import re

_EASTERN = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
_SEPARATORS = re.compile(r"[\s\-.()‎‏⁦-⁩]")
_MOBILE = re.compile(r"[567][0-9]{8}")


def normalize_phone(raw: str) -> str | None:
    """An Algerian mobile (05, 06, 07) as E.164 (+213…), or None. Accepts the
    same spellings as the app: 0550 12 34 56, +213 550…, 00213…, Arabic-Indic
    digits."""
    digits = _SEPARATORS.sub("", raw.translate(_EASTERN))
    if not re.fullmatch(r"\+?[0-9]+", digits):
        return None
    if digits.startswith("+213"):
        digits = digits[4:]
    elif digits.startswith("00213"):
        digits = digits[5:]
    elif digits.startswith("213") and len(digits) == 12:
        digits = digits[3:]
    if digits.startswith("0"):
        digits = digits[1:]
    return f"+213{digits}" if _MOBILE.fullmatch(digits) else None
