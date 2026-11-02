import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut } from '../api';
import { I18nProvider } from '../i18n';
import { Export } from '../pages/Export';

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Export page', () => {
  it('downloads each sheet as the CSV file the server names', async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: URL) => {
        urls.push(String(input));
        return new Response('\ufeffpatient_id\r\n', {
          status: 200,
          headers: { 'content-disposition': 'attachment; filename="benmahdia-patients-2026-11-02.csv"' },
        });
      }),
    );
    const created = vi.fn(() => 'blob:x');
    URL.createObjectURL = created;
    URL.revokeObjectURL = vi.fn();
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => undefined);
    let downloaded = '';
    click.mockImplementation(function (this: HTMLAnchorElement) {
      downloaded = this.download;
    });

    render(
      <I18nProvider initial="fr">
        <Export />
      </I18nProvider>,
    );
    expect(screen.getByText(/aucune donnée médicale/)).toBeInTheDocument();
    await userEvent.click(screen.getAllByRole('button', { name: 'Télécharger' })[0]);
    expect(urls[0]).toMatch(/v1\/admin\/export\/patients\.csv$/);
    expect(downloaded).toBe('benmahdia-patients-2026-11-02.csv');
    expect(created).toHaveBeenCalledOnce();
  });

  it('says so when the export fails', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ detail: { code: 'forbidden' } }), { status: 403 })));
    render(
      <I18nProvider initial="ar">
        <Export />
      </I18nProvider>,
    );
    await userEvent.click(screen.getAllByRole('button', { name: 'تنزيل' })[1]);
    expect(await screen.findByRole('alert')).toHaveTextContent('تعذّر التصدير');
  });
});
