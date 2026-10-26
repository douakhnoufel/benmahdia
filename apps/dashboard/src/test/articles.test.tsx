import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Articles } from '../pages/Articles';

const saved = {
  id: 'a1',
  title: 'Gérer une envie',
  body: 'Respirez.\n\nAppelez quelqu’un.',
  language: 'fr',
  topic: 'cravings',
  addiction_type: 'tobacco',
  published: true,
  published_at: '2026-10-17T10:00:00Z',
  updated_at: '2026-10-17T10:00:00Z',
};

type Call = { method: string; url: string; body: unknown };

/** A fake backend: lists [list], returns [saved] for one article, records writes. */
function backend(list: unknown[] = [saved]) {
  const calls: Call[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: URL, init: RequestInit) => {
      const call = { method: init.method ?? 'GET', url: String(url), body: init.body ? JSON.parse(String(init.body)) : null };
      calls.push(call);
      if (call.method === 'GET' && call.url.endsWith('/v1/staff/articles')) return new Response(JSON.stringify(list));
      return new Response(JSON.stringify({ ...saved, ...(call.body as object) }), { status: call.method === 'POST' ? 201 : 200 });
    }),
  );
  return calls;
}

function renderIn(lang: Lang) {
  return render(
    <I18nProvider initial={lang}>
      <Articles />
    </I18nProvider>,
  );
}

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Articles (PRD 5.5, 7)', () => {
  it('lists articles with their state, topic and audience', async () => {
    backend();
    renderIn('fr');
    expect(await screen.findByText('Gérer une envie')).toBeInTheDocument();
    expect(screen.getByText('Publié')).toBeInTheDocument();
    expect(screen.getByText(/Envies et déclencheurs/)).toHaveTextContent('Tabac');
  });

  it('says what to do when there is none, in Arabic', async () => {
    backend([]);
    renderIn('ar');
    expect(await screen.findByText('لا توجد مقالات. اكتب أول مقال لمرضاك.')).toBeInTheDocument();
  });

  it('writes a new article as a draft by default', async () => {
    const calls = backend([]);
    renderIn('fr');
    fireEvent.click(await screen.findByText('Nouvel article'));
    fireEvent.change(await screen.findByLabelText('Titre'), { target: { value: 'Parler à sa famille' } });
    fireEvent.change(screen.getByLabelText(/^Texte/), { target: { value: 'Choisissez un moment calme.' } });
    fireEvent.change(screen.getByLabelText('Rubrique'), { target: { value: 'family' } });
    fireEvent.click(screen.getByText('Enregistrer'));
    await screen.findByText('Nouvel article'); // back on the list
    const post = calls.find((c) => c.method === 'POST');
    expect(post?.url).toMatch(/\/v1\/staff\/articles$/);
    expect(post?.body).toEqual({
      title: 'Parler à sa famille',
      body: 'Choisissez un moment calme.',
      language: 'fr',
      topic: 'family',
      addiction_type: null,
      published: false,
    });
  });

  it('edits and unpublishes an article', async () => {
    const calls = backend();
    renderIn('fr');
    fireEvent.click(await screen.findByText('Modifier'));
    const publish = await screen.findByLabelText('Publier pour les patients');
    expect(publish).toBeChecked();
    fireEvent.click(publish);
    fireEvent.click(screen.getByText('Enregistrer'));
    await screen.findByText('Nouvel article');
    const put = calls.find((c) => c.method === 'PUT');
    expect(put?.url).toMatch(/\/v1\/staff\/articles\/a1$/);
    expect(put?.body).toMatchObject({ title: 'Gérer une envie', addiction_type: 'tobacco', published: false });
  });

  it('keeps the form and explains a refused save', async () => {
    backend([]);
    vi.stubGlobal(
      'fetch',
      vi.fn(async (_url: URL, init: RequestInit) =>
        init.method === 'POST'
          ? new Response(JSON.stringify({ detail: { code: 'validation' } }), { status: 422 })
          : new Response('[]'),
      ),
    );
    renderIn('fr');
    fireEvent.click(await screen.findByText('Nouvel article'));
    fireEvent.change(await screen.findByLabelText('Titre'), { target: { value: 'x' } });
    fireEvent.change(screen.getByLabelText(/^Texte/), { target: { value: 'y' } });
    fireEvent.click(screen.getByText('Enregistrer'));
    expect(await screen.findByText('Enregistrement impossible. Vérifiez le titre et le texte.')).toBeInTheDocument();
    expect(screen.getByLabelText('Titre')).toHaveValue('x');
  });
});
