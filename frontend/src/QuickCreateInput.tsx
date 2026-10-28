import { useMemo, useRef, useState } from 'react';
import { Plus } from 'lucide-react';
import { activeTagQuery, parseQuickTask } from './quickCreate';

interface QuickCreateInputProps {
  placeholder: string;
  submitLabel: string;
  /** 已有全局标签（不带 #），用于末尾 # 补全。 */
  tagNames: string[];
  /** resolve = 输入已处理（清空）；reject = 保留输入并显示错误。 */
  onSubmit: (title: string, tags: string[]) => Promise<void>;
  disabled?: boolean;
}

interface Suggestion {
  name: string;
  isNew: boolean;
}

const MAX_SUGGESTIONS = 8;

export function QuickCreateInput({ placeholder, submitLabel, tagNames, onSubmit, disabled = false }: QuickCreateInputProps) {
  const [value, setValue] = useState('');
  const [caretAtEnd, setCaretAtEnd] = useState(true);
  const [focused, setFocused] = useState(false);
  const [dismissedFor, setDismissedFor] = useState<string | null>(null);
  const [active, setActive] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const busyRef = useRef(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const tagQuery = caretAtEnd ? activeTagQuery(value) : null;

  const suggestions = useMemo<Suggestion[]>(() => {
    if (!tagQuery) return [];
    const q = tagQuery.query.toLowerCase();
    const list: Suggestion[] = tagNames
      .filter((t) => t.toLowerCase().includes(q))
      .slice(0, MAX_SUGGESTIONS)
      .map((name) => ({ name, isNew: false }));
    if (q && !tagNames.some((t) => t.toLowerCase() === q)) list.push({ name: tagQuery.query, isNew: true });
    return list;
  }, [tagQuery, tagNames]);

  const open = focused && suggestions.length > 0 && dismissedFor !== value;
  const activeIdx = Math.min(active, Math.max(suggestions.length - 1, 0));

  const syncCaret = (el: HTMLInputElement) =>
    setCaretAtEnd(el.selectionStart === el.value.length && el.selectionEnd === el.value.length);

  const pick = (s: Suggestion) => {
    if (!tagQuery) return;
    setValue(`${value.slice(0, tagQuery.start)}#${s.name} `);
    setCaretAtEnd(true);
    inputRef.current?.focus();
  };

  const submit = async () => {
    if (busyRef.current || disabled) return;
    const { title, tags } = parseQuickTask(value);
    if (!title) {
      setError(tags.length > 0 ? '请填写任务名称（标签写在名称之后）' : null);
      return;
    }
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(title, tags);
      setValue('');
    } catch (err: any) {
      setError(`创建失败: ${err?.message || err}`);
    } finally {
      busyRef.current = false;
      setBusy(false);
      setTimeout(() => inputRef.current?.focus(), 0); // 输入框禁用期间会丢失焦点
    }
  };

  const onKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    // 输入法组合期间 Enter 只确认文字（keyCode 229 兼容 WebKit 在 compositionend 之后触发的 keydown）。
    if (e.nativeEvent.isComposing || e.keyCode === 229) return;
    if (open) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const n = suggestions.length;
        setActive((activeIdx + (e.key === 'ArrowDown' ? 1 : n - 1)) % n);
        return;
      }
      if (e.key === 'Tab' || e.key === 'Enter') {
        e.preventDefault();
        pick(suggestions[activeIdx]);
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        setDismissedFor(value);
        return;
      }
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      void submit();
    }
  };

  return (
    <div className="space-y-1">
      <div className="flex items-center space-x-2">
        <div className="relative flex-1">
          <input
            ref={inputRef}
            type="text"
            role="combobox"
            aria-expanded={open}
            aria-autocomplete="list"
            value={value}
            onChange={(e) => {
              setValue(e.target.value);
              setActive(0);
              setError(null);
              syncCaret(e.target);
            }}
            onSelect={(e) => syncCaret(e.currentTarget)}
            onKeyDown={onKeyDown}
            onFocus={() => setFocused(true)}
            onBlur={() => setFocused(false)}
            placeholder={placeholder}
            disabled={busy || disabled}
            className="w-full px-3 py-2 text-[13px] leading-4 rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-950 text-stone-900 dark:text-stone-100 placeholder:text-muted-foreground quick-entry shadow-2xs"
          />
          {open && (
            <ul
              role="listbox"
              className="pata-pop absolute left-0 right-0 top-full mt-1 z-20 max-h-56 overflow-y-auto rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-900 shadow-lg py-1 text-xs"
            >
              {suggestions.map((s, i) => (
                <li
                  key={`${s.isNew ? 'new' : 'tag'}-${s.name}`}
                  role="option"
                  aria-selected={i === activeIdx}
                  onMouseDown={(e) => {
                    e.preventDefault();
                    pick(s);
                  }}
                  onMouseEnter={() => setActive(i)}
                  className={`px-3 py-1.5 cursor-pointer ${
                    i === activeIdx
                      ? 'bg-interaction-100/70 dark:bg-interaction-950/60 text-interaction-900 dark:text-interaction-200'
                      : 'text-stone-700 dark:text-stone-300'
                  }`}
                >
                  {s.isNew ? `使用新标签「${s.name}」` : `#${s.name}`}
                </li>
              ))}
            </ul>
          )}
        </div>
        <button
          type="button"
          onMouseDown={(e) => {
            e.preventDefault();
          }}
          onClick={() => void submit()}
          disabled={busy || disabled || !value.trim()}
          className="flex items-center space-x-1 px-3 py-2 h-[34px] rounded-lg bg-[var(--pata-accent-solid)] hover:bg-[var(--pata-accent-solid-hover)] text-[var(--pata-accent-on-solid)] text-xs font-medium transition disabled:opacity-40 shadow-2xs shrink-0"
        >
          <Plus className="w-3.5 h-3.5" />
          <span>{busy ? '创建中' : submitLabel}</span>
        </button>
      </div>
      {error && <div className="text-[11px] text-rose-600 dark:text-rose-400 px-1 break-all">{error}</div>}
    </div>
  );
}
