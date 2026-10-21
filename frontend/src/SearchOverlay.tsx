import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
  Search,
  CheckSquare,
  FileText,
  MessageSquare,
  Paperclip,
  AlertCircle,
  Loader2,
  X,
  ExternalLink,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { SearchResultItem } from '../bindings/pata/internal/storage/markdown/models';

interface SearchOverlayProps {
  isOpen: boolean;
  onClose: () => void;
  onOpenTask: (taskId: string) => void;
  onOpenNote: (noteId: string) => void;
  onOpenTodayDate?: (date: string) => void;
  vaultOpen?: boolean;
}

export function SearchOverlay({
  isOpen,
  onClose,
  onOpenTask,
  onOpenNote,
  onOpenTodayDate,
  vaultOpen = true,
}: SearchOverlayProps) {
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<SearchResultItem[]>([]);
  const [activityTaskMap, setActivityTaskMap] = useState<Record<string, string>>({});
  const [selectedIndex, setSelectedIndex] = useState<number>(0);

  const seqRef = useRef(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const itemRefs = useRef<(HTMLDivElement | null)[]>([]);
  const previousActiveElementRef = useRef<HTMLElement | null>(null);

  // Reset or focus when overlay opens / closes
  useEffect(() => {
    if (isOpen) {
      previousActiveElementRef.current = document.activeElement as HTMLElement | null;
      const timer = setTimeout(() => {
        inputRef.current?.focus();
        inputRef.current?.select();
      }, 50);
      return () => clearTimeout(timer);
    } else {
      // Restore focus to triggering element
      if (previousActiveElementRef.current && typeof previousActiveElementRef.current.focus === 'function') {
        previousActiveElementRef.current.focus();
        previousActiveElementRef.current = null;
      }
      // Discard any in-flight requests and reset state
      ++seqRef.current;
      setQuery('');
      setResults([]);
      setActivityTaskMap({});
      setLoading(false);
      setSelectedIndex(0);
    }
  }, [isOpen]);

  // Debounced search with sequence token race-condition guard
  useEffect(() => {
    if (!isOpen) return;

    const trimmed = query.trim();
    if (!trimmed) {
      ++seqRef.current;
      setResults([]);
      setActivityTaskMap({});
      setLoading(false);
      setSelectedIndex(0);
      return;
    }

    setLoading(true);
    const timer = setTimeout(async () => {
      const seq = ++seqRef.current;
      try {
        const rawResults = await VaultService.SearchAll(trimmed);
        if (seq !== seqRef.current) return;

        const items = (rawResults || []).filter((r): r is SearchResultItem => r !== null);
        setResults(items);
        setSelectedIndex(0);

        // Preload activity task_ids for up to 5 displayed records
        const displayedActivities = items.filter((r) => r.type === 'activity').slice(0, 5);
        if (displayedActivities.length > 0) {
          const taskMap: Record<string, string> = {};
          await Promise.all(
            displayedActivities.map(async (ar) => {
              try {
                const act = await VaultService.GetActivity(ar.id);
                if (act && act.task_id) {
                  taskMap[ar.id] = act.task_id;
                }
              } catch (err) {
                console.warn(`Failed to fetch activity details for ${ar.id}:`, err);
              }
            })
          );
          if (seq !== seqRef.current) return;
          setActivityTaskMap(taskMap);
        } else {
          setActivityTaskMap({});
        }
      } catch (err) {
        if (seq !== seqRef.current) return;
        console.error('SearchAll query error:', err);
        setResults([]);
      } finally {
        if (seq === seqRef.current) {
          setLoading(false);
        }
      }
    }, 250);

    return () => {
      clearTimeout(timer);
    };
  }, [query, isOpen]);

  // Group results by type (Task -> Note -> Activity -> File)
  const tasks = useMemo(() => results.filter((r) => r.type === 'task'), [results]);
  const notes = useMemo(() => results.filter((r) => r.type === 'note'), [results]);
  const activities = useMemo(() => results.filter((r) => r.type === 'activity'), [results]);
  const files = useMemo(() => results.filter((r) => (r.type as string) === 'file'), [results]);

  // Truncate displayed items to first 5 per type
  const displayedTasks = useMemo(() => tasks.slice(0, 5), [tasks]);
  const displayedNotes = useMemo(() => notes.slice(0, 5), [notes]);
  const displayedActivities = useMemo(() => activities.slice(0, 5), [activities]);
  const displayedFiles = useMemo(() => files.slice(0, 5), [files]);

  // Flattened displayed items for keyboard navigation index
  const displayedItems = useMemo(
    () => [...displayedTasks, ...displayedNotes, ...displayedActivities, ...displayedFiles],
    [displayedTasks, displayedNotes, displayedActivities, displayedFiles]
  );

  // Keep selected index within bounds
  useEffect(() => {
    if (displayedItems.length === 0) {
      setSelectedIndex(-1);
    } else {
      setSelectedIndex((prev) => Math.min(Math.max(0, prev), displayedItems.length - 1));
    }
  }, [displayedItems.length]);

  // Scroll active item into view
  useEffect(() => {
    if (selectedIndex >= 0 && itemRefs.current[selectedIndex]) {
      itemRefs.current[selectedIndex]?.scrollIntoView({
        block: 'nearest',
      });
    }
  }, [selectedIndex]);

  // Navigation action
  const handleItemSelect = useCallback(
    (item: SearchResultItem) => {
      if (item.type === 'task') {
        onOpenTask(item.id);
        onClose();
      } else if (item.type === 'note') {
        onOpenNote(item.id);
        onClose();
      } else if (item.type === 'activity') {
        const taskId = activityTaskMap[item.id];
        if (taskId) {
          onOpenTask(taskId);
          onClose();
        } else if (item.title && /^\d{4}-\d{2}-\d{2}$/.test(item.title)) {
          onOpenTodayDate?.(item.title);
          onClose();
        } else {
          onClose();
        }
      } else if ((item.type as string) === 'file') {
        VaultService.PreviewFile(item.id).catch((err) => {
          console.warn('Failed to preview file:', err);
        });
        onClose();
      }
    },
    [activityTaskMap, onOpenTask, onOpenNote, onOpenTodayDate, onClose]
  );

  // Keyboard navigation & a11y focus trap
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
      return;
    }

    if (e.key === 'Tab') {
      e.preventDefault();
      inputRef.current?.focus();
      return;
    }

    if (displayedItems.length === 0) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setSelectedIndex((prev) => (prev < displayedItems.length - 1 ? prev + 1 : 0));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setSelectedIndex((prev) => (prev > 0 ? prev - 1 : displayedItems.length - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (selectedIndex >= 0 && selectedIndex < displayedItems.length) {
        handleItemSelect(displayedItems[selectedIndex]);
      }
    }
  };

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-[10vh] px-4 bg-stone-900/40 dark:bg-black/60 backdrop-blur-xs select-none"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="全局快速搜索"
        className="w-full max-w-xl bg-stone-50 dark:bg-stone-900 border border-stone-200 dark:border-stone-800 rounded-xl shadow-2xl overflow-hidden flex flex-col max-h-[72vh] text-stone-900 dark:text-stone-100"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={handleKeyDown}
      >
        {/* Search Input Bar */}
        <div className="flex items-center px-4 py-3 border-b border-stone-200 dark:border-stone-800 gap-2.5">
          <Search className="w-4 h-4 text-stone-400 shrink-0" />
          <input
            ref={inputRef}
            type="text"
            role="combobox"
            aria-expanded={displayedItems.length > 0}
            aria-autocomplete="list"
            aria-controls="search-results-list"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索任务、笔记、记录 (⌘K / ⌘P)..."
            className="flex-1 bg-transparent text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 dark:placeholder-stone-500 outline-none border-none focus:outline-none focus:ring-0"
          />
          {loading && <Loader2 className="w-3.5 h-3.5 text-stone-400 animate-spin shrink-0" />}
          {query && !loading && (
            <button
              type="button"
              onMouseDown={(e) => {
                e.preventDefault();
                setQuery('');
                inputRef.current?.focus();
              }}
              onClick={() => {
                setQuery('');
                inputRef.current?.focus();
              }}
              className="p-1 rounded text-stone-400 hover:text-stone-600 dark:hover:text-stone-300"
              title="清空"
            >
              <X className="w-3 h-3" />
            </button>
          )}
          <kbd className="text-[10px] font-mono bg-stone-200/70 dark:bg-stone-800 text-stone-500 dark:text-stone-400 px-1.5 py-0.5 rounded shrink-0">
            ESC
          </kbd>
        </div>

        {/* Results Body */}
        <div className="flex-1 overflow-y-auto min-h-[140px] max-h-[52vh]">
          {!vaultOpen ? (
            <div className="py-12 text-center text-stone-400 dark:text-stone-500">
              <AlertCircle className="w-6 h-6 mx-auto mb-2 opacity-50 text-amber-500" />
              <p className="text-xs">Vault 尚未打开，请先选择工作区目录</p>
            </div>
          ) : !query.trim() ? (
            <div className="py-12 text-center text-stone-400 dark:text-stone-500">
              <Search className="w-6 h-6 mx-auto mb-2 opacity-40" />
              <p className="text-xs">输入关键词跨类型快速搜索</p>
              <p className="text-[11px] mt-1 text-stone-400/80">
                覆盖任务标题与描述、笔记内容、以及任务记录
              </p>
            </div>
          ) : loading && results.length === 0 ? (
            <div className="py-12 text-center text-stone-400 dark:text-stone-500">
              <Loader2 className="w-5 h-5 mx-auto mb-2 animate-spin text-stone-400" />
              <p className="text-xs">正在搜索...</p>
            </div>
          ) : results.length === 0 ? (
            <div className="py-12 text-center text-stone-400 dark:text-stone-500">
              <AlertCircle className="w-6 h-6 mx-auto mb-2 opacity-40" />
              <p className="text-xs">未找到与 “{query.trim()}” 相关的结果</p>
            </div>
          ) : (
            <div id="search-results-list" role="listbox" aria-label="搜索结果" className="divide-y divide-stone-100 dark:divide-stone-800/60">
              {/* 1. Tasks Section */}
              {displayedTasks.length > 0 && (
                <div>
                  <div className="flex items-center justify-between px-3.5 py-1.5 text-[11px] font-semibold text-stone-500 dark:text-stone-400 bg-stone-100/60 dark:bg-stone-800/40">
                    <div className="flex items-center space-x-1.5">
                      <CheckSquare className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400" />
                      <span>任务</span>
                    </div>
                    <span className="font-mono text-[10px] text-stone-400">
                      {tasks.length > 5 ? `显示前 5 条 / 共 ${tasks.length} 条` : `共 ${tasks.length} 条`}
                    </span>
                  </div>
                  <div className="p-1 space-y-0.5">
                    {displayedTasks.map((task, i) => {
                      const globalIndex = i;
                      const isSelected = selectedIndex === globalIndex;
                      return (
                        <div
                          key={`task-${task.id}`}
                          role="option"
                          aria-selected={isSelected}
                          tabIndex={-1}
                          ref={(el) => {
                            itemRefs.current[globalIndex] = el;
                          }}
                          onMouseEnter={() => setSelectedIndex(globalIndex)}
                          onClick={() => handleItemSelect(task)}
                          className={`w-full flex items-center justify-between px-3 py-2 rounded-lg text-xs cursor-pointer transition-colors ${
                            isSelected
                              ? 'bg-stone-200/80 dark:bg-stone-800 text-stone-900 dark:text-stone-50'
                              : 'text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/50'
                          }`}
                        >
                          <div className="flex items-center space-x-2.5 min-w-0 mr-2 flex-1">
                            <CheckSquare className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400 shrink-0 opacity-80" />
                            <div className="min-w-0 flex-1">
                              <div className="font-medium truncate">{task.title || '(无标题任务)'}</div>
                              {task.snippet && (
                                <div className="text-[11px] text-stone-500 dark:text-stone-400 truncate mt-0.5 opacity-90">
                                  {task.snippet}
                                </div>
                              )}
                            </div>
                          </div>
                          {isSelected && (
                            <span className="text-[10px] font-mono text-stone-400 dark:text-stone-500 shrink-0">
                              ↵ 打开
                            </span>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* 2. Notes Section */}
              {displayedNotes.length > 0 && (
                <div>
                  <div className="flex items-center justify-between px-3.5 py-1.5 text-[11px] font-semibold text-stone-500 dark:text-stone-400 bg-stone-100/60 dark:bg-stone-800/40">
                    <div className="flex items-center space-x-1.5">
                      <FileText className="w-3.5 h-3.5 text-blue-600 dark:text-blue-400" />
                      <span>笔记</span>
                    </div>
                    <span className="font-mono text-[10px] text-stone-400">
                      {notes.length > 5 ? `显示前 5 条 / 共 ${notes.length} 条` : `共 ${notes.length} 条`}
                    </span>
                  </div>
                  <div className="p-1 space-y-0.5">
                    {displayedNotes.map((note, j) => {
                      const globalIndex = displayedTasks.length + j;
                      const isSelected = selectedIndex === globalIndex;
                      return (
                        <div
                          key={`note-${note.id}`}
                          role="option"
                          aria-selected={isSelected}
                          tabIndex={-1}
                          ref={(el) => {
                            itemRefs.current[globalIndex] = el;
                          }}
                          onMouseEnter={() => setSelectedIndex(globalIndex)}
                          onClick={() => handleItemSelect(note)}
                          className={`w-full flex items-center justify-between px-3 py-2 rounded-lg text-xs cursor-pointer transition-colors ${
                            isSelected
                              ? 'bg-stone-200/80 dark:bg-stone-800 text-stone-900 dark:text-stone-50'
                              : 'text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/50'
                          }`}
                        >
                          <div className="flex items-center space-x-2.5 min-w-0 mr-2 flex-1">
                            <FileText className="w-3.5 h-3.5 text-blue-600 dark:text-blue-400 shrink-0 opacity-80" />
                            <div className="min-w-0 flex-1">
                              <div className="font-medium truncate">{note.title || '(无标题笔记)'}</div>
                              {note.snippet && (
                                <div className="text-[11px] text-stone-500 dark:text-stone-400 truncate mt-0.5 opacity-90">
                                  {note.snippet}
                                </div>
                              )}
                            </div>
                          </div>
                          {isSelected && (
                            <span className="text-[10px] font-mono text-stone-400 dark:text-stone-500 shrink-0">
                              ↵ 打开
                            </span>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* 3. Activities Section */}
              {displayedActivities.length > 0 && (
                <div>
                  <div className="flex items-center justify-between px-3.5 py-1.5 text-[11px] font-semibold text-stone-500 dark:text-stone-400 bg-stone-100/60 dark:bg-stone-800/40">
                    <div className="flex items-center space-x-1.5">
                      <MessageSquare className="w-3.5 h-3.5 text-amber-600 dark:text-amber-400" />
                      <span>记录</span>
                    </div>
                    <span className="font-mono text-[10px] text-stone-400">
                      {activities.length > 5 ? `显示前 5 条 / 共 ${activities.length} 条` : `共 ${activities.length} 条`}
                    </span>
                  </div>
                  <div className="p-1 space-y-0.5">
                    {displayedActivities.map((act, k) => {
                      const globalIndex = displayedTasks.length + displayedNotes.length + k;
                      const isSelected = selectedIndex === globalIndex;
                      const taskId = activityTaskMap[act.id];
                      const hasTaskId = Boolean(taskId);
                      const hasDate = Boolean(act.title && /^\d{4}-\d{2}-\d{2}$/.test(act.title));
                      const isClickable = hasTaskId || hasDate;

                      return (
                        <div
                          key={`activity-${act.id}`}
                          role="option"
                          aria-selected={isSelected}
                          tabIndex={-1}
                          ref={(el) => {
                            itemRefs.current[globalIndex] = el;
                          }}
                          onMouseEnter={() => setSelectedIndex(globalIndex)}
                          onClick={() => {
                            if (isClickable) {
                              handleItemSelect(act);
                            }
                          }}
                          className={`w-full flex items-center justify-between px-3 py-2 rounded-lg text-xs transition-colors ${
                            isClickable ? 'cursor-pointer' : 'cursor-default opacity-85'
                          } ${
                            isSelected
                              ? 'bg-stone-200/80 dark:bg-stone-800 text-stone-900 dark:text-stone-50'
                              : 'text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/50'
                          }`}
                        >
                          <div className="flex items-center space-x-2.5 min-w-0 mr-2 flex-1">
                            <MessageSquare className="w-3.5 h-3.5 text-amber-600 dark:text-amber-400 shrink-0 opacity-80" />
                            <div className="min-w-0 flex-1">
                              <div className="truncate text-stone-800 dark:text-stone-200">
                                {act.snippet || '(无内容记录)'}
                              </div>
                              <div className="flex items-center space-x-1.5 mt-0.5">
                                {hasTaskId ? (
                                  <span className="text-[10px] text-emerald-600 dark:text-emerald-400 font-mono">
                                    关联任务评论
                                  </span>
                                ) : hasDate ? (
                                  <span className="text-[10px] text-blue-600 dark:text-blue-400 font-mono">
                                    日计划活动 ({act.title})
                                  </span>
                                ) : (
                                  <span className="text-[10px] text-stone-400 font-mono">
                                    独立记录 (仅展示)
                                  </span>
                                )}
                              </div>
                            </div>
                          </div>
                          {isSelected && hasTaskId && (
                            <span className="text-[10px] font-mono text-stone-400 dark:text-stone-500 shrink-0 flex items-center space-x-1">
                              <span>↵ 跳父任务</span>
                              <ExternalLink className="w-2.5 h-2.5" />
                            </span>
                          )}
                          {isSelected && !hasTaskId && hasDate && (
                            <span className="text-[10px] font-mono text-stone-400 dark:text-stone-500 shrink-0 flex items-center space-x-1">
                              <span>↵ 打开日计划</span>
                              <ExternalLink className="w-2.5 h-2.5" />
                            </span>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* 4. Files Section */}
              {displayedFiles.length > 0 && (
                <div>
                  <div className="flex items-center justify-between px-3.5 py-1.5 text-[11px] font-semibold text-stone-500 dark:text-stone-400 bg-stone-100/60 dark:bg-stone-800/40">
                    <div className="flex items-center space-x-1.5">
                      <Paperclip className="w-3.5 h-3.5 text-blue-600 dark:text-blue-400" />
                      <span>文件资源</span>
                    </div>
                    <span className="font-mono text-[10px] text-stone-400">
                      {files.length > 5 ? `显示前 5 条 / 共 ${files.length} 条` : `共 ${files.length} 条`}
                    </span>
                  </div>
                  <div className="p-1 space-y-0.5">
                    {displayedFiles.map((file, m) => {
                      const globalIndex = displayedTasks.length + displayedNotes.length + displayedActivities.length + m;
                      const isSelected = selectedIndex === globalIndex;

                      return (
                        <div
                          key={`file-${file.id}`}
                          role="option"
                          aria-selected={isSelected}
                          tabIndex={-1}
                          ref={(el) => {
                            itemRefs.current[globalIndex] = el;
                          }}
                          onMouseEnter={() => setSelectedIndex(globalIndex)}
                          onClick={() => handleItemSelect(file)}
                          className={`w-full flex items-center justify-between px-3 py-2 rounded-lg text-xs cursor-pointer transition-colors ${
                            isSelected
                              ? 'bg-stone-200/80 dark:bg-stone-800 text-stone-900 dark:text-stone-50'
                              : 'text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/50'
                          }`}
                        >
                          <div className="flex items-center space-x-2.5 min-w-0 mr-2 flex-1">
                            <Paperclip className="w-3.5 h-3.5 text-blue-600 dark:text-blue-400 shrink-0 opacity-80" />
                            <div className="min-w-0 flex-1">
                              <div className="font-medium truncate">{file.title}</div>
                              <div className="text-[11px] text-stone-500 dark:text-stone-400 truncate mt-0.5 opacity-90">
                                {file.snippet || file.id}
                              </div>
                            </div>
                          </div>
                          <div className="flex items-center space-x-2 shrink-0">
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                VaultService.RevealInFinder(file.id).catch(() => {});
                              }}
                              title="在 Finder 中显示"
                              className="p-1 text-stone-400 hover:text-stone-600 dark:hover:text-stone-200 rounded cursor-pointer"
                            >
                              <ExternalLink className="w-3 h-3" />
                            </button>
                            {isSelected && (
                              <span className="text-[10px] font-mono text-stone-400 dark:text-stone-500">
                                ↵ 预览
                              </span>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="px-4 py-2 bg-stone-100/70 dark:bg-stone-950/70 border-t border-stone-200/60 dark:border-stone-800/60 flex items-center justify-between text-[11px] text-stone-400 select-none">
          <div className="flex items-center space-x-3">
            <span>
              <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[10px]">
                ↑
              </kbd>{' '}
              <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[10px]">
                ↓
              </kbd>{' '}
              选择
            </span>
            <span>
              <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[10px]">
                ↵
              </kbd>{' '}
              打开
            </span>
            <span>
              <kbd className="font-mono bg-stone-200/60 dark:bg-stone-800 px-1 py-0.5 rounded text-[10px]">
                ESC
              </kbd>{' '}
              关闭
            </span>
          </div>
          <span className="font-mono text-[10px]">⌘K / ⌘P</span>
        </div>
      </div>
    </div>
  );
}
