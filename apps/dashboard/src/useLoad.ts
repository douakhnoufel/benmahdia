import { useCallback, useEffect, useState } from 'react';
import { ApiError } from './api';

export type Load<T> =
  | { state: 'loading' }
  | { state: 'error'; code: string }
  | { state: 'ready'; data: T };

/** Runs [fetcher] when [deps] change; [reload] runs it again. */
export function useLoad<T>(fetcher: () => Promise<T>, deps: unknown[]) {
  const [load, setLoad] = useState<Load<T>>({ state: 'loading' });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const run = useCallback(fetcher, deps);
  const reload = useCallback(() => {
    let live = true;
    setLoad({ state: 'loading' });
    run().then(
      (data) => live && setLoad({ state: 'ready', data }),
      (e: unknown) => live && setLoad({ state: 'error', code: e instanceof ApiError ? e.code : 'unknown' }),
    );
    return () => {
      live = false;
    };
  }, [run]);
  useEffect(() => reload(), [reload]);
  return { load, reload, setLoad };
}
