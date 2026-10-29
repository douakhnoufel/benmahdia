// Client for the BenMahdia API's doctor routes (backend/app/routers/staff.py).

const BASE = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? 'http://localhost:8000/';

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}

type Session = { access_token: string; refresh_token: string };

const KEY = 'benmahdia.session';

// Kept for this browser tab only: closing the tab signs the doctor out.
function load(): Session | null {
  try {
    const raw = sessionStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}

function save(session: Session | null) {
  try {
    if (session) sessionStorage.setItem(KEY, JSON.stringify(session));
    else sessionStorage.removeItem(KEY);
  } catch {
    // Storage blocked: the session lives in memory only.
  }
}

let session: Session | null = load();
const listeners = new Set<(signedIn: boolean) => void>();

function setSession(next: Session | null) {
  session = next;
  save(next);
  listeners.forEach((l) => l(next !== null));
}

export function isSignedIn() {
  return session !== null;
}

export function onSessionChange(listener: (signedIn: boolean) => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function signOut() {
  setSession(null);
}

async function raw(method: string, path: string, body?: unknown, token?: string): Promise<Response> {
  try {
    return await fetch(new URL(path, BASE), {
      method,
      headers: {
        'content-type': 'application/json',
        accept: 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, 'offline');
  }
}

async function parse<T>(res: Response): Promise<T> {
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) throw new ApiError(res.status, json?.detail?.code ?? 'unknown');
  return json as T;
}

async function refresh(): Promise<boolean> {
  if (!session) return false;
  const res = await raw('POST', 'v1/auth/refresh', { refresh_token: session.refresh_token });
  if (!res.ok) {
    setSession(null);
    return false;
  }
  setSession(await parse<Session>(res));
  return true;
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let res = await raw(method, path, body, session?.access_token);
  if (res.status === 401 && (await refresh())) {
    res = await raw(method, path, body, session?.access_token);
  }
  if (res.status === 401) setSession(null);
  return parse<T>(res);
}

/** Like [request], for a binary answer (the patient's selfie). */
async function requestBlob(path: string): Promise<Blob> {
  let res = await raw('GET', path, undefined, session?.access_token);
  if (res.status === 401 && (await refresh())) {
    res = await raw('GET', path, undefined, session?.access_token);
  }
  if (res.status === 401) setSession(null);
  if (!res.ok) return parse<never>(res);
  return res.blob();
}

/** Who is signed in. The super admin is also a doctor (PRD 3). */
export type Me = { id: string; role: 'doctor' | 'super_admin'; name_ar: string; name_fr: string };

export type AppointmentStatus = 'awaiting_payment' | 'confirmed' | 'completed' | 'cancelled' | 'no_show';

export type AgendaItem = {
  id: string;
  patient_id: string;
  patient_phone: string | null;
  start: string;
  end: string;
  status: AppointmentStatus;
  method: 'edahabia' | 'cib' | 'clinic' | null;
  price_dzd: number;
  paid: boolean;
  /** When the front desk accepted the patient's booking code, if it did. */
  checked_in_at?: string | null;
  /** Whose visit it is: the agenda is clinic-wide, only the visit's own doctor can act on it. */
  doctor_name_ar: string;
  doctor_name_fr: string;
  mine: boolean;
};

/** A slot held while the patient pays: a booking request, not a visit yet. */
export type HoldItem = {
  id: string;
  patient_id: string;
  patient_phone: string | null;
  start: string;
  end: string;
  doctor_name_ar: string;
  doctor_name_fr: string;
  mine: boolean;
  /** The slot is given back at this time if still unpaid. */
  expires_at: string;
  /** The card chosen at Chargily's checkout, once the patient opened it. */
  paying_by: 'edahabia' | 'cib' | 'clinic' | null;
};

/** One of a patient's visits in the clinic, as their doctor sees it. */
export type Visit = {
  id: string;
  start: string;
  end: string;
  status: AppointmentStatus;
  doctor_name_ar: string;
  doctor_name_fr: string;
  mine: boolean;
  paid: boolean;
  method: 'edahabia' | 'cib' | 'clinic' | null;
  price_dzd: number;
  /** Only ever true on the doctor's own visits. */
  has_note: boolean;
};

/** The doctor's private note after a visit; never shown to the patient or the AI. */
export type Note = { text: string | null; updated_at: string | null };

/** rate = completed / (completed + no_show); null before the first past visit. */
export type VisitHistory = {
  attendance: { completed: number; no_show: number; rate: number | null };
  appointments: Visit[];
};

export type PaymentMethod = 'edahabia' | 'cib' | 'clinic';

/** Proof of payment of a paid appointment (PRD 4.4): not a tax invoice, no medical content. */
export type Receipt = {
  number: string;
  appointment_id: string;
  doctor_name_ar: string;
  doctor_name_fr: string;
  start: string;
  amount_dzd: number;
  method: PaymentMethod;
  paid_at: string;
  /** Chargily's payment id for a card; null when paid at the clinic. */
  payment_ref: string | null;
};

export type PaymentRow = {
  id: string;
  start: string;
  doctor_name_ar: string;
  doctor_name_fr: string;
  mine: boolean;
  patient_phone: string | null;
  status: AppointmentStatus;
  method: PaymentMethod | null;
  price_dzd: number;
  paid: boolean;
  paid_at: string | null;
};

/** Unpaid counts only what is owed: a cancelled visit owes nothing. */
export type Payments = {
  rows: PaymentRow[];
  totals: { paid_count: number; paid_dzd: number; unpaid_count: number; unpaid_dzd: number };
};

export type Patient = {
  id: string;
  phone: string | null;
  visits: number;
  last_visit: string | null;
  next_visit: string | null;
};

export type Signup = {
  id: string;
  phone: string | null;
  created_at: string;
  /** What the patient declared from their ID: never "verified". */
  id_status?: 'none' | 'declared' | 'approved' | 'rejected';
  /** The patient tried an ID that belongs to another account. */
  duplicate_attempt?: boolean;
};

/** The decrypted declaration. The ID number is never available. */
export type Identity = {
  /** The document declared: the Algerian national ID card or passport. */
  id_type?: 'national_id' | 'passport';
  full_name: string;
  birth_date: string;
  declared_at: string;
  submissions: number;
  has_selfie: boolean;
};

export type AddictionType =
  | 'opioids'
  | 'cannabis'
  | 'alcohol'
  | 'tobacco'
  | 'pills'
  | 'stimulants'
  | 'gambling'
  | 'other';

/** How an addiction is tracked (PRD 5.6); null = generic. */
export type SubstanceProfile = 'nicotine' | 'thc' | 'pregabalin' | 'buprenorphine' | 'cocaine' | 'amphetamines';

export type Localized = { ar: string; fr: string };

/** What a substance profile's daily check rates, from the server's catalog. */
export type ProfileSpec = {
  key: SubstanceProfile;
  type: AddictionType;
  name: Localized;
  signals: { key: string; label: Localized }[];
};

/** One day's check for one addiction: craving and signals 1-5 (higher = harder). */
export type AddictionCheck = {
  addiction_id: string;
  day: string;
  used: boolean;
  craving: number;
  signals: Record<string, number>;
};

export type CheckChart = { days: number; checked_days: number; checks: AddictionCheck[] };

export type HabitKind = 'sport' | 'brush_teeth' | 'water' | 'reading' | 'call_family' | 'sleep' | 'custom';

/** A good habit and the days it was done over the last [days] (PRD 5.6). */
export type HabitSummary = { id: string; kind: HabitKind; text: string | null; days: number; done_days: number };

/** What the patient entered, for the doctor to confirm or refuse (PRD 3). */
export type PatientAddiction = {
  id: string;
  type: AddictionType;
  profile: SubstanceProfile | null;
  substance: string | null;
  /** The small goal the patient chose (null = automatic) and the current one, in days. */
  goal_days: number | null;
  goal: number;
  /** Start of the current streak, UTC ISO. */
  clean_since: string;
  longest_past_days: number;
  past_days: number;
  review_status: 'pending' | 'confirmed' | 'rejected';
  relapses: { at: string; note: string | null }[];
};

export type Medication = {
  id: string;
  name: string;
  amount: string;
  times: string[];
  start_date: string;
  end_date: string | null;
  instructions: string | null;
};

export type NewMedication = {
  name: string;
  amount: string;
  times: string[];
  start_date: string;
  end_date: string | null;
  instructions: string | null;
};

export type Alert = {
  id: string;
  patient_id: string;
  patient_phone: string | null;
  /** "relapse", "missed_doses", "craving_high", "no_checkin", booking events. Never carries medical content. */
  type: string;
  priority: string;
  read: boolean;
  created_at: string;
};

/** One weekly period of consultations. Monday = 0 ... Sunday = 6; minutes after midnight, clinic time. */
export type Window = { weekday: number; start_minute: number; end_minute: number };

export type BlockedDay = { id: string; day: string; reason: string | null };

/** A booked visit the current hours no longer cover. It is never moved or cancelled. */
export type Conflict = {
  appointment_id: string;
  start: string;
  patient_phone: string | null;
  reason: 'blocked_day' | 'outside_hours';
};

export type SlotMinutes = 5 | 10 | 15;

export type Availability = {
  slot_minutes: SlotMinutes;
  notice_hours: number;
  windows: Window[];
  blocked_days: BlockedDay[];
  conflicts: Conflict[];
};

/** A doctor as the super admin sets their price (PRD 4.4). */
export type AdminDoctor = { id: string; name_ar: string; name_fr: string; price_dzd: number; slot_minutes: number };

export const api = {
  async login(email: string, password: string) {
    const res = await raw('POST', 'v1/staff/login', { email, password });
    setSession(await parse<Session>(res));
  },
  me: () => request<Me>('GET', 'v1/staff/me'),
  availability: () => request<Availability>('GET', 'v1/staff/availability'),
  saveWindows: (windows: Window[]) => request<Availability>('PUT', 'v1/staff/availability/windows', { windows }),
  saveBookingSettings: (slot_minutes: SlotMinutes, notice_hours: number) =>
    request<Availability>('PUT', 'v1/staff/availability/settings', { slot_minutes, notice_hours }),
  blockDay: (day: string, reason: string | null) =>
    request<Availability>('POST', 'v1/staff/availability/blocked-days', { day, reason }),
  adminDoctors: () => request<AdminDoctor[]>('GET', 'v1/admin/doctors'),
  setPrice: (doctorId: string, price_dzd: number) =>
    request<AdminDoctor>('PUT', `v1/admin/doctors/${doctorId}/price`, { price_dzd }),
  unblockDay: (id: string) => request<Availability>('DELETE', `v1/staff/availability/blocked-days/${id}`),
  agenda: (day: string) => request<AgendaItem[]>('GET', `v1/staff/agenda?day=${day}`),
  holds: (day: string) => request<HoldItem[]>('GET', `v1/staff/holds?day=${day}`),
  setStatus: (id: string, status: 'completed' | 'no_show') =>
    request<AgendaItem>('POST', `v1/staff/appointments/${id}/status`, { status }),
  setPaid: (id: string, paid: boolean) => request<AgendaItem>('POST', `v1/staff/appointments/${id}/paid`, { paid }),
  checkin: (code: string) => request<AgendaItem>('POST', 'v1/staff/checkin', { code }),
  patients: () => request<Patient[]>('GET', 'v1/staff/patients'),
  signups: () => request<Signup[]>('GET', 'v1/staff/signups'),
  approve: (id: string) => request<Signup>('POST', `v1/staff/signups/${id}/approve`),
  reject: (id: string, reason?: string) =>
    request<Signup>('POST', `v1/staff/signups/${id}/reject`, reason ? { reason } : undefined),
  identity: (id: string) => request<Identity>('GET', `v1/staff/signups/${id}/identity`),
  patientAppointments: (patientId: string) =>
    request<VisitHistory>('GET', `v1/staff/patients/${patientId}/appointments`),
  receipt: (appointmentId: string) => request<Receipt>('GET', `v1/staff/appointments/${appointmentId}/receipt`),
  /** Clinic days, both included, at most 92 days. */
  payments: (from: string, to: string) => request<Payments>('GET', `v1/staff/payments?from=${from}&to=${to}`),
  note: (appointmentId: string) => request<Note>('GET', `v1/staff/appointments/${appointmentId}/note`),
  /** Empty text deletes the note. */
  saveNote: (appointmentId: string, text: string) =>
    request<Note>('PUT', `v1/staff/appointments/${appointmentId}/note`, { text }),
  patientAddictions: (patientId: string) =>
    request<PatientAddiction[]>('GET', `v1/staff/patients/${patientId}/addictions`),
  reviewAddiction: (patientId: string, addictionId: string, decision: 'confirm' | 'reject') =>
    request<PatientAddiction>('POST', `v1/staff/patients/${patientId}/addictions/${addictionId}/${decision}`),
  profiles: () => request<ProfileSpec[]>('GET', 'v1/staff/recovery/profiles'),
  setProfile: (patientId: string, addictionId: string, profile: SubstanceProfile | null) =>
    request<PatientAddiction>('PUT', `v1/staff/patients/${patientId}/addictions/${addictionId}/profile`, { profile }),
  addictionChecks: (patientId: string, addictionId: string, days = 30) =>
    request<CheckChart>('GET', `v1/staff/patients/${patientId}/addictions/${addictionId}/checks?days=${days}`),
  habits: (patientId: string) => request<HabitSummary[]>('GET', `v1/staff/patients/${patientId}/habits`),
  medications: (patientId: string) => request<Medication[]>('GET', `v1/staff/patients/${patientId}/medications`),
  prescribe: (patientId: string, medication: NewMedication) =>
    request<Medication>('POST', `v1/staff/patients/${patientId}/medications`, medication),
  stopMedication: (patientId: string, medicationId: string) =>
    request<null>('DELETE', `v1/staff/patients/${patientId}/medications/${medicationId}`),
  alerts: (unread = false) => request<Alert[]>('GET', `v1/staff/alerts${unread ? '?unread=true' : ''}`),
  markAlertRead: (id: string) => request<Alert>('POST', `v1/staff/alerts/${id}/read`),
  /** A temporary browser URL for the selfie; release it with URL.revokeObjectURL. */
  selfie: async (id: string) => URL.createObjectURL(await requestBlob(`v1/staff/signups/${id}/selfie`)),
};
