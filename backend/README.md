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
| GET, POST | `/v1/me/addictions` | The patient's addictions (pending doctor review) / add one. |
| POST | `/v1/me/addictions/{id}/relapses` | Log a relapse: restarts the counter, keeps past streaks, alerts the doctor. |
| GET | `/v1/me/checkins` | Days ticked "without use" (last 60 days, or `since`). |
| PUT | `/v1/me/checkins/{day}` | Tick a day (today ± a small window). Idempotent. |
| GET, PUT | `/v1/me/reminder` | Daily-check reminder time `HH:MM` or `null`. |
| GET | `/v1/me/doses?day=` | The day's doses: due, taken, skipped or missed. |
| PUT | `/v1/me/doses` | Answer a dose: taken or skipped. |
| GET | `/v1/me/quote` | Quote of the day (ar + fr). |
| GET, POST, DELETE | `/v1/staff/patients/{id}/medications` | Doctor: list, prescribe, stop a medicine. |
| GET | `/v1/staff/patients/{id}/addictions` | Doctor: the patient's addictions with relapses. |
| POST | `/v1/staff/patients/{id}/addictions/{aid}/confirm` or `/reject` | Doctor reviews what the patient entered. |
| GET | `/v1/staff/alerts?unread=` | Doctor's alerts (relapse, missed doses). |
| POST | `/v1/staff/alerts/{id}/read` | Mark an alert read. |

Errors look like `{"detail": {"code": "wrong_credentials"}}`; the app maps each code to a message.

## Not done yet

- Real SMS gateway (only the console sender exists).
- Google / Apple client IDs and Apple keys: set them in `.env` once the developer accounts exist.
- Doctor / super-admin login with 2FA, doctor-side session revocation, notifying the doctor on deletion.
- Daily jobs run by `python -m app.jobs` (the `jobs` service in `infra/docker-compose.yml`, 00:10 Algiers time): `app.purge` and `app.alerts_job`. A Celery/Redis setup is only needed if more background work appears.
- Every patient is linked to a doctor only through booked appointments (no `primary_doctor_id` yet), so a relapse of a patient who never booked alerts nobody.
- Migrations 0008–0010 are tested on SQLite only; apply them to PostgreSQL before the pilot.
- Starter quotes (`app/quotes_seed.py`) are drafts for the clinic to approve.
