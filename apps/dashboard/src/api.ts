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

export type AddictionType = 'opioids' | 'cannabis' | 'alcohol' | 'tobacco' | 'pills' | 'gambling' | 'other';

/** What the patient entered, for the doctor to confirm or refuse (PRD 3). */
export type PatientAddiction = {
  id: string;
  type: AddictionType;
  substance: string | null;
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
  /** "relapse" or "missed_doses". Never carries medical content. */
  type: string;
  priority: string;
  read: boolean;
  created_at: string;
};

export const api = {
  async login(email: string, password: string) {
    const res = await raw('POST', 'v1/staff/login', { email, password });
    setSession(await parse<Session>(res));
  },
  agenda: (day: string) => request<AgendaItem[]>('GET', `v1/staff/agenda?day=${day}`),
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
  patientAddictions: (patientId: string) =>
    request<PatientAddiction[]>('GET', `v1/staff/patients/${patientId}/addictions`),
  reviewAddiction: (patientId: string, addictionId: string, decision: 'confirm' | 'reject') =>
    request<PatientAddiction>('POST', `v1/staff/patients/${patientId}/addictions/${addictionId}/${decision}`),
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
