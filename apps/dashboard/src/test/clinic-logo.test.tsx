import { render, screen } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { CLINIC_LOGO_SRC, ClinicLogo } from '../components/ClinicLogo';
import { I18nProvider, type Lang } from '../i18n';
import { Login } from '../pages/Login';

function renderIn(ui: React.ReactNode, lang: Lang) {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

describe('clinic branding', () => {
  it('shows the clinic logo on the login page, in French', () => {
    renderIn(<Login />, 'fr');
    const logo = screen.getByRole('img', { name: 'Logo de la clinique' });
    expect(logo).toHaveAttribute('src', CLINIC_LOGO_SRC);
  });

  it('labels the clinic logo in Arabic', () => {
    renderIn(<ClinicLogo size="sm" />, 'ar');
    expect(screen.getByRole('img', { name: 'شعار العيادة' })).toHaveAttribute('src', CLINIC_LOGO_SRC);
  });

  it('uses the clinic logo as the favicon', () => {
    const html = readFileSync(resolve(__dirname, '../../index.html'), 'utf8');
    expect(html).toContain(`rel="icon" type="image/png" href="${CLINIC_LOGO_SRC}"`);
  });
});
