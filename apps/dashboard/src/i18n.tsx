import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

export type Lang = 'ar' | 'fr';

// Every visible string, in Arabic (default, RTL) and French.
const strings = {
  ar: {
    appName: 'بن مهدية — فضاء الطبيب',
    switchLang: 'Français',
    signIn: 'تسجيل الدخول',
    email: 'البريد الإلكتروني',
    password: 'كلمة المرور',
    wrongCredentials: 'البريد أو كلمة المرور غير صحيحة.',
    locked: 'تم قفل الحساب مؤقتا. حاول لاحقا.',
    offline: 'تعذر الاتصال بالخادم. حاول مجددا.',
    signOut: 'تسجيل الخروج',
    today: 'اليوم',
    patients: 'المرضى',
    signups: 'تسجيلات جديدة',
    previousDay: 'اليوم السابق',
    nextDay: 'اليوم التالي',
    noVisits: 'لا توجد مواعيد في هذا اليوم.',
    time: 'الوقت',
    patient: 'المريض',
    status: 'الحالة',
    payment: 'الدفع',
    actions: 'إجراءات',
    confirmed: 'مؤكد',
    completed: 'تم',
    no_show: 'غائب',
    cancelled: 'ملغى',
    awaiting_payment: 'في انتظار الدفع',
    markCompleted: 'تم الفحص',
    markNoShow: 'غائب',
    paid: 'مدفوع',
    unpaid: 'غير مدفوع',
    markPaid: 'تسجيل الدفع',
    markUnpaid: 'إلغاء الدفع',
    card: 'بطاقة',
    clinic: 'في العيادة',
    noPatients: 'لا يوجد مرضى بعد.',
    phone: 'الهاتف',
    visits: 'الزيارات',
    lastVisit: 'آخر زيارة',
    nextVisit: 'الزيارة القادمة',
    noSignups: 'لا توجد تسجيلات في الانتظار.',
    signedUp: 'تاريخ التسجيل',
    approve: 'قبول',
    reject: 'رفض',
    declaredNotice: 'تعرض هذه الصفحة ما صرّح به المريض فقط. تحقق من بطاقة الهوية الأصلية عند الاستقبال.',
    idNone: 'لم يصرّح بهويته بعد',
    idDeclared: 'هوية مصرّح بها',
    idDuplicate: 'هوية مرتبطة بحساب آخر',
    review: 'مراجعة',
    close: 'إغلاق',
    fullName: 'الاسم الكامل',
    birthDate: 'تاريخ الميلاد',
    document: 'الوثيقة',
    docNationalId: 'بطاقة التعريف الجزائرية',
    docPassport: 'جواز السفر الجزائري',
    submissionsCount: 'عدد الإرسالات',
    selfiePhoto: 'صورة المريض',
    selfieMissing: 'لا توجد صورة.',
    rejectReason: 'سبب الرفض (اختياري)',
    reviewReminder: 'قارن الصورة والبيانات ببطاقة الهوية الأصلية عند الاستقبال.',
    loading: 'جار التحميل…',
    retry: 'إعادة المحاولة',
    checkinTitle: 'تسجيل وصول مريض',
    checkinCode: 'رمز الحجز',
    checkinSubmit: 'تأكيد',
    checkinDone: 'تم تسجيل وصول المريض.',
    checkinIdReminder: 'تذكير: تحقق من بطاقة هوية المريض الأصلية.',
    checkinInvalid: 'رمز غير معروف. تحقق منه وأعد المحاولة.',
    checkinNotToday: 'هذا الرمز لموعد في يوم آخر.',
    checkinNotCheckable: 'لا يمكن تسجيل هذا الموعد (ملغى أو تمت معالجته).',
    checkinTooMany: 'رموز خاطئة كثيرة. انتظر بضع دقائق ثم أعد المحاولة.',
    checkinFailed: 'تعذر التسجيل. حاول مجددا.',
    arrived: 'وصل',
  },
  fr: {
    appName: 'BenMahdia — Espace médecin',
    switchLang: 'العربية',
    signIn: 'Se connecter',
    email: 'E-mail',
    password: 'Mot de passe',
    wrongCredentials: 'E-mail ou mot de passe incorrect.',
    locked: 'Compte bloqué temporairement. Réessayez plus tard.',
    offline: 'Impossible de joindre le serveur. Réessayez.',
    signOut: 'Se déconnecter',
    today: "Aujourd'hui",
    patients: 'Patients',
    signups: 'Nouveaux inscrits',
    previousDay: 'Jour précédent',
    nextDay: 'Jour suivant',
    noVisits: 'Aucun rendez-vous ce jour-là.',
    time: 'Heure',
    patient: 'Patient',
    status: 'Statut',
    payment: 'Paiement',
    actions: 'Actions',
    confirmed: 'Confirmé',
    completed: 'Effectué',
    no_show: 'Absent',
    cancelled: 'Annulé',
    awaiting_payment: 'En attente de paiement',
    markCompleted: 'Effectué',
    markNoShow: 'Absent',
    paid: 'Payé',
    unpaid: 'Impayé',
    markPaid: 'Marquer payé',
    markUnpaid: 'Marquer impayé',
    card: 'Carte',
    clinic: 'À la clinique',
    noPatients: 'Pas encore de patients.',
    phone: 'Téléphone',
    visits: 'Visites',
    lastVisit: 'Dernière visite',
    nextVisit: 'Prochaine visite',
    noSignups: 'Aucune inscription en attente.',
    signedUp: 'Inscrit le',
    approve: 'Approuver',
    reject: 'Refuser',
    declaredNotice: "Cette page montre ce que le patient a déclaré. Vérifiez la pièce d'identité originale à l'accueil.",
    idNone: "Pas encore d'identité déclarée",
    idDeclared: 'Identité déclarée',
    idDuplicate: 'Identité déjà liée à un autre compte',
    review: 'Examiner',
    close: 'Fermer',
    fullName: 'Nom complet',
    birthDate: 'Date de naissance',
    document: 'Document',
    docNationalId: "Carte d'identité algérienne",
    docPassport: 'Passeport algérien',
    submissionsCount: "Nombre d'envois",
    selfiePhoto: 'Photo du patient',
    selfieMissing: 'Aucune photo.',
    rejectReason: 'Motif du refus (facultatif)',
    reviewReminder: "Comparez la photo et les informations avec la pièce d'identité originale à l'accueil.",
    loading: 'Chargement…',
    retry: 'Réessayer',
    checkinTitle: "Enregistrer l'arrivée d'un patient",
    checkinCode: 'Code de réservation',
    checkinSubmit: 'Valider',
    checkinDone: 'Arrivée enregistrée.',
    checkinIdReminder: "Rappel : vérifiez la pièce d'identité originale du patient.",
    checkinInvalid: 'Code inconnu. Vérifiez-le et réessayez.',
    checkinNotToday: 'Ce code correspond à un rendez-vous un autre jour.',
    checkinNotCheckable: 'Ce rendez-vous ne peut plus être enregistré (annulé ou déjà traité).',
    checkinTooMany: 'Trop de codes erronés. Attendez quelques minutes avant de réessayer.',
    checkinFailed: "Enregistrement impossible. Réessayez.",
    arrived: 'Arrivé',
  },
} as const;

export type StringKey = keyof (typeof strings)['ar'];

type I18n = {
  lang: Lang;
  setLang: (lang: Lang) => void;
  t: (key: StringKey) => string;
  /** A UTC ISO instant as clinic time (Africa/Algiers). */
  time: (iso: string) => string;
  date: (iso: string) => string;
};

const I18nContext = createContext<I18n | null>(null);

const CLINIC_TZ = 'Africa/Algiers';

export function I18nProvider({ children, initial = 'ar' }: { children: ReactNode; initial?: Lang }) {
  const [lang, setLang] = useState<Lang>(initial);
  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }, [lang]);
  const locale = lang === 'ar' ? 'ar-DZ' : 'fr-DZ';
  const value: I18n = {
    lang,
    setLang,
    t: (key) => strings[lang][key],
    time: (iso) =>
      new Intl.DateTimeFormat(locale, { timeZone: CLINIC_TZ, hour: '2-digit', minute: '2-digit', hour12: false }).format(
        new Date(iso),
      ),
    date: (iso) =>
      new Intl.DateTimeFormat(locale, { timeZone: CLINIC_TZ, day: 'numeric', month: 'long', year: 'numeric' }).format(
        new Date(iso),
      ),
  };
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18n {
  const value = useContext(I18nContext);
  if (!value) throw new Error('useI18n outside I18nProvider');
  return value;
}
