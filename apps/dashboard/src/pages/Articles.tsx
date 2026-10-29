import { useState, type FormEvent } from 'react';
import { api, type AddictionType, type ArticleInput, type ArticleSummary, type ArticleTopic } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Badge, Button, Card, Input, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { TYPE_KEY } from './PatientDetail';
import { Failed, Loading } from './Status';

export const TOPIC_KEY = {
  addiction: 'topicAddiction',
  cravings: 'topicCravings',
  relapse: 'topicRelapse',
  medication: 'topicMedication',
  family: 'topicFamily',
  motivation: 'topicMotivation',
} as const satisfies Record<ArticleTopic, StringKey>;

const TOPICS = Object.keys(TOPIC_KEY) as ArticleTopic[];
const TYPES = Object.keys(TYPE_KEY) as AddictionType[];

/** Editing: null = the list, 'new' = a blank article, otherwise its id. */
type Editing = null | 'new' | string;

/** The clinic's article library (PRD 5.5, 7): doctors write, edit and publish
 * the articles patients read in the app. Any doctor may edit any article. */
export function Articles() {
  const [editing, setEditing] = useState<Editing>(null);
  if (editing !== null) return <Editor id={editing} onDone={() => setEditing(null)} />;
  return <List onEdit={setEditing} />;
}

function List({ onEdit }: { onEdit: (id: Editing) => void }) {
  const { t, date } = useI18n();
  const { load, reload } = useLoad(() => api.articles(), []);
  return (
    <section className="flex flex-col gap-lg">
      <div>
        <Button onClick={() => onEdit('new')}>{t('newArticle')}</Button>
      </div>
      <Card className="p-0">
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && load.data.length === 0 && <p className="p-xl text-ink-muted">{t('noArticles')}</p>}
        {load.state === 'ready' &&
          load.data.map((a: ArticleSummary) => (
            <article key={a.id} className="flex flex-wrap items-center gap-md border-b border-border p-md last:border-0">
              <div className="flex min-w-[12rem] flex-1 flex-col gap-xs">
                <span className="text-body-lg text-ink-strong" dir={a.language === 'ar' ? 'rtl' : 'ltr'}>
                  {a.title}
                </span>
                <span className="text-caption text-ink-muted">
                  {t(TOPIC_KEY[a.topic])} · {t(a.language === 'ar' ? 'langAr' : 'langFr')} ·{' '}
                  {a.addiction_type ? t(TYPE_KEY[a.addiction_type]) : t('articleForAll')} ·{' '}
                  {t('updatedOn').replace('{d}', date(a.updated_at))}
                </span>
              </div>
              <Badge tone={a.published ? 'success' : 'neutral'}>
                {t(a.published ? 'articlePublished' : 'articleDraft')}
              </Badge>
              <Button variant="secondary" onClick={() => onEdit(a.id)}>
                {t('edit')}
              </Button>
            </article>
          ))}
      </Card>
    </section>
  );
}

function blank(lang: 'ar' | 'fr'): ArticleInput {
  return { title: '', body: '', language: lang, topic: 'addiction', addiction_type: null, published: false };
}

function Editor({ id, onDone }: { id: 'new' | string; onDone: () => void }) {
  const { t, lang } = useI18n();
  const { load, reload } = useLoad<ArticleInput>(
    () =>
      id === 'new'
        ? Promise.resolve(blank(lang))
        : api.article(id).then(({ title, body, language, topic, addiction_type, published }) => ({
            title,
            body,
            language,
            topic,
            addiction_type,
            published,
          })),
    [id],
  );
  return (
    <section className="flex flex-col gap-lg">
      <div>
        <Button variant="ghost" onClick={onDone}>
          {t('back')}
        </Button>
      </div>
      <Card>
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && <Form id={id} initial={load.data} onDone={onDone} />}
      </Card>
    </section>
  );
}

function Form({ id, initial, onDone }: { id: 'new' | string; initial: ArticleInput; onDone: () => void }) {
  const { t } = useI18n();
  const [form, setForm] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const dir = form.language === 'ar' ? 'rtl' : 'ltr';

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setFailed(false);
    try {
      if (id === 'new') await api.createArticle(form);
      else await api.updateArticle(id, form);
      onDone();
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  const select = 'min-h-[44px] rounded-field border border-border bg-surface px-md text-body text-ink-strong';

  return (
    <form onSubmit={submit} className="flex flex-col gap-lg">
      <div className="grid gap-md sm:grid-cols-3">
        <label className="flex flex-col gap-xs text-label text-ink-strong">
          {t('articleLanguage')}
          <select className={select} value={form.language}
            onChange={(e) => setForm({ ...form, language: e.target.value as 'ar' | 'fr' })}>
            <option value="ar">{t('langAr')}</option>
            <option value="fr">{t('langFr')}</option>
          </select>
        </label>
        <label className="flex flex-col gap-xs text-label text-ink-strong">
          {t('articleTopic')}
          <select className={select} value={form.topic}
            onChange={(e) => setForm({ ...form, topic: e.target.value as ArticleTopic })}>
            {TOPICS.map((k) => (
              <option key={k} value={k}>{t(TOPIC_KEY[k])}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-xs text-label text-ink-strong">
          {t('articleFor')}
          <select className={select} value={form.addiction_type ?? ''}
            onChange={(e) => setForm({ ...form, addiction_type: (e.target.value || null) as AddictionType | null })}>
            <option value="">{t('articleForAll')}</option>
            {TYPES.map((k) => (
              <option key={k} value={k}>{t(TYPE_KEY[k])}</option>
            ))}
          </select>
        </label>
      </div>
      <Input label={t('articleTitle')} required maxLength={160} dir={dir} value={form.title}
        onChange={(e) => setForm({ ...form, title: e.target.value })} />
      <label className="flex flex-col gap-xs text-label text-ink-strong">
        {t('articleBody')}
        <textarea
          required
          maxLength={20000}
          rows={14}
          dir={dir}
          className="rounded-field border border-border bg-surface p-md text-body text-ink-strong focus:border-teal-500 focus:outline-none"
          value={form.body}
          onChange={(e) => setForm({ ...form, body: e.target.value })}
        />
        <span className="text-caption text-ink-muted">{t('articleBodyHint')}</span>
      </label>
      <label className="flex items-center gap-sm text-label text-ink-strong">
        <input type="checkbox" checked={form.published} onChange={(e) => setForm({ ...form, published: e.target.checked })} />
        {t('publishNow')}
      </label>
      {failed && <Notice>{t('articleFailed')}</Notice>}
      <div>
        <Button type="submit" disabled={busy}>
          {t('saveArticle')}
        </Button>
      </div>
    </form>
  );
}
