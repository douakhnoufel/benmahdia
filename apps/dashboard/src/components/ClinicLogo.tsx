import { useI18n } from '../i18n';

// The clinic's logo, copied from branding/clinic/logo.png.
export const CLINIC_LOGO_SRC = '/clinic-logo.png';

export function ClinicLogo({ size }: { size: 'sm' | 'lg' }) {
  const { t } = useI18n();
  const box = size === 'sm' ? 'h-2xl w-2xl' : 'h-3xl w-3xl';
  return <img src={CLINIC_LOGO_SRC} alt={t('clinicLogoAlt')} className={`${box} shrink-0 object-contain`} />;
}
