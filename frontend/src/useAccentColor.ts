import { useCallback, useEffect, useRef, useState } from 'react';
import * as VaultService from '../bindings/pata/internal/app/vaultservice';
import { Events } from '@wailsio/runtime';
import { applyAccent, validAccent } from './accentColor';

export function useAccentColor() {
  const [color, setColor] = useState(() => {
    try { const cached = localStorage.getItem('pata_accent_color'); return validAccent(cached) ? cached : ''; }
    catch { return ''; }
  });
  const [ready, setReady] = useState(false);
  const [status, setStatus] = useState<'loading' | 'saved' | 'saving' | 'failed'>('loading');
  const [error, setError] = useState('');
  const currentRef = useRef(color);
  const pendingRef = useRef<string | null>(null);
  const savingRef = useRef(false);
  const mountedRef = useRef(true);

  useEffect(() => { applyAccent(color); }, [color]);
  useEffect(() => Events.On('appearance:changed', () => {
    if (savingRef.current || pendingRef.current !== null) return;
    void VaultService.GetAccentColorPreference().then((saved) => {
      if (savingRef.current || pendingRef.current !== null || !validAccent(saved)) return;
      currentRef.current = saved; setColor(saved);
      try { localStorage.setItem('pata_accent_color', saved); } catch { /* 以磁盘偏好为准。 */ }
    }).catch(() => {});
  }), []);
  useEffect(() => {
    let cancelled = false;
    mountedRef.current = true;
    void VaultService.GetAccentColorPreference().then((saved) => {
      if (cancelled) return;
      if (!validAccent(saved)) throw new Error('无效颜色');
      currentRef.current = saved; setColor(saved); setStatus('saved');
      try { localStorage.setItem('pata_accent_color', saved); } catch { /* 磁盘偏好仍有效。 */ }
    }).catch(() => {
      if (!cancelled) { setStatus('failed'); setError('读取主题色失败。可重新选择颜色并保存。'); }
    }).finally(() => { if (!cancelled) setReady(true); });
    return () => { cancelled = true; mountedRef.current = false; };
  }, []);

  // 同时只提交一次写入；拖动选色器时合并等待中的颜色，最后一次选择始终最后保存。
  const save = useCallback(async () => {
    if (savingRef.current) return;
    savingRef.current = true;
    try {
      while (pendingRef.current !== null) {
        const next = pendingRef.current;
        pendingRef.current = null;
        try {
          await VaultService.SetAccentColorPreference(next);
          try { localStorage.setItem('pata_accent_color', next); } catch { /* 以应用配置为准。 */ }
          if (mountedRef.current && pendingRef.current === null) { setStatus('saved'); setError(''); }
        } catch {
          if (mountedRef.current && pendingRef.current === null) { setStatus('failed'); setError('主题色保存失败，当前预览仍保留，请重试。'); }
        }
      }
    } finally { savingRef.current = false; }
  }, []);

  const change = useCallback((next: string) => {
    if (!validAccent(next)) return;
    next = next.toLowerCase();
    currentRef.current = next; setColor(next); setStatus('saving'); setError('');
    pendingRef.current = next;
    void save();
  }, [save]);

  return { color, ready, status, error, change, retry: () => change(currentRef.current) };
}
