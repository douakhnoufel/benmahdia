# BenMahdia — doctor dashboard (MVP)

React + TypeScript + Vite + Tailwind (design tokens only), Arabic RTL and French.
Pages: sign-in, Today (agenda, completed / no-show, paid at the clinic), Patients (opens a patient's file: addictions to confirm or refuse, relapses, medicines to prescribe or stop), New sign-ups, Alerts (relapse, missed doses; unread count on the tab).

```bash
cp .env.example .env.local      # VITE_API_BASE_URL=http://localhost:8000/
npm install
npm run dev                     # http://localhost:5173
npm test                        # vitest
```

Sign-in account: run `SEED_DOCTOR_PASSWORD=... python -m app.seed` in `backend/`, then use
`dr.benmahdia@example.invalid`. The API must allow this origin (`CORS_ORIGINS` in `backend/.env`).

Not yet: 2FA (PRD 4.1, required before launch), ID photos on the sign-ups page,
availability editor, a quote library screen. UI pieces are hand-written in the shadcn style; the shadcn CLI
is not set up yet.

Tip: keep `node_modules` out of OneDrive (it syncs thousands of files and makes `npm install` very slow).
