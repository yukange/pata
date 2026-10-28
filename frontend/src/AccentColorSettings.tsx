import { Monitor, Plus } from 'lucide-react';
import { DEFAULT_ACCENT } from './accentColor';

interface Props {
  color: string;
  ready: boolean;
  status: 'loading' | 'saved' | 'saving' | 'failed';
  error: string;
  onChange: (color: string) => void;
  onRetry: () => void;
}

const PRESET_COLORS = [
  { name: '蓝色', value: '#007aff' },
  { name: '紫色', value: '#af52de' },
  { name: '绿色', value: '#34c759' },
  { name: '橙色', value: '#ff9500' },
  { name: '粉色', value: '#ff2d55' },
  { name: '灰色', value: '#8e8e93' },
];

const buttonClass =
  'flex h-9 w-9 shrink-0 items-center justify-center rounded-full cursor-pointer transition-colors hover:bg-stone-100/60 dark:hover:bg-stone-800/60';

// Only outline the selected color itself, not the entire 36px click target.
const selectedSwatchClass =
  'ring-1 ring-stone-500 dark:ring-stone-400 ring-offset-2 ring-offset-white dark:ring-offset-stone-900';

export function AccentColorSettings({ color, ready, status, error, onChange, onRetry }: Props) {
  const isCustom = !!color && !PRESET_COLORS.some((preset) => preset.value === color.toLowerCase());

  return (
    <fieldset
      aria-label="主题强调色设置"
      disabled={!ready}
      className="space-y-2 border-t border-stone-200/80 dark:border-stone-800/80 pt-4"
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="text-xs font-medium text-stone-700 dark:text-stone-300">主题强调色</span>
        <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="选择主题强调色">
          <button
            type="button"
            title="跟随系统"
            aria-label="跟随系统强调色"
            aria-pressed={!color}
            onClick={() => onChange('')}
            className={[buttonClass, !color ? 'bg-stone-100 dark:bg-stone-800' : ''].join(' ')}
          >
            <Monitor className="h-4 w-4 text-stone-600 dark:text-stone-300" aria-hidden="true" />
          </button>
          {PRESET_COLORS.map((preset) => (
            <button
              key={preset.value}
              type="button"
              title={preset.name}
              aria-label={preset.name}
              aria-pressed={color.toLowerCase() === preset.value}
              onClick={() => onChange(preset.value)}
              className={buttonClass}
            >
              <span
                className={[
                  'h-6 w-6 rounded-full border border-black/10 dark:border-white/15',
                  color.toLowerCase() === preset.value ? selectedSwatchClass : '',
                ].join(' ')}
                style={{ backgroundColor: preset.value }}
                aria-hidden="true"
              />
            </button>
          ))}
          <label
            title={isCustom ? '自定义颜色：' + color.toUpperCase() : '自定义颜色'}
            className={[
              buttonClass,
              'relative has-[input:focus-visible]:outline-2 has-[input:focus-visible]:outline-offset-1 has-[input:focus-visible]:outline-stone-500',
            ].join(' ')}
          >
            {isCustom ? (
              <span
                className={['h-6 w-6 rounded-full border border-black/10 dark:border-white/15', selectedSwatchClass].join(' ')}
                style={{ backgroundColor: color }}
                aria-hidden="true"
              />
            ) : (
              <Plus className="h-4 w-4 text-stone-500 dark:text-stone-400" aria-hidden="true" />
            )}
            <input
              type="color"
              aria-label="自定义主题强调色"
              value={color || DEFAULT_ACCENT}
              onChange={(event) => onChange(event.target.value)}
              className="absolute inset-0 h-full w-full opacity-0 cursor-pointer"
            />
          </label>
        </div>
      </div>
      <p aria-live="polite" className="sr-only">
        {status === 'loading' ? '读取主题色…' : status === 'saving' ? '正在保存…' : status === 'saved' ? color ? '强调色已保存' : '跟随系统强调色' : ''}
      </p>
      {error && (
        <div role="alert" className="flex items-center gap-3 text-xs text-rose-600 dark:text-rose-400">
          <span>{error}</span>
          <button type="button" onClick={onRetry} className="shrink-0 underline cursor-pointer">重试保存</button>
        </div>
      )}
    </fieldset>
  );
}
