import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Events } from '@wailsio/runtime';
import {
  Hash,
  CheckSquare,
  FileText,
  MessageSquare,
  ChevronRight,
  AlertCircle,
  Loader2,
  ExternalLink,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { EntityRef } from '../bindings/pata/internal/storage/markdown/models';
import { DetailSplit, useDetailOrigin } from './DetailSplit';
import { TaskDetailPanel, TaskDetailHandle } from './TaskDetailPanel';
import {
  isVirtualAllTag,
  formatTagViewHeader,
  formatTagLoadingText,
  formatTagErrorSubject,
  formatTagEmptyMessage,
} from './tagAll';

interface TagViewProps {
  selectedTag: string | null;
  onOpenNote: (noteId: string, fromTaskId?: string) => void;
  initialTaskId?: string | null;
  onInitialTaskConsumed?: () => void;
  tagNames: string[];
  onVaultDataChanged: () => void;
  leaveGuardRef: React.MutableRefObject<(() => Promise<boolean>) | null>;
}

function formatItemTime(isoString?: string): string {
  if (!isoString) return '';
  try {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return '';
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const isToday =
      d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() &&
      d.getDate() === now.getDate();
    const timeStr = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    if (isToday) {
      return `今天 ${timeStr}`;
    }
    const isThisYear = d.getFullYear() === now.getFullYear();
    const dateStr = isThisYear
      ? `${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
      : `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    return `${dateStr} ${timeStr}`;
  } catch {
    return '';
  }
}

export function TagView({
  selectedTag,
  onOpenNote,
  initialTaskId,
  onInitialTaskConsumed,
  tagNames,
  onVaultDataChanged,
  leaveGuardRef,
}: TagViewProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<EntityRef[]>([]);
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);

  const panelRef = useRef<TaskDetailHandle>(null);
  const origin = useDetailOrigin();
  const seqRef = useRef(0);

  // Consume initialTaskId if passed (e.g. when returning from a note)
  useEffect(() => {
    if (initialTaskId) {
      setSelectedTaskId(initialTaskId);
      onInitialTaskConsumed?.();
    }
  }, [initialTaskId, onInitialTaskConsumed]);

  const loadTagData = useCallback(async (tag: string | null) => {
    const seq = ++seqRef.current;
    const all = isVirtualAllTag(tag);

    setLoading(true);
    setError(null);
    try {
      const rawRefs = all
        ? await VaultService.ListAllEntities()
        : await VaultService.ListByTag(tag!.trim());
      if (seq !== seqRef.current) return;

      const refs = (rawRefs || []).filter((r): r is EntityRef => r !== null);
      setItems(refs);
    } catch (err: any) {
      if (seq !== seqRef.current) return;
      console.error('Failed to load entities:', err);
      setError(`加载${formatTagErrorSubject(tag)}内容失败: ${err?.message || err}`);
    } finally {
      if (seq === seqRef.current) {
        setLoading(false);
      }
    }
  }, []);

  // Reload when selectedTag changes
  useEffect(() => {
    loadTagData(selectedTag);
  }, [selectedTag, loadTagData]);

  // Subscribe to vault:changed events
  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', () => {
      loadTagData(selectedTag);
    });

    return () => {
      unsubscribe();
    };
  }, [selectedTag, loadTagData]);

  // Panel management
  const closePanel = useCallback(async () => {
    if (panelRef.current && !(await panelRef.current.confirmLeave())) return;
    setSelectedTaskId(null);
    origin.restore();
  }, [origin]);

  const openTask = useCallback(
    async (id: string) => {
      if (id === selectedTaskId) return;
      if (panelRef.current && !(await panelRef.current.confirmLeave())) return;
      origin.capture();
      setSelectedTaskId(id);
    },
    [selectedTaskId, origin]
  );

  const refreshAll = useCallback(() => {
    void loadTagData(selectedTag);
    onVaultDataChanged();
  }, [loadTagData, selectedTag, onVaultDataChanged]);

  // Protect unsaved draft in panel before leaving
  useEffect(() => {
    leaveGuardRef.current = async () => {
      if (!selectedTaskId) return true;
      if (!panelRef.current) return true;
      return panelRef.current.confirmLeave();
    };
    return () => {
      leaveGuardRef.current = null;
    };
  }, [selectedTaskId, leaveGuardRef]);

  // Category counts
  const taskCount = useMemo(() => items.filter((it) => it.type === 'task').length, [items]);
  const noteCount = useMemo(() => items.filter((it) => it.type === 'note').length, [items]);
  const activityCount = useMemo(() => items.filter((it) => it.type === 'activity').length, [items]);

  const panel = selectedTaskId ? (
    <TaskDetailPanel
      key={selectedTaskId}
      ref={panelRef}
      taskId={selectedTaskId}
      closeLabel="关闭详情"
      tagNames={tagNames}
      onClose={closePanel}
      onChanged={refreshAll}
      onDeleted={closePanel}
      onOpenNote={(noteId) => onOpenNote(noteId, selectedTaskId)}
    />
  ) : null;

  if (loading && items.length === 0) {
    return (
      <div className="max-w-[900px] mx-auto py-16 flex items-center justify-center text-stone-400 text-xs">
        <Loader2 className="w-5 h-5 animate-spin mr-2 text-emerald-600" />
        <span>{formatTagLoadingText(selectedTag)}</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="max-w-[900px] mx-auto p-4 rounded-lg bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-900 text-rose-700 dark:text-rose-300 text-xs flex items-center space-x-2">
        <AlertCircle className="w-4 h-4 shrink-0" />
        <span>{error}</span>
      </div>
    );
  }

  return (
    <DetailSplit panel={panel}>
      <div className="space-y-4">
        {/* Header with Tag Chip & Counts */}
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 border-b border-stone-200/80 dark:border-stone-800 pb-3">
          <div className="flex items-center space-x-2">
            <div className="flex items-center space-x-1.5 px-2.5 py-1 rounded-md bg-emerald-50 dark:bg-emerald-950/50 border border-emerald-200/60 dark:border-emerald-800/60 text-emerald-800 dark:text-emerald-300 font-medium text-sm">
              <Hash className="w-4 h-4" />
              <span>{formatTagViewHeader(selectedTag)}</span>
            </div>
            <span className="text-xs text-stone-400">
              共 {items.length} 项（任务 {taskCount} · 笔记 {noteCount} · 记录 {activityCount}）
            </span>
          </div>
        </div>

        {/* Chronological Timeline Feed */}
        {items.length === 0 ? (
          <div className="py-16 flex flex-col items-center justify-center text-stone-400 text-xs bg-white dark:bg-stone-900/60 rounded-xl border border-stone-200/80 dark:border-stone-800">
            <Hash className="w-8 h-8 mb-2 opacity-30 text-stone-400" />
            <p>{formatTagEmptyMessage(selectedTag)}</p>
          </div>
        ) : (
          <div className="space-y-2.5">
            {items.map((item) => {
              if (item.type === 'task') {
                const isSelected = selectedTaskId === item.id;
                return (
                  <div
                    key={`task-${item.id}`}
                    role="button"
                    tabIndex={0}
                    onClick={() => void openTask(item.id)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        void openTask(item.id);
                      }
                    }}
                    className={`w-full p-3.5 rounded-xl border transition text-left cursor-pointer group bg-white dark:bg-stone-900/90 ${
                      isSelected
                        ? 'border-emerald-500 ring-1 ring-emerald-500/30'
                        : 'border-stone-200/80 dark:border-stone-800 hover:border-emerald-500/50 hover:bg-stone-50/80 dark:hover:bg-stone-800/50'
                    }`}
                    title={`在右栏查看任务: ${item.title || item.id}`}
                  >
                    <div className="flex items-center justify-between text-xs mb-1.5">
                      <div className="flex items-center space-x-1.5">
                        <span className="inline-flex items-center space-x-1 text-[10px] px-1.5 py-0.5 rounded bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-400 border border-emerald-200/60 dark:border-emerald-800/60 font-medium">
                          <CheckSquare className="w-3 h-3" />
                          <span>任务</span>
                        </span>
                        {item.status === 'done' && (
                          <span className="text-[10px] px-1.5 py-0.5 rounded bg-stone-100 dark:bg-stone-800 text-stone-500 font-medium">
                            已完成
                          </span>
                        )}
                      </div>
                      <span className="text-[11px] text-stone-400 font-mono">
                        {formatItemTime(item.time)}
                      </span>
                    </div>

                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="text-xs font-medium text-stone-800 dark:text-stone-200 group-hover:text-emerald-700 dark:group-hover:text-emerald-400 truncate">
                          {item.title || item.id}
                        </div>
                        {item.snippet && (
                          <p className="text-[11px] text-stone-500 dark:text-stone-400 line-clamp-2 mt-1">
                            {item.snippet}
                          </p>
                        )}
                      </div>
                      <span className="text-[10px] text-stone-400 flex items-center space-x-0.5 shrink-0 group-hover:text-emerald-600 transition">
                        <span>查看任务</span>
                        <ChevronRight className="w-3.5 h-3.5" />
                      </span>
                    </div>
                  </div>
                );
              }

              if (item.type === 'note') {
                return (
                  <div
                    key={`note-${item.id}`}
                    role="button"
                    tabIndex={0}
                    onClick={() => onOpenNote(item.id)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        onOpenNote(item.id);
                      }
                    }}
                    className="w-full p-3.5 rounded-xl border border-stone-200/80 dark:border-stone-800 bg-white dark:bg-stone-900/90 hover:border-blue-500/50 hover:bg-stone-50/80 dark:hover:bg-stone-800/50 transition text-left cursor-pointer group"
                    title={`打开笔记: ${item.title || item.id}`}
                  >
                    <div className="flex items-center justify-between text-xs mb-1.5">
                      <div className="flex items-center space-x-1.5">
                        <span className="inline-flex items-center space-x-1 text-[10px] px-1.5 py-0.5 rounded bg-blue-50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-400 border border-blue-200/60 dark:border-blue-800/60 font-medium">
                          <FileText className="w-3 h-3" />
                          <span>笔记</span>
                        </span>
                      </div>
                      <span className="text-[11px] text-stone-400 font-mono">
                        {formatItemTime(item.time)}
                      </span>
                    </div>

                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="text-xs font-medium text-stone-800 dark:text-stone-200 group-hover:text-blue-700 dark:group-hover:text-blue-400 truncate">
                          {item.title || item.id}
                        </div>
                        {item.snippet && (
                          <p className="text-[11px] text-stone-500 dark:text-stone-400 line-clamp-2 mt-1">
                            {item.snippet}
                          </p>
                        )}
                      </div>
                      <span className="text-[10px] text-stone-400 flex items-center space-x-0.5 shrink-0 group-hover:text-blue-600 transition">
                        <span>打开笔记</span>
                        <ChevronRight className="w-3.5 h-3.5" />
                      </span>
                    </div>
                  </div>
                );
              }

              // Activity
              const isTaskSelected = !!item.task_id && selectedTaskId === item.task_id;
              return (
                <div
                  key={`activity-${item.id}`}
                  className={`w-full p-3.5 rounded-xl border transition text-left bg-white dark:bg-stone-900/90 space-y-2 ${
                    isTaskSelected
                      ? 'border-emerald-500/70 ring-1 ring-emerald-500/20'
                      : 'border-stone-200/80 dark:border-stone-800'
                  }`}
                >
                  <div className="flex items-center justify-between text-xs">
                    <div className="flex items-center space-x-2 truncate mr-2">
                      <span className="inline-flex items-center space-x-1 text-[10px] px-1.5 py-0.5 rounded bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-400 border border-amber-200/60 dark:border-amber-800/60 font-medium shrink-0">
                        <MessageSquare className="w-3 h-3" />
                        <span>记录</span>
                      </span>
                      {item.inherited && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded bg-amber-100/70 dark:bg-amber-950/60 text-amber-800 dark:text-amber-300 border border-amber-200 dark:border-amber-900 font-medium shrink-0">
                          经父任务
                        </span>
                      )}
                      {item.task_id ? (
                        <span className="text-[11px] text-stone-500 dark:text-stone-400 truncate">
                          所属任务: {item.title}
                        </span>
                      ) : (
                        <span className="text-[11px] text-stone-500 dark:text-stone-400 truncate">
                          今日计划: {item.title}
                        </span>
                      )}
                    </div>
                    <span className="text-[11px] text-stone-400 font-mono shrink-0">
                      {formatItemTime(item.time)}
                    </span>
                  </div>

                  <p className="text-xs text-stone-700 dark:text-stone-300 leading-relaxed whitespace-pre-wrap line-clamp-3">
                    {item.snippet?.trim() || '（无正文内容）'}
                  </p>

                  {item.task_id && (
                    <div className="pt-1.5 border-t border-stone-100 dark:border-stone-800/60 flex justify-end">
                      <button
                        onClick={() => void openTask(item.task_id!)}
                        className="text-[11px] text-stone-500 hover:text-emerald-700 dark:hover:text-emerald-400 flex items-center space-x-1 transition min-h-[28px] px-1 cursor-pointer"
                        title="在右栏查看任务详情"
                      >
                        <span>查看任务</span>
                        <ExternalLink className="w-3 h-3" />
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </DetailSplit>
  );
}
