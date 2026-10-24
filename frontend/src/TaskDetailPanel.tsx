import React, { useState, useEffect, useMemo, useCallback, useRef, useImperativeHandle, forwardRef } from 'react';
import { Events } from '@wailsio/runtime';
import {
  ArrowRight,
  MoreHorizontal,
  Check,
  Calendar,
  CalendarMinus,
  X,
  Trash2,
  AlertCircle,
  RefreshCw,
  Info,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { Task, TaskStatus, Activity } from '../bindings/pata/internal/storage/markdown/models';
import { UpdateTaskInput, CreateActivityInput } from '../bindings/pata/models';
import { playLogoSuccess } from './logoAnimation';
import { dedupeTags, validateTag, hasTag } from './tagUtils';
import { TagChipEditor } from './TagChipEditor';
import { NoteRefText, NoteRefTextarea, NoteRefMap, pruneRefs, sameRefs, useNoteRefs } from './noteRefs';
import { ActivityComposer } from './ActivityComposer';
import { ActivityItem } from './ActivityItem';
import {
  buildTaskTimelineItems,
  formatActivityTimestamp,
  formatFullLocalTimestamp,
} from './taskTimeline';

function getPresetDates() {
  const now = new Date();
  const pad = (n: number) => n.toString().padStart(2, '0');
  const format = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

  const todayStr = format(now);

  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowStr = format(tomorrow);

  const nextMonday = new Date(now);
  const day = nextMonday.getDay();
  const daysUntilNextMonday = ((8 - day) % 7) || 7;
  nextMonday.setDate(nextMonday.getDate() + daysUntilNextMonday);
  const nextMondayStr = format(nextMonday);

  return { todayStr, tomorrowStr, nextMondayStr };
}

function formatDueDisplay(dueStr: string): { text: string; isOverdue: boolean; isToday: boolean } {
  if (!dueStr) return { text: '添加截止日期', isOverdue: false, isToday: false };
  const { todayStr, tomorrowStr } = getPresetDates();

  if (dueStr === todayStr) {
    return { text: '今天截止', isOverdue: false, isToday: true };
  }
  if (dueStr === tomorrowStr) {
    return { text: '明天截止', isOverdue: false, isToday: false };
  }
  if (dueStr < todayStr) {
    return { text: `${dueStr} (已逾期)`, isOverdue: true, isToday: false };
  }
  try {
    const [y, m, d] = dueStr.split('-').map(Number);
    const nowYear = new Date().getFullYear();
    if (y === nowYear) {
      return { text: `${m}月${d}日截止`, isOverdue: false, isToday: false };
    }
    return { text: `${dueStr} 截止`, isOverdue: false, isToday: false };
  } catch {
    return { text: `${dueStr} 截止`, isOverdue: false, isToday: false };
  }
}

const adjustTextareaHeight = (el: HTMLTextAreaElement | null, minHeight = 22) => {
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.max(el.scrollHeight, minHeight)}px`;
};

export interface TaskDetailHandle {
  /** 有未保存草稿时返回确认；成功自动保存或返回 true 表示可以继续离开。 */
  confirmLeave: () => Promise<boolean>;
  /** 丢弃表单并从磁盘重读（行内修改后同步）。 */
  reload: () => Promise<void>;
}

export interface PlanDateContext {
  date: string;
  isToday: boolean;
  onRemoveFromPlan: (taskId: string, date: string) => Promise<boolean>;
}

interface TaskDetailPanelProps {
  taskId: string;
  closeLabel: string;
  tagNames?: string[];
  onClose: () => void;
  /** 任何成功写入后调用，用于刷新父级列表、全局标签与搜索。 */
  onChanged: () => void;
  onDeleted: () => void;
  onOpenNote?: (noteId: string, fromTaskId?: string) => void;
  planDateContext?: PlanDateContext;
}

const isConflictErr = (err: any) =>
  typeof err?.message === 'string' &&
  (err.message.includes('write conflict') || err.message.includes('conflict at'));

export const TaskDetailPanel = forwardRef<TaskDetailHandle, TaskDetailPanelProps>(function TaskDetailPanel(
  { taskId, closeLabel, tagNames = [], onClose, onChanged, onDeleted, onOpenNote, planDateContext },
  ref
) {
  const [task, setTask] = useState<Task | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [removingFromPlan, setRemovingFromPlan] = useState(false);

  const [detailTitle, setDetailTitle] = useState('');
  const [detailStatus, setDetailStatus] = useState<TaskStatus>(TaskStatus.TaskStatusTodo);
  const [detailDue, setDetailDue] = useState<string>('');
  const [detailTags, setDetailTags] = useState<string[]>([]);
  const [detailBody, setDetailBody] = useState<string>('');
  const [detailRefs, setDetailRefs] = useState<NoteRefMap>({});
  const [isEditingBody, setIsEditingBody] = useState(false);

  const [saving, setSaving] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [externalModified, setExternalModified] = useState(false);
  const [conflictError, setConflictError] = useState<string | null>(null);

  // Popover / Menu dropdown states
  const [menuOpen, setMenuOpen] = useState(false);
  const [dueOpen, setDueOpen] = useState(false);

  // Modals
  const [showTaskInfo, setShowTaskInfo] = useState(false);
  const [deleteModalOpen, setDeleteModalOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [leavePrompt, setLeavePrompt] = useState<((r: boolean) => void) | null>(null);

  // Activities
  const [taskActivities, setTaskActivities] = useState<Activity[]>([]);
  const [activityListError, setActivityListError] = useState<string | null>(null);
  const [newActivityBody, setNewActivityBody] = useState('');
  const [newActivityRefs, setNewActivityRefs] = useState<NoteRefMap>({});
  const [submittingActivity, setSubmittingActivity] = useState(false);
  const [submitActivityError, setSubmitActivityError] = useState<string | null>(null);

  // Activity Inline Editing
  const [editingActivityId, setEditingActivityId] = useState<string | null>(null);
  const [editBody, setEditBody] = useState('');
  const [editRefs, setEditRefs] = useState<NoteRefMap>({});
  const [editSaving, setEditSaving] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);

  const editingActivity = useMemo(
    () => taskActivities.find((a) => a.id === editingActivityId),
    [taskActivities, editingActivityId]
  );
  const editDirty = Boolean(
    editingActivityId &&
      (!editingActivity ||
        editBody !== editingActivity.body ||
        !sameRefs(pruneRefs(editBody, editRefs), pruneRefs(editingActivity.body, editingActivity.note_refs ?? {})))
  );

  const noteRefs = useNoteRefs();

  const titleTextareaRef = useRef<HTMLTextAreaElement>(null);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const externalModifiedRef = useRef(false);
  const externalChangeVersionRef = useRef(0);
  const hasDraftRef = useRef(false);

  // Popover refs for outside click detection
  const menuRef = useRef<HTMLDivElement>(null);
  const dueRef = useRef<HTMLDivElement>(null);

  // Latest state references for safe auto-saving
  const latestTaskRef = useRef<Task | null>(null);
  const latestTitleRef = useRef('');
  const latestStatusRef = useRef<TaskStatus>(TaskStatus.TaskStatusTodo);
  const latestDueRef = useRef<string>('');
  const latestTagsRef = useRef<string[]>([]);
  const latestBodyRef = useRef<string>('');
  const latestRefsRef = useRef<NoteRefMap>({});

  useEffect(() => {
    latestTaskRef.current = task;
  }, [task]);
  useEffect(() => {
    latestTitleRef.current = detailTitle;
  }, [detailTitle]);
  useEffect(() => {
    latestStatusRef.current = detailStatus;
  }, [detailStatus]);
  useEffect(() => {
    latestDueRef.current = detailDue;
  }, [detailDue]);
  useEffect(() => {
    latestTagsRef.current = detailTags;
  }, [detailTags]);
  useEffect(() => {
    latestBodyRef.current = detailBody;
  }, [detailBody]);
  useEffect(() => {
    latestRefsRef.current = detailRefs;
  }, [detailRefs]);

  // Adjust title height on load or change
  useEffect(() => {
    adjustTextareaHeight(titleTextareaRef.current, 28);
  }, [detailTitle]);

  const applyTask = useCallback((t: Task) => {
    latestTaskRef.current = t;
    latestTitleRef.current = t.title;
    latestStatusRef.current = t.status;
    latestDueRef.current = t.due ?? '';
    latestTagsRef.current = t.tags ?? [];
    latestBodyRef.current = t.description ?? t.body ?? '';
    setTask(t);
    setDetailTitle(t.title);
    setDetailStatus(t.status);
    setDetailDue(t.due ?? '');
    setDetailTags(t.tags ?? []);
    setDetailBody(t.description ?? t.body ?? '');
    setDetailRefs(t.note_refs ?? {});
    latestRefsRef.current = t.note_refs ?? {};
  }, []);

  const loadActivities = useCallback(async () => {
    setActivityListError(null);
    try {
      const result = await VaultService.ListActivitiesByTask(taskId);
      setTaskActivities((result ?? []).filter((m): m is Activity => m !== null));
    } catch (err: any) {
      console.error('Failed to list activities for task:', err);
      setActivityListError(err?.message || String(err));
    }
  }, [taskId]);

  const reload = useCallback(async (preserveDraft = false) => {
    const version = externalChangeVersionRef.current;
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = null;
    }
    try {
      const t = await VaultService.GetTask(taskId);
      if (!t) throw new Error('任务不存在');
      if (version !== externalChangeVersionRef.current || (preserveDraft && hasDraftRef.current)) return;
      applyTask(t);
      externalModifiedRef.current = false;
      setDetailError(null);
      setConflictError(null);
      setExternalModified(false);
      setLoadError(null);
      await loadActivities();
    } catch (err: any) {
      setDetailError(`重新加载失败: ${err?.message || err}`);
      setLoadError((prev) => prev ?? (err?.message || String(err)));
    }
  }, [taskId, applyTask, loadActivities]);

  useEffect(() => {
    void reload();
  }, [reload]);

  // Outside click listener to dismiss open popovers
  useEffect(() => {
    const handleOutsideClick = (e: MouseEvent) => {
      const target = e.target as Node;
      if (menuRef.current && !menuRef.current.contains(target)) {
        setMenuOpen(false);
      }
      if (dueRef.current && !dueRef.current.contains(target)) {
        setDueOpen(false);
      }
    };
    window.addEventListener('mousedown', handleOutsideClick);
    return () => window.removeEventListener('mousedown', handleOutsideClick);
  }, []);

  // Escape key listener to dismiss open popovers
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setMenuOpen(false);
        setDueOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // External vault file change listener
  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', (ev) => {
      const data = ev.data as { entity_id?: string } | undefined;
      if (data?.entity_id === taskId) {
        externalChangeVersionRef.current += 1;
        externalModifiedRef.current = true;
        setExternalModified(true);
        if (debounceTimerRef.current) {
          clearTimeout(debounceTimerRef.current);
          debounceTimerRef.current = null;
        }
        if (!hasDraftRef.current) void reload(true);
      }
      void loadActivities();
    });
    return () => {
      unsubscribe();
    };
  }, [taskId, loadActivities, reload]);

  // Clear debounce timer on unmount
  useEffect(() => {
    return () => {
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    };
  }, []);

  const saveTask = useCallback(
    async (patch?: {
      title?: string;
      status?: TaskStatus;
      due?: string | null;
      tags?: string[];
      body?: string;
      refs?: NoteRefMap;
    }): Promise<boolean> => {
      const currentTask = latestTaskRef.current;
      if (!currentTask || externalModifiedRef.current) return false;

      const titleToSave = (patch?.title !== undefined ? patch.title : latestTitleRef.current).trim();
      if (!titleToSave) {
        return false;
      }
      const statusToSave = patch?.status !== undefined ? patch.status : latestStatusRef.current;
      const dueToSave = patch?.due !== undefined ? (patch.due || null) : (latestDueRef.current || null);
      const tagsToSave = patch?.tags !== undefined ? patch.tags : latestTagsRef.current;
      const bodyToSave = patch?.body !== undefined ? patch.body : latestBodyRef.current;
      const refsToSave = patch?.refs !== undefined ? patch.refs : latestRefsRef.current;

      hasDraftRef.current = true;
      setSaving(true);
      setDetailError(null);
      setConflictError(null);

      try {
        const input: UpdateTaskInput = {
          id: taskId,
          title: titleToSave,
          description: bodyToSave,
          status: statusToSave,
          due: dueToSave,
          tags: dedupeTags(tagsToSave),
          body: bodyToSave,
          note_ids: currentTask.note_ids ?? [],
          note_refs: pruneRefs(bodyToSave, refsToSave),
        };

        const updated = await VaultService.UpdateTask(input);
        if (externalModifiedRef.current) return false;
        if (updated) {
          applyTask(updated);
          setExternalModified(false);
        }
        onChanged();
        return true;
      } catch (err: any) {
        if (isConflictErr(err)) {
          externalModifiedRef.current = true;
          setConflictError(err?.message || '文件已被外部修改（写入冲突）');
          setExternalModified(true);
        } else {
          setDetailError(err?.message || String(err));
        }
        return false;
      } finally {
        setSaving(false);
      }
    },
    [taskId, applyTask, onChanged]
  );

  const formDirty = useMemo(() => {
    if (!task) return false;
    const currentTitle = detailTitle.trim();
    if (currentTitle !== task.title) return true;
    if (detailStatus !== task.status) return true;
    if ((detailDue || '') !== (task.due ?? '')) return true;
    const curTags = dedupeTags(detailTags).sort().join(',');
    const taskTags = dedupeTags(task.tags ?? []).sort().join(',');
    if (curTags !== taskTags) return true;
    const taskDesc = task.description ?? task.body ?? '';
    if (detailBody !== taskDesc) return true;
    if (!sameRefs(pruneRefs(detailBody, detailRefs), pruneRefs(taskDesc, task.note_refs ?? {}))) return true;
    return false;
  }, [task, detailTitle, detailStatus, detailDue, detailTags, detailBody, detailRefs]);
  hasDraftRef.current = formDirty || editDirty || Boolean(newActivityBody.trim()) || saving;

  const handleAddActivity = async (e?: React.FormEvent): Promise<boolean> => {
    if (e) e.preventDefault();
    const body = newActivityBody.trim();
    if (!body) return true;
    setSubmittingActivity(true);
    setSubmitActivityError(null);
    try {
      const input: CreateActivityInput = { body, task_id: taskId, note_refs: pruneRefs(body, newActivityRefs) };
      await VaultService.CreateActivity(input);
      playLogoSuccess();
      setNewActivityBody('');
      setNewActivityRefs({});
      await loadActivities();
      onChanged();
      return true;
    } catch (err: any) {
      console.error('Failed to create activity:', err);
      setSubmitActivityError(err?.message || String(err));
      return false;
    } finally {
      setSubmittingActivity(false);
    }
  };

  const handleSaveActivityEdit = async (id: string, tags: string[]): Promise<boolean> => {
    setEditSaving(true);
    setEditError(null);
    try {
      await VaultService.UpdateActivity({
        id,
        body: editBody,
        tags,
        note_refs: pruneRefs(editBody, editRefs),
      });
      setEditingActivityId(null);
      await loadActivities();
      onChanged();
      return true;
    } catch (err: any) {
      console.error('Failed to update activity:', err);
      setEditError(err?.message || String(err));
      return false;
    } finally {
      setEditSaving(false);
    }
  };

  const confirmLeave = useCallback(async (): Promise<boolean> => {
    if (formDirty) {
      const ok = await saveTask();
      if (!ok) return false;
    }
    if (newActivityBody.trim() !== '' || editDirty) {
      return new Promise<boolean>((resolve) => setLeavePrompt(() => resolve));
    }
    return true;
  }, [formDirty, saveTask, newActivityBody, editDirty]);

  useImperativeHandle(ref, () => ({ confirmLeave, reload }), [confirmLeave, reload]);

  const finishLeavePrompt = async (choice: 'save' | 'discard' | 'cancel') => {
    const resolve = leavePrompt;
    if (!resolve) return;
    if (choice === 'save') {
      if (editDirty && editingActivityId) {
        const editOk = await handleSaveActivityEdit(editingActivityId, editingActivity?.tags ?? []);
        if (!editOk) {
          // 保存已有评论失败：短路，不继续发送新 Activity，避免部分提交
          setLeavePrompt(null);
          resolve(false);
          return;
        }
      }
      if (newActivityBody.trim()) {
        const addOk = await handleAddActivity();
        if (!addOk) {
          setLeavePrompt(null);
          resolve(false);
          return;
        }
      }
      setLeavePrompt(null);
      resolve(true);
      return;
    }
    if (choice === 'discard') {
      setEditingActivityId(null);
      setEditBody('');
      setEditRefs({});
      setEditError(null);
      setNewActivityBody('');
      setNewActivityRefs({});
      setSubmitActivityError(null);
      setLeavePrompt(null);
      resolve(true);
      return;
    }
    setLeavePrompt(null);
    resolve(false);
  };

  const handleStartEditActivity = async (act: { id: string; body: string; note_refs?: NoteRefMap | null }) => {
    if (editSaving || submittingActivity) return;
    if (editingActivityId === act.id) return;
    if (editDirty) {
      const ok = await new Promise<boolean>((resolve) => setLeavePrompt(() => resolve));
      if (!ok) return;
    }
    setEditingActivityId(act.id);
    setEditBody(act.body);
    setEditRefs(act.note_refs ?? {});
    setEditError(null);
  };

  const handleCloseClick = async () => {
    if (await confirmLeave()) onClose();
  };

  const handleToggleStatus = async () => {
    const nextStatus =
      detailStatus === TaskStatus.TaskStatusDone
        ? TaskStatus.TaskStatusTodo
        : TaskStatus.TaskStatusDone;
    setDetailStatus(nextStatus);
    if (nextStatus === TaskStatus.TaskStatusDone) {
      playLogoSuccess();
    }
    await saveTask({ status: nextStatus });
  };

  const handleDueChange = async (newDue: string | null) => {
    setDueOpen(false);
    const formatted = newDue ? newDue : '';
    if (formatted === detailDue) return;
    setDetailDue(formatted);
    await saveTask({ due: formatted ? formatted : null });
  };

  const handleRemoveTag = async (tagToRemove: string) => {
    const nextTags = detailTags.filter((t) => t.toLowerCase() !== tagToRemove.toLowerCase());
    setDetailTags(nextTags);
    await saveTask({ tags: nextTags });
  };

  const handleAddTag = async (rawTag: string): Promise<boolean> => {
    const res = validateTag(rawTag);
    if (!res.ok) return false;
    const clean = res.tag!;
    if (hasTag(detailTags, clean)) {
      return true;
    }
    const nextTags = dedupeTags([...detailTags, clean]);
    setDetailTags(nextTags);
    await saveTask({ tags: nextTags });
    return true;
  };

  const handleTitleBlur = async () => {
    const trimmed = detailTitle.trim();
    if (!trimmed) {
      if (task) setDetailTitle(task.title);
      return;
    }
    if (task && trimmed !== task.title) {
      await saveTask({ title: trimmed });
    }
  };

  const handleBodyChange = (val: string) => {
    hasDraftRef.current = true;
    setDetailBody(val);

    if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    if (externalModifiedRef.current) return;
    debounceTimerRef.current = setTimeout(() => {
      const taskDesc = latestTaskRef.current ? (latestTaskRef.current.description ?? latestTaskRef.current.body ?? '') : '';
      if (val !== taskDesc) {
        void saveTask({ body: val });
      }
    }, 1500);
  };

  const handleBodyBlur = async () => {
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = null;
    }
    const taskDesc = task ? (task.description ?? task.body ?? '') : '';
    if (task && detailBody !== taskDesc) {
      await saveTask({ body: detailBody });
    }
    setIsEditingBody(false);
  };

  const handleDeleteTask = async () => {
    setDeleting(true);
    try {
      await VaultService.DeleteTask(taskId);
      setDeleteModalOpen(false);
      onChanged();
      onDeleted();
    } catch (err: any) {
      setDetailError(`删除失败: ${err?.message || err}`);
      setDeleteModalOpen(false);
    } finally {
      setDeleting(false);
    }
  };

  // ⌘S / Ctrl+S keyboard shortcut to force save
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        void saveTask();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [saveTask]);

  const { todayStr, tomorrowStr, nextMondayStr } = useMemo(() => getPresetDates(), []);
  const dueDisplay = useMemo(() => formatDueDisplay(detailDue), [detailDue]);

  const timelineItems = useMemo(
    () => buildTaskTimelineItems(task, taskActivities),
    [task, taskActivities]
  );

  if (!task) {
    return (
      <div className="h-full flex flex-col min-h-0 p-6 space-y-4 text-xs text-stone-500">
        <button
          onClick={onClose}
          className="flex items-center space-x-1.5 px-2.5 py-1.5 rounded-md font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 transition w-fit"
        >
          <ArrowRight className="w-3.5 h-3.5" />
          <span>{closeLabel}</span>
        </button>
        {loadError ? (
          <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200">
            加载任务失败: {loadError}
          </div>
        ) : (
          <div className="py-8 text-center text-stone-400">加载中...</div>
        )}
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col min-h-0 bg-stone-50/50 dark:bg-stone-900/50 select-text">
      {/* 1. Top Navigation Bar */}
      <div className="flex items-center justify-between px-6 py-3 border-b border-stone-200/80 dark:border-stone-800/80 shrink-0">
        <button
          type="button"
          onClick={handleCloseClick}
          className="p-1.5 -ml-1.5 rounded-md text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 transition"
          title={closeLabel}
        >
          <ArrowRight className="w-4 h-4" />
        </button>

        <div className="flex items-center space-x-1">
          {saving && (
            <span className="text-[11px] text-stone-400 dark:text-stone-500 mr-1 select-none animate-pulse">
              保存中...
            </span>
          )}
          <div className="relative" ref={menuRef}>
            <button
              type="button"
              onClick={() => setMenuOpen((v) => !v)}
              className="p-1.5 -mr-1.5 rounded-md text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 transition"
              title="更多操作"
            >
              <MoreHorizontal className="w-4 h-4" />
            </button>

            {menuOpen && (
              <div className="absolute right-0 top-full mt-1 w-40 rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 shadow-lg py-1 z-30">
                <button
                  type="button"
                  onClick={() => {
                    setMenuOpen(false);
                    setShowTaskInfo(true);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-stone-800 dark:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left"
                >
                  <Info className="w-3.5 h-3.5 text-stone-400 shrink-0" />
                  <span>任务信息</span>
                </button>
                {planDateContext && (
                  <button
                    type="button"
                    onClick={async () => {
                      setMenuOpen(false);
                      if (!(await confirmLeave())) return;
                      setRemovingFromPlan(true);
                      try {
                        const ok = await planDateContext.onRemoveFromPlan(taskId, planDateContext.date);
                        if (ok) {
                          onClose();
                        } else {
                          setDetailError('移出计划失败，请重试');
                        }
                      } catch (err: any) {
                        setDetailError(`移出计划失败: ${err?.message || err}`);
                      } finally {
                        setRemovingFromPlan(false);
                      }
                    }}
                    disabled={removingFromPlan || saving}
                    className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-stone-800 dark:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left disabled:opacity-50"
                  >
                    <CalendarMinus className="w-3.5 h-3.5 text-stone-400 shrink-0" />
                    <span>{planDateContext.isToday ? '移出今日计划' : '移出当日计划'}</span>
                  </button>
                )}
                <div className="my-1 border-t border-stone-100 dark:border-stone-800" />
                <button
                  type="button"
                  onClick={() => {
                    setMenuOpen(false);
                    setDeleteModalOpen(true);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 transition text-left"
                >
                  <Trash2 className="w-3.5 h-3.5 shrink-0" />
                  <span>删除任务</span>
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* 2. Scrollable Middle Content with Floating Activity Composer */}
      <div className="relative flex-1 min-h-0">
        <div className="h-full overflow-y-auto px-6 py-4 pb-36 space-y-4">
        {/* External Modification Warning Banner */}
        {(externalModified || conflictError) && (
          <div className="p-3 rounded-lg border border-amber-300 dark:border-amber-800/80 bg-amber-50 dark:bg-amber-950/40 text-amber-900 dark:text-amber-200 text-xs flex items-center justify-between gap-3 shadow-xs">
            <div className="flex items-center space-x-2 min-w-0">
              <AlertCircle className="w-4 h-4 text-amber-600 shrink-0" />
              <span className="font-medium">
                {conflictError
                  ? '文件已被外部修改（保存冲突）'
                  : '文件已被外部修改，自动保存已暂停；草稿已保留，重新加载将替换任务内容'}
              </span>
            </div>
            <button
              type="button"
              onClick={() => void reload()}
              className="flex items-center space-x-1 px-2.5 py-1 rounded-md bg-amber-600 hover:bg-amber-700 text-white text-xs font-medium transition shrink-0"
            >
              <RefreshCw className="w-3 h-3" />
              <span>重新加载</span>
            </button>
          </div>
        )}

        {/* Generic Error Banner */}
        {detailError && !conflictError && (
          <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-start space-x-2">
            <AlertCircle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
            <div className="space-y-0.5">
              <div className="font-semibold">保存失败</div>
              <div className="font-mono text-[11px] break-all">{detailError}</div>
            </div>
          </div>
        )}

        {/* Task Title (Inline, borderless, natural auto-growing) */}
        <div>
          <textarea
            ref={titleTextareaRef}
            value={detailTitle}
            onChange={(e) => {
              hasDraftRef.current = true;
              setDetailTitle(e.target.value);
              adjustTextareaHeight(e.target, 28);
            }}
            onBlur={handleTitleBlur}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                (e.target as HTMLTextAreaElement).blur();
              }
            }}
            placeholder="任务标题..."
            rows={1}
            className="w-full text-lg font-semibold text-stone-900 dark:text-stone-100 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 resize-none overflow-hidden p-0 leading-snug transition-none placeholder:text-stone-400"
          />
        </div>

        {/* Task Properties (Status, Due, Tags) */}
        <div className="space-y-2 pt-1">
          {/* Row 1: Status & Due Date */}
          <div className="flex flex-wrap items-center gap-2">
            {/* Status Checkbox */}
            <button
              type="button"
              role="checkbox"
              aria-checked={detailStatus === TaskStatus.TaskStatusDone}
              onClick={() => void handleToggleStatus()}
              className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-xs font-medium transition cursor-pointer select-none ${
                detailStatus === TaskStatus.TaskStatusDone
                  ? 'text-emerald-700 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/40 hover:bg-emerald-100/70 dark:hover:bg-emerald-900/50'
                  : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
              }`}
              title={detailStatus === TaskStatus.TaskStatusDone ? '点击恢复为待办' : '点击标记为完成'}
            >
              <span
                className={`w-3.5 h-3.5 rounded border flex items-center justify-center transition-colors ${
                  detailStatus === TaskStatus.TaskStatusDone
                    ? 'bg-emerald-600 border-emerald-600 text-white'
                    : 'border-stone-400 dark:border-stone-500 bg-transparent'
                }`}
              >
                {detailStatus === TaskStatus.TaskStatusDone && (
                  <Check className="w-2.5 h-2.5 stroke-[3]" />
                )}
              </span>
              <span>{detailStatus === TaskStatus.TaskStatusDone ? '已完成' : '待办'}</span>
            </button>

            {/* Due Date Dropdown */}
            <div className="relative" ref={dueRef}>
              <button
                type="button"
                onClick={() => setDueOpen((v) => !v)}
                className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-xs font-medium transition ${
                  dueDisplay.isOverdue
                    ? 'text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40'
                    : dueDisplay.isToday
                    ? 'text-amber-700 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-950/40'
                    : detailDue
                    ? 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
                    : 'text-stone-400 dark:text-stone-500 hover:text-stone-700 dark:hover:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
                }`}
              >
                <Calendar className="w-3.5 h-3.5 shrink-0" />
                <span>{dueDisplay.text}</span>
              </button>

              {dueOpen && (
                <div className="absolute left-0 top-full mt-1 w-48 rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 shadow-lg p-2 z-30 space-y-2">
                  <div className="space-y-0.5">
                    <button
                      type="button"
                      onClick={() => void handleDueChange(todayStr)}
                      className="w-full text-left px-2 py-1 rounded text-xs text-stone-800 dark:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
                    >
                      今天
                    </button>
                    <button
                      type="button"
                      onClick={() => void handleDueChange(tomorrowStr)}
                      className="w-full text-left px-2 py-1 rounded text-xs text-stone-800 dark:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
                    >
                      明天
                    </button>
                    <button
                      type="button"
                      onClick={() => void handleDueChange(nextMondayStr)}
                      className="w-full text-left px-2 py-1 rounded text-xs text-stone-800 dark:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
                    >
                      下周一
                    </button>
                  </div>

                  <div className="pt-1.5 border-t border-stone-100 dark:border-stone-800">
                    <label className="block text-[10px] text-stone-400 mb-1">选择具体日期</label>
                    <input
                      type="date"
                      value={detailDue}
                      onChange={(e) => void handleDueChange(e.target.value)}
                      className="w-full px-2 py-1 text-xs rounded border border-stone-200 dark:border-stone-800 bg-stone-50 dark:bg-stone-950 text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-0 focus:border-stone-300 dark:focus:border-stone-700"
                    />
                  </div>

                  {detailDue && (
                    <div className="pt-1 border-t border-stone-100 dark:border-stone-800">
                      <button
                        type="button"
                        onClick={() => void handleDueChange(null)}
                        className="w-full text-left px-2 py-1 rounded text-xs text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 transition"
                      >
                        清除截止日期
                      </button>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* Row 2: Tags */}
          <TagChipEditor
            tags={detailTags}
            suggestedTags={tagNames}
            onAddTag={handleAddTag}
            onRemoveTag={handleRemoveTag}
            className="pt-0.5"
          />
        </div>

        {/* Task Description (Seamless inline viewing and editing, 0px size jumping, clickable [[ notes) */}
        <div className="space-y-1 pt-1">
          <div className="text-[11px] font-medium text-stone-400 dark:text-stone-500">
            描述
          </div>
          {isEditingBody || !detailBody.trim() ? (
            <NoteRefTextarea
              value={detailBody}
              onChange={handleBodyChange}
              refs={detailRefs}
              onRefsChange={(nextRefs) => {
                setDetailRefs(nextRefs);
                latestRefsRef.current = nextRefs;
                if (latestTaskRef.current) {
                  void saveTask({ refs: nextRefs });
                }
              }}
              notes={noteRefs}
              autoAdjustHeight
              minHeight={22}
              onBlur={handleBodyBlur}
              autoFocus={isEditingBody}
              onKeyDown={(e) => {
                if (e.key === 'Escape') {
                  setIsEditingBody(false);
                }
              }}
              placeholder="添加描述… (输入 [[ 引用笔记)"
              rows={1}
              className="w-full text-xs sm:text-sm text-stone-800 dark:text-stone-200 placeholder-stone-400 dark:placeholder-stone-500 bg-transparent border-0 outline-none focus:outline-none focus:ring-0 resize-none overflow-hidden leading-relaxed p-0 min-h-[22px] transition-none"
            />
          ) : (
            <div
              role="button"
              tabIndex={0}
              onClick={() => {
                if (!window.getSelection()?.toString()) {
                  setIsEditingBody(true);
                }
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  setIsEditingBody(true);
                }
              }}
              className="cursor-text leading-relaxed text-xs sm:text-sm text-stone-800 dark:text-stone-200 p-0 border-0 outline-none focus:outline-none min-h-[22px] select-text"
            >
              <NoteRefText
                text={detailBody}
                refs={detailRefs}
                notes={noteRefs}
                onOpenNote={(id) => onOpenNote?.(id, taskId)}
                className="leading-relaxed"
              />
            </div>
          )}
        </div>

        {/* Divider */}
        <div className="border-t border-stone-200/80 dark:border-stone-800/80 my-3" />

        {/* Activities Section */}
        <div className="space-y-3 pt-1">
          <div className="text-[11px] font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider">
            活动
          </div>

          {activityListError && (
            <div className="p-2.5 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center space-x-2">
              <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
              <span>加载活动列表失败: {activityListError}</span>
            </div>
          )}

          {timelineItems.length === 0 ? (
            <div className="py-4 text-center text-xs text-stone-400 dark:text-stone-500">
              暂无活动记录
            </div>
          ) : (
            <div className="divide-y divide-stone-200/70 dark:divide-stone-800">
              {timelineItems.map((item) => {
                if (item.kind === 'status_event') {
                  return (
                    <ActivityItem
                      key={item.key}
                      timeStr={formatActivityTimestamp(item.at)}
                      fullTimeStr={formatFullLocalTimestamp(item.at)}
                      statusEvent={{ action: item.action, by: item.by }}
                      notes={noteRefs}
                      onOpenNote={(id) => onOpenNote?.(id, taskId)}
                    />
                  );
                }

                const act = item.activity;
                const isEditing = editingActivityId === act.id;
                return (
                  <ActivityItem
                    key={item.key}
                    timeStr={formatActivityTimestamp(act.at)}
                    fullTimeStr={formatFullLocalTimestamp(act.at)}
                    activity={{
                      id: act.id,
                      by: act.by,
                      body: act.body,
                      tags: act.tags,
                      note_refs: act.note_refs,
                    }}
                    notes={noteRefs}
                    onOpenNote={(id) => onOpenNote?.(id, taskId)}
                    isEditing={isEditing}
                    editBody={editBody}
                    editRefs={editRefs}
                    editSaving={editSaving}
                    editError={isEditing ? editError : null}
                    onStartEdit={() => {
                      void handleStartEditActivity(act);
                    }}
                    onEditBodyChange={setEditBody}
                    onEditRefsChange={setEditRefs}
                    onSaveEdit={() => {
                      void handleSaveActivityEdit(act.id, act.tags ?? []);
                    }}
                    onCancelEdit={() => {
                      setEditingActivityId(null);
                      setEditError(null);
                    }}
                  />
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Floating Activity Composer */}
      {/* focus-within:ring-2 focus-within:ring-emerald-500/20 */}
      <div className="pointer-events-none absolute bottom-0 inset-x-0 p-4 pt-8 bg-gradient-to-t from-stone-50/95 via-stone-50/60 to-transparent dark:from-stone-900/95 dark:via-stone-900/60 z-10">
        <div className="pointer-events-auto shadow-lg shadow-stone-900/10 dark:shadow-stone-950/40 rounded-xl">
          <ActivityComposer
            value={newActivityBody}
            onChange={setNewActivityBody}
            refs={newActivityRefs}
            onRefsChange={setNewActivityRefs}
            notes={noteRefs}
            placeholder="记录进展… (输入 [[ 引用笔记)"
            minRows={2}
            submitting={submittingActivity}
            onSubmit={() => void handleAddActivity()}
            error={submitActivityError}
            onClearError={() => setSubmitActivityError(null)}
            ariaLabel="任务进展记录输入"
          />
        </div>
      </div>
    </div>

      {/* Task Info Modal */}
      {showTaskInfo && (
        <div className="pata-fade fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-stone-100 dark:border-stone-800">
              <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">任务信息</h3>
              <button
                type="button"
                onClick={() => setShowTaskInfo(false)}
                className="text-stone-400 hover:text-stone-600 dark:hover:text-stone-200 transition"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="space-y-3 text-xs">
              <div>
                <div className="text-[11px] text-stone-400 mb-0.5">任务 ID</div>
                <div className="font-mono text-stone-800 dark:text-stone-200 select-all bg-stone-100/60 dark:bg-stone-800/60 px-2 py-1 rounded">
                  {task.id}
                </div>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <div className="text-[11px] text-stone-400 mb-0.5">创建时间</div>
                  <div className="font-mono text-[11px] text-stone-700 dark:text-stone-300">
                    {formatFullLocalTimestamp(task.created_at) || '-'}
                  </div>
                </div>
                <div>
                  <div className="text-[11px] text-stone-400 mb-0.5">更新时间</div>
                  <div className="font-mono text-[11px] text-stone-700 dark:text-stone-300">
                    {formatFullLocalTimestamp(task.updated_at) || '-'}
                  </div>
                </div>
              </div>
            </div>

            <div className="flex justify-end pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => setShowTaskInfo(false)}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                关闭
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {deleteModalOpen && (
        <div className="pata-fade fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 shrink-0">
                <AlertCircle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">确认删除任务？</h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  任务「{task.title}」的文件将从 Vault 中永久删除。任务及其活动记录将一起删除，此操作不可撤销。
                </p>
              </div>
            </div>

            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => setDeleteModalOpen(false)}
                disabled={deleting}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                取消
              </button>
              <button
                type="button"
                onClick={handleDeleteTask}
                disabled={deleting}
                className="px-3 py-1.5 rounded-md bg-rose-600 hover:bg-rose-700 text-white text-xs font-medium transition disabled:opacity-50"
              >
                {deleting ? '删除中...' : '确认删除'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Unsaved Activity Draft Leave Prompt */}
      {leavePrompt && (
        <div className="pata-fade fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="space-y-1">
              <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">有未保存的记录</h3>
              <p className="text-xs text-stone-500 leading-relaxed">
                {editDirty && newActivityBody.trim()
                  ? '有正在编辑的评论与未发送的记录草稿，离开前是否保存？'
                  : editDirty
                  ? '有正在编辑的评论草稿，离开前是否保存？'
                  : '活动输入框中有未发送的草稿，是否发送后继续离开？'}
              </p>
            </div>
            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                autoFocus
                onClick={() => void finishLeavePrompt('cancel')}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition cursor-pointer"
              >
                取消
              </button>
              <button
                type="button"
                onClick={() => void finishLeavePrompt('discard')}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-950/40 transition cursor-pointer"
              >
                放弃
              </button>
              <button
                type="button"
                onClick={() => void finishLeavePrompt('save')}
                disabled={submittingActivity || editSaving}
                className="px-3 py-1.5 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition disabled:opacity-50 cursor-pointer"
              >
                {submittingActivity || editSaving ? '保存中...' : '保存并离开'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
});
