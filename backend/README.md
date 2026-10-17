# BenMahdia API

FastAPI + PostgreSQL. Accounts and sessions for patients (PRD 4.1, 12.1, 12.5).

## Run locally

```bash
cp backend/.env.example backend/.env          # from the repo root
docker compose -f infra/docker-compose.yml up --build
```

- API: http://localhost:8000 — interactive docs at http://localhost:8000/docs
- SMS codes are printed in the `api` container log (`SMS_PROVIDER=console`).

## Tests

```bash
cd backend
python -m venv .venv && . .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
pytest
```

Tests use an in-memory SQLite database and a frozen clock; no Docker needed.

## Endpoints

| Method | Path | What it does |
| --- | --- | --- |
| POST | `/v1/auth/otp/request` | Send a 6-digit SMS code (`sign_up`, `reset_password`, `attach_phone`). 60 s between codes, 5 per hour. |
| POST | `/v1/auth/otp/verify` | Check a code (5 tries, valid 5 min) → single-use `phone_proof` (10 min). |
| POST | `/v1/auth/register` | Phone + password account from a `sign_up` proof. |
| POST | `/v1/auth/login` | Phone + password. 5 failures lock the account for 15 min. |
| POST | `/v1/auth/password/reset` | New password from a `reset_password` proof; signs out other sessions. |
| POST | `/v1/auth/google` | Sign in with a Google ID token. |
| POST | `/v1/auth/apple` | Sign in with an Apple identity token (+ authorization code for revocation). |
| POST | `/v1/auth/refresh` | Rotate the refresh token. Reusing a spent one signs that login out. |
| POST | `/v1/auth/logout` | Revoke a refresh token. |
| GET | `/v1/me` | The signed-in account. |
| PUT | `/v1/me/phone` | Add a confirmed number (from an `attach_phone` proof). |
| DELETE | `/v1/me` | Delete the account (password required if it has one). Disabled at once; erased after 30 days by `python -m app.purge`. |

Errors look like `{"detail": {"code": "wrong_credentials"}}`; the app maps each code to a message.

## Not done yet

- Real SMS gateway (only the console sender exists).
- Google / Apple client IDs and Apple keys: set them in `.env` once the developer accounts exist.
- Doctor / super-admin login with 2FA, doctor-side session revocation, notifying the doctor on deletion.
- A scheduled job running `app.purge` daily (Celery/cron).
