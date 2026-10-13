# BenMahdia — project rules
- Source of truth: docs/PRD.md and docs/DESIGN.md. Never invent features; ask me.
- Monorepo: apps/mobile (Flutter, Riverpod), apps/dashboard (React + TypeScript + Vite + Tailwind + shadcn), backend (FastAPI + PostgreSQL + Alembic), infra (Docker Compose + Nginx).
- Colors, fonts and spacing only from design tokens. Arabic RTL + French on every screen.
- A patient sees only their own data; a doctor only their own patients. Enforce it in the API.
- The AI never shows a diagnosis to the patient. No medical content in notifications or logs.
- No real patient data. Secrets only in .env. Tests for every backend endpoint. Small commits.
- Show me a plan before any big change.
