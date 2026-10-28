import { useEffect, useState } from 'react';
import { accentHex, accentRGB, DEFAULT_ACCENT, type RGB } from './accentColor';

interface Props {
  color: string;
  ready: boolean;
  status: 'loading' | 'saved' | 'saving' | 'failed';
  error: string;
  onChange: (color: string) => void;
  onRetry: () => void;
}

export function AccentColorSettings({ color, ready, status, error, onChange, onRetry }: Props) {
  const [channels, setChannels] = useState(() => accentRGB(color).map(String));
  const [invalid, setInvalid] = useState(false);
  useEffect(() => { setChannels(accentRGB(color).map(String)); setInvalid(false); }, [color]);
  const changeChannel = (index: number, value: string) => {
    const next = channels.map((channel, offset) => offset === index ? value : channel);
    setChannels(next);
    const valid = next.every((channel) => /^\d{1,3}$/.test(channel) && Number(channel) <= 255);
    setInvalid(!valid);
    if (valid) onChange(accentHex(next.map(Number) as RGB));
  };
  return <fieldset aria-label="主题强调色设置" disabled={!ready} className="space-y-3 pt-4 border-t border-stone-200/80 dark:border-stone-800/80">
    <div className="flex items-center justify-between gap-3">
      <span className="text-xs font-medium text-stone-700 dark:text-stone-300">主题强调色</span>
      <button type="button" onClick={() => { setChannels(accentRGB('').map(String)); setInvalid(false); onChange(''); }} className="text-xs text-stone-500 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 cursor-pointer">恢复默认颜色</button>
    </div>
    <div className="flex flex-wrap items-end gap-3">
      <label className="text-xs font-medium text-stone-700 dark:text-stone-300 space-y-1">
        <span className="block">选取颜色</span>
        <input type="color" aria-label="主题强调色" value={color || DEFAULT_ACCENT} onChange={(event) => onChange(event.target.value)} className="block w-12 h-9 p-0.5 rounded-md border border-stone-200 dark:border-stone-700 bg-transparent cursor-pointer" />
      </label>
      {['红色 R', '绿色 G', '蓝色 B'].map((label, index) => <label key={label} className="text-xs font-medium text-stone-700 dark:text-stone-300 space-y-1">
        <span className="block">{label}</span>
        <input type="number" aria-label={label} aria-invalid={invalid} min="0" max="255" step="1" value={channels[index]} onChange={(event) => changeChannel(index, event.target.value)}
          className="block w-20 h-9 px-2 rounded-md border border-stone-200 dark:border-stone-700 bg-white dark:bg-stone-950 text-stone-800 dark:text-stone-200 font-normal tabular-nums" />
      </label>)}
      <span className="pb-2 text-xs text-stone-500 dark:text-stone-400 font-mono">{(color || DEFAULT_ACCENT).toUpperCase()}</span>
    </div>
    {invalid && <p role="alert" className="text-xs text-rose-600 dark:text-rose-400">RGB 各项须为 0–255 的整数，当前输入尚未应用。</p>}
    <p aria-live="polite" className="sr-only">{status === 'loading' ? '读取主题色…' : status === 'saving' ? '正在保存…' : status === 'saved' ? color ? '已保存自定义颜色' : '使用默认颜色' : ''}</p>
    {error && <div role="alert" className="flex items-center gap-3 text-xs text-rose-600 dark:text-rose-400"><span>{error}</span><button type="button" onClick={onRetry} className="underline cursor-pointer shrink-0">重试保存</button></div>}
  </fieldset>;
}
