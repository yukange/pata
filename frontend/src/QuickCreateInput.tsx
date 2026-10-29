import { useEffect, useMemo, useRef, useState } from 'react';
import { CheckCircle2, Circle, Plus, RefreshCw } from 'lucide-react';
import type { Task } from '../bindings/pata/internal/storage/markdown/models.js';
import { getInlineTaskCandidates } from './taskPicker';
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
  const [tab, setTab] = useState<'uncompleted' | 'completed'>('uncompleted');
  const [active, setActive] = useState(0);
  const [activeTaskId, setActiveTaskId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const busyRef = useRef(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const activeItemRef = useRef<HTMLLIElement>(null);

  useEffect(() => {
    if (activeTaskId && activeItemRef.current) {
      activeItemRef.current.scrollIntoView({ block: 'nearest' });
    }
  }, [activeTaskId]);

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

  const parsedTitle = parseQuickTask(value).title;
  const hasQuery = Boolean(parsedTitle.trim());

  const taskSections = useMemo(() => {
    if (!existingTasks || !onSelectExisting) {
      return { uncompletedTasks: [] as Task[], completedTasks: [] as Task[], searchResults: [] as Task[] };
    }
    return getInlineTaskCandidates(existingTasks, planTaskIds ?? [], parsedTitle);
  }, [existingTasks, planTaskIds, onSelectExisting, parsedTitle]);

  const taskOptions = hasQuery
    ? taskSections.searchResults
    : tab === 'uncompleted'
    ? taskSections.uncompletedTasks
    : taskSections.completedTasks;

  const hasAvailableTasks = hasQuery
    ? taskSections.searchResults.length > 0
    : taskSections.uncompletedTasks.length > 0 || taskSections.completedTasks.length > 0;

  const taskOpen = Boolean(onSelectExisting) && focused && !busy && !tagQuery && dismissedFor !== value && hasAvailableTasks;
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
    const currentIndex = taskOptions.findIndex((t) => t.id === taskId);
    const targetIndex = currentIndex >= 0 ? currentIndex : 0;
    const remaining = taskOptions.filter((t) => t.id !== taskId);
    const nextTaskId =
      remaining.length > 0 ? remaining[Math.min(targetIndex, remaining.length - 1)].id : null;

    busyRef.current = true;
    setError(null);
    try {
      if (!(await onSelectExisting(taskId))) {
        setError('加入计划失败，请重试');
        return;
      }
      setValue('');
      setActiveTaskId(nextTaskId);
      setDismissedFor(null);
    } catch (err: any) {
      setError(`加入计划失败: ${err?.message || err}`);
    } finally {
      busyRef.current = false;
      inputRef.current?.focus();
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
      setDismissedFor(null);
      setTab('uncompleted');
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
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      setActiveTaskId(null);
      setDismissedFor(null);
      inputRef.current?.blur();
      return;
    }
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
    }
    if (taskOpen) {
      if (!hasQuery) {
        if (e.key === 'ArrowRight' && tab === 'uncompleted') {
          e.preventDefault();
          setTab('completed');
          const nextTasks = taskSections.completedTasks;
          if (nextTasks.length > 0 && activeTaskIndex >= 0) {
            const nextIdx = Math.min(activeTaskIndex, nextTasks.length - 1);
            setActiveTaskId(nextTasks[nextIdx].id);
          } else {
            setActiveTaskId(null);
          }
          return;
        }
        if (e.key === 'ArrowLeft' && tab === 'completed') {
          e.preventDefault();
          setTab('uncompleted');
          const nextTasks = taskSections.uncompletedTasks;
          if (nextTasks.length > 0 && activeTaskIndex >= 0) {
            const nextIdx = Math.min(activeTaskIndex, nextTasks.length - 1);
            setActiveTaskId(nextTasks[nextIdx].id);
          } else {
            setActiveTaskId(null);
          }
          return;
        }
      }
      if (taskOptions.length > 0 && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
        e.preventDefault();
        const next = e.key === 'ArrowDown'
          ? (activeTaskIndex < 0 ? 0 : Math.min(activeTaskIndex + 1, taskOptions.length - 1))
          : Math.max(activeTaskIndex - 1, 0);
        setActiveTaskId(taskOptions[next].id);
        return;
      }
      if (e.key === 'Enter' && activeTaskIndex >= 0) {
        e.preventDefault();
        void selectExisting(taskOptions[activeTaskIndex].id);
        return;
      }
      if (e.key === 'Enter' && !hasQuery && taskOptions.length > 0) {
        e.preventDefault();
        void selectExisting(taskOptions[0].id);
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
      <div className="relative">
        <div
          onClick={() => inputRef.current?.focus()}
          className="flex items-center rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-950 pl-3 pr-1.5 py-1 focus-within:border-[var(--pata-accent-focus)] focus-within:ring-0 transition shadow-2xs cursor-text"
        >
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
              setDismissedFor(null);
            }}
            placeholder={placeholder}
            disabled={busy || disabled}
            className="flex-1 min-w-0 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 text-[13px] leading-4 text-stone-900 dark:text-stone-100 placeholder:text-muted-foreground quick-entry py-1"
          />
          <button
            type="button"
            onMouseDown={(e) => {
              e.preventDefault();
            }}
            onClick={() => void submit()}
            disabled={busy || disabled || !value.trim()}
            className="flex items-center space-x-1 px-2.5 py-1 rounded-md bg-[var(--pata-accent-solid)] hover:bg-[var(--pata-accent-solid-hover)] text-[var(--pata-accent-on-solid)] text-xs font-medium transition disabled:opacity-40 shadow-2xs shrink-0 cursor-pointer disabled:cursor-not-allowed"
          >
            {busy ? (
              <RefreshCw className="w-3.5 h-3.5 animate-spin shrink-0" />
            ) : (
              <Plus className="w-3.5 h-3.5 shrink-0" />
            )}
            <span>{busy ? '创建中' : submitLabel}</span>
          </button>
        </div>
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
          <div
            onMouseDown={(e) => {
              // 防止点击下拉内部（空白处、滚动条、Tab 栏等）导致 input 失焦
              e.preventDefault();
            }}
            className="pata-pop absolute left-0 right-0 top-full mt-1 z-20 rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-900 shadow-lg text-xs overflow-hidden"
          >
            {!hasQuery && (
              <div
                role="tablist"
                aria-label="任务状态分类"
                className="flex items-center gap-1 px-2 pt-1.5 pb-0.5"
              >
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === 'uncompleted'}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => {
                    setTab('uncompleted');
                    setActiveTaskId(null);
                  }}
                  className={
                    'px-2.5 py-1 rounded-md text-xs font-medium transition cursor-pointer select-none ' +
                    (tab === 'uncompleted'
                      ? 'bg-stone-100 dark:bg-stone-800 text-stone-900 dark:text-stone-100 font-semibold'
                      : 'text-muted-foreground hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-50 dark:hover:bg-stone-800/40')
                  }
                >
                  未完成
                </button>
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === 'completed'}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => {
                    setTab('completed');
                    setActiveTaskId(null);
                  }}
                  className={
                    'px-2.5 py-1 rounded-md text-xs font-medium transition cursor-pointer select-none ' +
                    (tab === 'completed'
                      ? 'bg-stone-100 dark:bg-stone-800 text-stone-900 dark:text-stone-100 font-semibold'
                      : 'text-muted-foreground hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-50 dark:hover:bg-stone-800/40')
                  }
                >
                  已完成
                </button>
              </div>
            )}
            <ul
              role="listbox"
              aria-label="已有任务"
              className="max-h-56 overflow-y-auto py-1"
            >
              {taskOptions.length === 0 ? (
                <li role="presentation" className="px-3 py-3 text-center text-xs text-muted-foreground">
                  {tab === 'uncompleted' ? '暂无未完成任务' : '暂无已完成任务'}
                </li>
              ) : (
                taskOptions.map((task) => (
                  <li
                    key={task.id}
                    ref={activeTaskId === task.id ? activeItemRef : undefined}
                    role="option"
                    aria-selected={activeTaskId === task.id}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => void selectExisting(task.id)}
                    className={
                      'flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-stone-100 dark:hover:bg-stone-800 ' +
                      (activeTaskId === task.id ? 'bg-interaction-100/70 dark:bg-interaction-950/60' : '')
                    }
                  >
                    {task.status === 'done' ? (
                      <CheckCircle2 className="w-3.5 h-3.5 shrink-0 text-stone-400" />
                    ) : (
                      <Circle className="w-3.5 h-3.5 shrink-0 text-stone-400" />
                    )}
                    <span
                      className={
                        'truncate min-w-0 flex-1 ' +
                        (task.status === 'done'
                          ? 'line-through text-muted-foreground'
                          : 'text-stone-800 dark:text-stone-200')
                      }
                    >
                      {task.title}
                    </span>
                    {(task.tags ?? []).slice(0, 2).map((tag) => (
                      <span key={tag} className="shrink-0 text-[11px] text-muted-foreground">#{tag}</span>
                    ))}
                  </li>
                ))
              )}
            </ul>
            <div className="px-3 py-1.5 bg-stone-100/70 dark:bg-stone-950/70 border-t border-[var(--pata-border)] flex items-center justify-between text-[11px] text-muted-foreground select-none">
              <span>
                <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[11px]">
                  ↵
                </kbd>{' '}
                {hasQuery ? (activeTaskIndex >= 0 ? '加入已有' : '创建新任务') : '加入今日'}
              </span>
              <div className="flex items-center space-x-3">
                <span>
                  <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[11px]">
                    ↑
                  </kbd>{' '}
                  <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[11px]">
                    ↓
                  </kbd>{' '}
                  {hasQuery && activeTaskIndex < 0 ? '选择' : '移动'}
                </span>
                {!hasQuery && (
                  <span>
                    <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[11px]">
                      ←
                    </kbd>{' '}
                    <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[11px]">
                      →
                    </kbd>{' '}
                    分类
                  </span>
                )}
                <span>
                  <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[11px]">
                    ESC
                  </kbd>{' '}
                  关闭
                </span>
              </div>
            </div>
          </div>
        )}
      </div>
      {error && <div className="text-[11px] text-rose-600 dark:text-rose-400 px-1 break-all">{error}</div>}
    </div>
  );
}
