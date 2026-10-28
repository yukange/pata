import { useMemo, useRef, useState } from 'react';
import { CheckCircle2, Circle, Plus } from 'lucide-react';
import type { Task } from '../bindings/pata/internal/storage/markdown/models.js';
import { splitAndSortTasksForPicker } from './taskPicker';
import { activeTagQuery, parseQuickTask } from './quickCreate';

interface QuickCreateInputProps {
  placeholder: string;
  submitLabel: string;
  /** 已有全局标签（不带 #），用于末尾 # 补全。 */
  tagNames: string[];
  /** resolve = 输入已处理（清空）；reject = 保留输入并显示错误。 */
  onSubmit: (title: string, tags: string[]) => Promise<void>;
  disabled?: boolean;
  /** Only Today supplies these, to allow existing tasks to be added inline. */
  existingTasks?: Task[];
  planTaskIds?: string[];
  onSelectExisting?: (taskId: string) => Promise<boolean>;
}

interface Suggestion {
  name: string;
  isNew: boolean;
}

const MAX_SUGGESTIONS = 8;

export function QuickCreateInput({
  placeholder,
  submitLabel,
  tagNames,
  onSubmit,
  disabled = false,
  existingTasks,
  planTaskIds,
  onSelectExisting,
}: QuickCreateInputProps) {
  const [value, setValue] = useState('');
  const [caretAtEnd, setCaretAtEnd] = useState(true);
  const [focused, setFocused] = useState(false);
  const [dismissedFor, setDismissedFor] = useState<string | null>(null);
  const [active, setActive] = useState(0);
  const [activeTaskId, setActiveTaskId] = useState<string | null>(null);
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

  const taskSections = useMemo(() => {
    if (!existingTasks || !onSelectExisting) return { uncompletedTasks: [] as Task[], completedTasks: [] as Task[] };
    const titleQuery = parseQuickTask(value).title;
    const sections = splitAndSortTasksForPicker(existingTasks, planTaskIds ?? [], titleQuery);
    return {
      uncompletedTasks: sections.uncompletedTasks.slice(0, 5),
      // Keep completed tasks searchable, but do not suggest them when the input is empty.
      completedTasks: titleQuery.trim() ? sections.completedTasks.slice(0, 5) : [],
    };
  }, [existingTasks, planTaskIds, onSelectExisting, value]);
  const taskOptions = [...taskSections.uncompletedTasks, ...taskSections.completedTasks];
  const taskOpen = Boolean(onSelectExisting) && focused && !busy && !tagQuery && dismissedFor !== value && taskOptions.length > 0;
  // No default selection: typing and pressing Enter must still CREATE a task.
  const activeTaskIndex = taskOptions.findIndex((task) => task.id === activeTaskId);

  const syncCaret = (el: HTMLInputElement) =>
    setCaretAtEnd(el.selectionStart === el.value.length && el.selectionEnd === el.value.length);

  const pick = (s: Suggestion) => {
    if (!tagQuery) return;
    setValue(`${value.slice(0, tagQuery.start)}#${s.name} `);
    setCaretAtEnd(true);
    inputRef.current?.focus();
  };

  const selectExisting = async (taskId: string) => {
    if (!onSelectExisting || busyRef.current || disabled) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      if (!(await onSelectExisting(taskId))) {
        setError('加入计划失败，请重试');
        return;
      }
      setValue('');
      setActiveTaskId(null);
    } catch (err: any) {
      setError(`加入计划失败: ${err?.message || err}`);
    } finally {
      busyRef.current = false;
      setBusy(false);
      setTimeout(() => inputRef.current?.focus(), 0);
    }
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
      setActiveTaskId(null);
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
    if (taskOpen) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const next = e.key === 'ArrowDown'
          ? (activeTaskIndex + 1) % taskOptions.length
          : activeTaskIndex < 0 ? taskOptions.length - 1 : (activeTaskIndex + taskOptions.length - 1) % taskOptions.length;
        setActiveTaskId(taskOptions[next].id);
        return;
      }
      if (e.key === 'Enter' && activeTaskIndex >= 0) {
        e.preventDefault();
        void selectExisting(taskOptions[activeTaskIndex].id);
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        setActiveTaskId(null);
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
            aria-expanded={open || taskOpen}
            aria-autocomplete="list"
            value={value}
            onChange={(e) => {
              setValue(e.target.value);
              setActive(0);
              setActiveTaskId(null);
              setError(null);
              syncCaret(e.target);
            }}
            onSelect={(e) => syncCaret(e.currentTarget)}
            onKeyDown={onKeyDown}
            onFocus={() => setFocused(true)}
            onBlur={() => {
              setFocused(false);
              setActiveTaskId(null);
            }}
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
          {taskOpen && (
            <ul
              role="listbox"
              aria-label="已有任务"
              className="pata-pop absolute left-0 right-0 top-full mt-1 z-20 max-h-56 overflow-y-auto rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-900 shadow-lg py-1 text-xs"
            >
              {taskSections.uncompletedTasks.length > 0 && (
                <li role="presentation" className="px-3 pt-1.5 pb-1 text-[11px] text-muted-foreground">未完成</li>
              )}
              {taskSections.uncompletedTasks.map((task) => (
                <li
                  key={task.id}
                  role="option"
                  aria-selected={activeTaskId === task.id}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => void selectExisting(task.id)}
                  className={
                    'flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-stone-100 dark:hover:bg-stone-800 ' +
                    (activeTaskId === task.id ? 'bg-interaction-100/70 dark:bg-interaction-950/60' : '')
                  }
                >
                  <Circle className="w-3.5 h-3.5 shrink-0 text-stone-400" />
                  <span className="truncate min-w-0 flex-1 text-stone-800 dark:text-stone-200">{task.title}</span>
                  {(task.tags ?? []).slice(0, 2).map((tag) => (
                    <span key={tag} className="shrink-0 text-[11px] text-muted-foreground">#{tag}</span>
                  ))}
                </li>
              ))}
              {taskSections.completedTasks.length > 0 && (
                <li role="presentation" className="px-3 pt-2 pb-1 text-[11px] text-muted-foreground border-t border-[var(--pata-border)]">已完成</li>
              )}
              {taskSections.completedTasks.map((task) => (
                <li
                  key={task.id}
                  role="option"
                  aria-selected={activeTaskId === task.id}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => void selectExisting(task.id)}
                  className={
                    'flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-stone-100 dark:hover:bg-stone-800 ' +
                    (activeTaskId === task.id ? 'bg-interaction-100/70 dark:bg-interaction-950/60' : '')
                  }
                >
                  <CheckCircle2 className="w-3.5 h-3.5 shrink-0 text-stone-400" />
                  <span className="truncate min-w-0 flex-1 line-through text-muted-foreground">{task.title}</span>
                  {(task.tags ?? []).slice(0, 2).map((tag) => (
                    <span key={tag} className="shrink-0 text-[11px] text-muted-foreground">#{tag}</span>
                  ))}
                </li>
              ))}
              <li role="presentation" className="px-3 py-1.5 text-[11px] text-muted-foreground border-t border-[var(--pata-border)]">
                {value.trim() ? '↵ 创建新任务 · ↑↓ 选择已有任务' : '↑↓ 选择任务 · ↵ 加入今日'}
              </li>
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
