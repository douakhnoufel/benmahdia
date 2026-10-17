import { useI18n } from '../i18n';
import { Button } from '../components/ui';

export function Loading() {
  const { t } = useI18n();
  return <p className="p-xl text-ink-muted">{t('loading')}</p>;
}

export function Failed({ onRetry }: { onRetry: () => void }) {
  const { t } = useI18n();
  return (
    <div className="flex flex-col items-start gap-md p-xl">
      <p className="text-danger">{t('offline')}</p>
      <Button variant="secondary" onClick={onRetry}>
        {t('retry')}
      </Button>
    </div>
  );
}
