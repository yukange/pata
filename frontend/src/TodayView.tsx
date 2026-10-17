import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { Events } from '@wailsio/runtime';
import {
  ChevronLeft,
  ChevronRight,
  RotateCcw,
  CheckCircle2,
  Circle,
  ArrowUp,
  ArrowDown,
  CalendarMinus,
  Plus,
  Search,
  X,
  AlertCircle,
  FolderOpen,
  FileText,
  Send,
  Undo2,
  Pencil,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { Task, TaskStatus } from '../bindings/pata/internal/storage/markdown/models';
import { VaultStatus, CreateTaskInput, TimelineItem, CreateActivityInput } from '../bindings/pata/models';
import { playLogoSuccess } from './logoAnimation';
import { QuickCreateInput } from './QuickCreateInput';
import { TaskDetailPanel, TaskDetailHandle } from './TaskDetailPanel';
import { DetailSplit, useDetailOrigin } from './DetailSplit';
import { NoteRefText, NoteRefTextarea, NoteRefMap, pruneRefs, sameRefs, useNoteRefs } from './noteRefs';

interface TodayViewProps {
  vaultStatus: VaultStatus | null;
  onSelectVault: () => void;
  vaultBusy?: boolean;
  onOpenNote?: (noteId: string, fromTaskId?: string) => void;
  /** 从笔记返回时恢复打开的任务详情。 */
  initialTaskId?: string | null;
  onInitialTaskConsumed?: () => void;
  /** 打开指定日期的日计划 */
  initialDate?: string | null;
  onInitialDateConsumed?: () => void;
  tagNames: string[];
  onVaultDataChanged: () => void;
  leaveGuardRef: React.MutableRefObject<(() => Promise<boolean>) | null>;
}

function formatTimelineTime(isoString: string): string {
  const d = new Date(isoString);
  if (!isoString || isNaN(d.getTime())) return isoString;
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function getLocalDateStr(d: Date = new Date()): string {
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function shiftDateStr(dateStr: string, offsetDays: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const date = new Date(y, m - 1, d);
  date.setDate(date.getDate() + offsetDays);
  return getLocalDateStr(date);
}

function formatDateDisplay(dateStr: string): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const date = new Date(y, m - 1, d);
  const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
  return `${m} 月 ${d} 日 · 星期${weekdays[date.getDay()]}`;
}

const iconBtn =
  'p-1 rounded text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition disabled:opacity-20 focus:outline-none focus:ring-0';

function Banner({
  tone,
  onClose,
  children,
}: {
  tone: 'amber' | 'rose';
  onClose?: () => void;
  children: React.ReactNode;
}) {
  const cls =
    tone === 'amber'
      ? 'border-amber-200 dark:border-amber-900/60 bg-amber-50/80 dark:bg-amber-950/40 text-amber-900 dark:text-amber-200'
      : 'border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200';
  return (
    <div className={`px-3 py-2 rounded-lg border text-xs flex items-start justify-between gap-2 ${cls}`}>
      <div className="flex items-start gap-2 min-w-0">
        <AlertCircle className="w-4 h-4 shrink-0 mt-px" />
        <div className="min-w-0 break-words">{children}</div>
      </div>
      {onClose && (
        <button type="button" onClick={onClose} className="p-0.5 rounded shrink-0 opacity-70 hover:opacity-100" title="关闭提示">
          <X className="w-3.5 h-3.5" />
        </button>
      )}
    </div>
  );
}

export function TodayView({
  vaultStatus,
  onSelectVault,
  vaultBusy = false,
  onOpenNote,
  initialTaskId,
  onInitialTaskConsumed,
  initialDate,
  onInitialDateConsumed,
  tagNames,
  onVaultDataChanged,
  leaveGuardRef,
}: TodayViewProps) {
  const todayStr = useMemo(() => getLocalDateStr(), []);
  const [selectedDate, setSelectedDate] = useState<string>(
    initialDate && /^\d{4}-\d{2}-\d{2}$/.test(initialDate) ? initialDate : todayStr
  );

  useEffect(() => {
    if (initialDate && /^\d{4}-\d{2}-\d{2}$/.test(initialDate)) {
      setSelectedDate(initialDate);
      onInitialDateConsumed?.();
    }
  }, [initialDate, onInitialDateConsumed]);

  const [tasks, setTasks] = useState<Task[]>([]);
  const [dayPlanTaskIds, setDayPlanTaskIds] = useState<string[]>([]);
  const [yesterdayTaskIds, setYesterdayTaskIds] = useState<string[]>([]);
  const [timelineItems, setTimelineItems] = useState<TimelineItem[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [noticeMsg, setNoticeMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  // 任务已创建但加入计划失败：保留 ID，重试只写计划，不再创建任务
  const [pendingPlan, setPendingPlan] = useState<{ id: string; title: string; date: string; error: string } | null>(null);

  // Quick activity + inline edit
  const noteRefs = useNoteRefs();
  const [quickActivityBody, setQuickActivityBody] = useState('');
  const [quickActivityRefs, setQuickActivityRefs] = useState<NoteRefMap>({});
  const [creatingActivity, setCreatingActivity] = useState(false);
  const [activityError, setActivityError] = useState<string | null>(null);
  const [editingActivityId, setEditingActivityId] = useState<string | null>(null);
  const [editBody, setEditBody] = useState('');
  const [editRefs, setEditRefs] = useState<NoteRefMap>({});
  const [editSaving, setEditSaving] = useState(false);
  const [leavePrompt, setLeavePrompt] = useState<((r: boolean) => void) | null>(null);

  const [addModalOpen, setAddModalOpen] = useState(false);
  const [addSearch, setAddSearch] = useState('');

  // 原地详情
  const [openTaskId, setOpenTaskId] = useState<string | null>(initialTaskId ?? null);
  useEffect(() => {
    if (initialTaskId) onInitialTaskConsumed?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const panelRef = useRef<TaskDetailHandle>(null);
  const origin = useDetailOrigin();

  useEffect(() => {
    if (!noticeMsg) return;
    const timer = setTimeout(() => setNoticeMsg(null), 5000);
    return () => clearTimeout(timer);
  }, [noticeMsg]);

  const loadData = useCallback(async () => {
    if (!vaultStatus?.open) {
      setTasks([]);
      setDayPlanTaskIds([]);
      setYesterdayTaskIds([]);
      setTimelineItems([]);
      setError(null);
      return;
    }
    setError(null);
    try {
      const [allTasksRes, planRes, timelineRes] = await Promise.all([
        VaultService.ListTasks(),
        VaultService.GetDayPlan(selectedDate),
        VaultService.GetDayTimeline(selectedDate),
      ]);
      setTasks((allTasksRes ?? []).filter((t): t is Task => t !== null));
      setDayPlanTaskIds((planRes?.task_ids ?? []).filter((id): id is string => typeof id === 'string'));
      setTimelineItems((timelineRes ?? []).filter((item): item is TimelineItem => item !== null));

      // 今天：昨日计划里未完成的任务仅作候选
      if (selectedDate === todayStr) {
        const yPlanRes = await VaultService.GetDayPlan(shiftDateStr(todayStr, -1));
        setYesterdayTaskIds((yPlanRes?.task_ids ?? []).filter((id): id is string => typeof id === 'string'));
      } else {
        setYesterdayTaskIds([]);
      }
    } catch (err: any) {
      console.error('Failed to load today data:', err);
      setError(err?.message || String(err));
    }
  }, [vaultStatus?.open, vaultStatus?.path, selectedDate, todayStr]);

  const currentPathRef = useRef(vaultStatus?.path);
  useEffect(() => {
    if (currentPathRef.current !== vaultStatus?.path) {
      currentPathRef.current = vaultStatus?.path;
      setPendingPlan(null);
      setNoticeMsg(null);
      setSaveError(null);
      setActivityError(null);
      setEditingActivityId(null);
    }
  }, [vaultStatus?.path]);

  useEffect(() => {
    setNoticeMsg(null);
    setSaveError(null);
    setActivityError(null);
    setEditingActivityId(null);
  }, [selectedDate]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', () => {
      void loadData();
    });
    return () => {
      unsubscribe();
    };
  }, [loadData]);

  const taskMap = useMemo(() => new Map(tasks.map((t) => [t.id, t])), [tasks]);

  const planItems = useMemo(
    () => dayPlanTaskIds.map((id) => ({ id, task: taskMap.get(id) ?? null })),
    [dayPlanTaskIds, taskMap]
  );
  const validPlanIds = useMemo(() => planItems.filter((i) => i.task).map((i) => i.id), [planItems]);

  const yesterdayCandidates = useMemo(() => {
    if (selectedDate !== todayStr) return [];
    const currentSet = new Set(dayPlanTaskIds);
    return yesterdayTaskIds
      .map((id) => taskMap.get(id))
      .filter((t): t is Task => !!t && t.status !== TaskStatus.TaskStatusDone && !currentSet.has(t.id));
  }, [selectedDate, todayStr, dayPlanTaskIds, yesterdayTaskIds, taskMap]);

  const availableTasksToAdd = useMemo(() => {
    const currentSet = new Set(dayPlanTaskIds);
    const query = addSearch.trim().toLowerCase();
    return tasks.filter((t) => {
      if (currentSet.has(t.id)) return false;
      if (!query) return true;
      return t.title.toLowerCase().includes(query) || (t.tags ?? []).some((tag) => tag.toLowerCase().includes(query));
    });
  }, [tasks, dayPlanTaskIds, addSearch]);

  // ---- 详情面板 ----
  const guardTask = async (id: string) => id !== openTaskId || ((await panelRef.current?.confirmLeave()) ?? true);

  const openTask = async (id: string) => {
    if (openTaskId && openTaskId !== id && !((await panelRef.current?.confirmLeave()) ?? true)) return;
    origin.capture();
    setOpenTaskId(id);
  };

  const closePanel = () => {
    setOpenTaskId(null);
    origin.restore();
  };

  const afterTaskWrite = async (id: string) => {
    await loadData();
    onVaultDataChanged();
    if (id === openTaskId) await panelRef.current?.reload();
  };

  // ---- 计划写入 ----
  const reportSaveError = (err: any) => {
    const errStr = err?.message || String(err);
    setSaveError(errStr);
    return errStr;
  };

  // 保存当前日期计划；已失效的 ID 一并剔除。成功返回 true。
  const persistPlan = async (newTaskIds: string[]): Promise<boolean> => {
    setSaving(true);
    setSaveError(null);
    try {
      const filtered = newTaskIds.filter((id) => taskMap.has(id));
      const dropped = newTaskIds.length - filtered.length;
      const updated = await VaultService.SaveDayPlan(selectedDate, filtered);
      setDayPlanTaskIds((updated?.task_ids ?? filtered).filter((id): id is string => typeof id === 'string'));
      setNoticeMsg(dropped > 0 ? `已同步移除 ${dropped} 个失效任务占位` : null);
      return true;
    } catch (err: any) {
      console.error('Failed to save day plan:', err);
      reportSaveError(err);
      await loadData();
      return false;
    } finally {
      setSaving(false);
    }
  };

  const handleMove = async (taskId: string, direction: 'up' | 'down') => {
    const i = validPlanIds.indexOf(taskId);
    const j = direction === 'up' ? i - 1 : i + 1;
    if (i === -1 || j < 0 || j >= validPlanIds.length) return;
    const ids = [...validPlanIds];
    [ids[i], ids[j]] = [ids[j], ids[i]];
    await persistPlan(ids);
  };

  const handleRemove = (taskId: string) => persistPlan(dayPlanTaskIds.filter((id) => id !== taskId));

  const handleAddExisting = async (taskId: string) => {
    if (validPlanIds.includes(taskId)) return;
    await persistPlan([...validPlanIds, taskId]);
  };

  // 把已创建的任务追加到指定日期的计划；失败时保留 pendingPlan 供重试
  const addCreatedToPlan = async (date: string, id: string, title: string) => {
    try {
      const [plan, all] = await Promise.all([VaultService.GetDayPlan(date), VaultService.ListTasks()]);
      const known = new Set((all ?? []).map((t) => t?.id));
      const existing = (plan?.task_ids ?? []).filter((x): x is string => typeof x === 'string');
      const kept = existing.filter((x) => known.has(x));
      if (!kept.includes(id)) await VaultService.SaveDayPlan(date, [...kept, id]);
      setPendingPlan(null);
      if (kept.length < existing.length) setNoticeMsg(`已同步移除 ${existing.length - kept.length} 个失效任务占位`);
    } catch (err: any) {
      console.error('Failed to add created task to plan:', err);
      setPendingPlan({ id, title, date, error: err?.message || String(err) });
    }
    await loadData();
  };

  // Today 创建：先建 Task（失败则抛出让输入保留），再追加到当前查看日期
  const handleQuickCreate = async (title: string, tags: string[]) => {
    const input: CreateTaskInput = {
      title,
      tags,
      status: TaskStatus.TaskStatusTodo,
    };
    const created = await VaultService.CreateTask(input);
    if (!created) throw new Error('未返回任务');
    onVaultDataChanged();
    setSaveError(null);
    await addCreatedToPlan(selectedDate, created.id, created.title);
  };

  // ---- 行内任务动作 ----
  const handleToggleStatus = async (task: Task) => {
    if (!(await guardTask(task.id))) return;
    const nextStatus =
      task.status === TaskStatus.TaskStatusDone
        ? TaskStatus.TaskStatusTodo
        : TaskStatus.TaskStatusDone;
    try {
      await VaultService.SetTaskStatus(task.id, nextStatus);
      setSaveError(null);
      await afterTaskWrite(task.id);
    } catch (err: any) {
      reportSaveError(`变更状态失败: ${err?.message || err}`);
      await loadData();
    }
  };

  // ---- Activity ----
  const handleCreateQuickActivity = async () => {
    const body = quickActivityBody.trim();
    if (!body) return true;
    setCreatingActivity(true);
    setActivityError(null);
    try {
      const input: CreateActivityInput = {
        date: selectedDate,
        body,
        tags: [],
        note_refs: pruneRefs(body, quickActivityRefs),
      };
      await VaultService.CreateActivity(input);
      playLogoSuccess();
      setQuickActivityBody('');
      setQuickActivityRefs({});
      await loadData();
      return true;
    } catch (err: any) {
      console.error('Failed to create activity:', err);
      setActivityError(err?.message || String(err));
      return false;
    } finally {
      setCreatingActivity(false);
    }
  };

  const handleSaveActivityEdit = async (id: string, tags: string[]) => {
    setEditSaving(true);
    setActivityError(null);
    try {
      await VaultService.UpdateActivity({ id, body: editBody, tags, note_refs: pruneRefs(editBody, editRefs) });
      setEditingActivityId(null);
      await loadData();
      return true;
    } catch (err: any) {
      setActivityError(err?.message || String(err));
      return false;
    } finally {
      setEditSaving(false);
    }
  };

  const editingActivity = timelineItems.find((item) => item.activity?.id === editingActivityId)?.activity;
  const editDirty = !!editingActivityId && (!editingActivity || editBody !== editingActivity.body ||
    !sameRefs(pruneRefs(editBody, editRefs), pruneRefs(editingActivity.body, editingActivity.note_refs ?? {})));

  // 全局导航和笔记跳转共用草稿确认；保存失败时不离开 Today。
  useEffect(() => {
    leaveGuardRef.current = async () => {
      if (creatingActivity || editSaving || leavePrompt) return false;
      if ((quickActivityBody.trim() || editDirty) && !(await new Promise<boolean>((resolve) => setLeavePrompt(() => resolve)))) return false;
      return (await panelRef.current?.confirmLeave()) ?? true;
    };
    return () => { leaveGuardRef.current = null; };
  }, [leaveGuardRef, quickActivityBody, editDirty, creatingActivity, editSaving, leavePrompt]);

  const finishLeavePrompt = async (choice: 'save' | 'discard' | 'cancel') => {
    const resolve = leavePrompt;
    if (!resolve) return;
    if (choice === 'save') {
      // 编辑中的记录可能被外部删除；不能误报已保存或改成另一条记录。
      if (editDirty && !editingActivity) {
        setActivityError('编辑中的记录已不可用，请保留草稿并重新加载');
        setLeavePrompt(null);
        resolve(false);
        return;
      }
      const ok = (!editDirty || await handleSaveActivityEdit(editingActivityId!, editingActivity?.tags ?? [])) &&
        (!quickActivityBody.trim() || await handleCreateQuickActivity());
      setLeavePrompt(null);
      resolve(ok);
      return;
    }
    if (choice === 'discard') {
      setQuickActivityBody('');
      setQuickActivityRefs({});
      setEditingActivityId(null);
    }
    setLeavePrompt(null);
    resolve(choice === 'discard');
  };

  // Unconfigured Vault state
  if (!vaultStatus?.configured) {
    return (
      <div className="h-full overflow-y-auto p-6">
      <div className="py-16 text-center space-y-4 max-w-md mx-auto">
        <FolderOpen className="w-12 h-12 text-emerald-600 mx-auto opacity-75" />
        <h2 className="text-base font-semibold text-stone-800 dark:text-stone-200">尚未配置 Vault 目录</h2>
        <p className="text-xs text-stone-500 leading-relaxed">
          Pata 以本地纯文本 Markdown 作为唯一数据真相源（Local First）。请先选择一个本地目录。
        </p>
        <button
          onClick={onSelectVault}
          disabled={vaultBusy}
          className="mx-auto flex items-center space-x-1.5 px-4 py-2 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition disabled:opacity-50 shadow-xs"
        >
          <FolderOpen className="w-3.5 h-3.5" />
          <span>选择 Vault 目录</span>
        </button>
      </div>
      </div>
    );
  }

  // Configured but unopened vault state
  if (!vaultStatus.open) {
    return (
      <div className="h-full overflow-y-auto p-6">
      <div className="p-5 max-w-lg mx-auto rounded-xl border border-amber-200 dark:border-amber-900/60 bg-amber-50/70 dark:bg-amber-950/30 text-xs space-y-3">
        <div className="font-medium text-amber-900 dark:text-amber-200">Vault 打开异常</div>
        <p className="text-stone-600 dark:text-stone-400">
          无法加载目录：<code className="font-mono text-[11px] text-stone-800 dark:text-stone-200">{vaultStatus.path}</code>
        </p>
        <button
          onClick={onSelectVault}
          disabled={vaultBusy}
          className="px-3.5 py-1.5 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white font-medium transition disabled:opacity-50"
        >
          重新选择目录
        </button>
      </div>
      </div>
    );
  }

  const isToday = selectedDate === todayStr;
  const completedCount = planItems.filter((i) => i.task?.status === TaskStatus.TaskStatusDone).length;
  const planWord = isToday ? '今日' : '当日';

  const taskLink = (taskId: string, title: string) => (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        void openTask(taskId);
      }}
      className="text-emerald-700 dark:text-emerald-400 hover:underline font-medium truncate max-w-[16rem] align-bottom"
      title="在右侧打开任务详情"
    >
      {title}
    </button>
  );

  const panel = openTaskId ? (
    <TaskDetailPanel
      key={openTaskId}
      ref={panelRef}
      taskId={openTaskId}
      closeLabel="关闭详情"
      tagNames={tagNames}
      onClose={closePanel}
      onChanged={() => {
        void loadData();
        onVaultDataChanged();
      }}
      onDeleted={closePanel}
      onOpenNote={onOpenNote}
    />
  ) : null;

  return (
    <>
      <DetailSplit panel={panel}>
        <div className="space-y-5">
          {/* Date bar */}
          <div className="flex items-center justify-between gap-3 h-12">
            <div className="flex items-center gap-2 min-w-0">
              <div className="flex items-center">
                <button
                  onClick={() => setSelectedDate((d) => shiftDateStr(d, -1))}
                  className={iconBtn + ' p-1.5'}
                  title="前一天"
                >
                  <ChevronLeft className="w-4 h-4" />
                </button>
                <button
                  onClick={() => setSelectedDate((d) => shiftDateStr(d, 1))}
                  className={iconBtn + ' p-1.5'}
                  title="后一天"
                >
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
              <span className="text-base font-semibold text-stone-900 dark:text-stone-100 truncate">
                {formatDateDisplay(selectedDate)}
              </span>
            </div>
            {!isToday && (
              <button
                onClick={() => setSelectedDate(todayStr)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-stone-200 dark:border-stone-800 hover:bg-stone-100 dark:hover:bg-stone-800 text-stone-600 dark:text-stone-300 text-xs font-medium transition shrink-0"
              >
                <RotateCcw className="w-3.5 h-3.5" />
                <span>回到今天</span>
              </button>
            )}
          </div>

          {noticeMsg && (
            <Banner tone="amber" onClose={() => setNoticeMsg(null)}>
              {noticeMsg}
            </Banner>
          )}
          {error && <Banner tone="rose">加载失败: {error}</Banner>}
          {saveError && (
            <Banner tone="rose" onClose={() => setSaveError(null)}>
              <div className="font-semibold">
                {saveError.includes('任务不存在') ? '计划中存在已删除任务的占位，请先移除后再试' : '操作失败'}
              </div>
              <div className="font-mono text-[11px] break-all">{saveError}</div>
            </Banner>
          )}
          {pendingPlan && (
            <Banner tone="amber">
              <div className="font-semibold">任务「{pendingPlan.title}」已创建，但未加入{pendingPlan.date === todayStr ? '今日' : pendingPlan.date}计划</div>
              <div className="font-mono text-[11px] break-all opacity-80">{pendingPlan.error}</div>
              <div className="flex gap-3 pt-1">
                <button
                  type="button"
                  onClick={() => void addCreatedToPlan(pendingPlan.date, pendingPlan.id, pendingPlan.title)}
                  className="font-medium underline"
                >
                  重新加入
                </button>
                <button type="button" onClick={() => void openTask(pendingPlan.id)} className="font-medium underline">
                  打开任务
                </button>
                <button type="button" onClick={() => setPendingPlan(null)} className="opacity-70 underline">
                  忽略
                </button>
              </div>
            </Banner>
          )}

          {/* Section A: plan */}
          <section className="space-y-3">
            <div className="flex items-center justify-between text-xs">
              <div className="flex items-baseline gap-2">
                <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">{planWord}计划</h2>
                <span className="font-mono text-stone-400">
                  {completedCount} / {planItems.length}
                </span>
              </div>
              <button
                onClick={() => {
                  setAddSearch('');
                  setAddModalOpen(true);
                }}
                disabled={saving}
                className="flex items-center gap-1 px-2 py-1 rounded-md text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 font-medium transition disabled:opacity-50"
              >
                <Plus className="w-3.5 h-3.5 text-emerald-600" />
                <span>从已有任务中选择</span>
              </button>
            </div>

            <QuickCreateInput
              placeholder={isToday ? '添加今天要做的事…  末尾可加 #标签' : '添加当日要做的事…  末尾可加 #标签'}
              submitLabel="添加"
              tagNames={tagNames}
              onSubmit={handleQuickCreate}
              disabled={saving}
            />

            {isToday && yesterdayCandidates.length > 0 && (
              <div className="rounded-lg bg-amber-50/60 dark:bg-amber-950/20 px-3 py-2 space-y-1 text-xs">
                <div className="text-amber-800 dark:text-amber-300 font-medium">
                  昨日未完成 ({yesterdayCandidates.length})
                  <span className="ml-2 font-normal text-amber-700/70 dark:text-amber-400/80">不会自动顺延，由你确认</span>
                </div>
                {yesterdayCandidates.map((cand) => (
                  <div key={cand.id} className="flex items-center justify-between gap-3">
                    <span className="truncate text-stone-800 dark:text-stone-200">{cand.title}</span>
                    <button
                      type="button"
                      onClick={() => void handleAddExisting(cand.id)}
                      disabled={saving}
                      className="flex items-center gap-1 px-2 py-0.5 rounded text-amber-800 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-900/40 font-medium shrink-0 disabled:opacity-50"
                    >
                      <Plus className="w-3 h-3" />
                      <span>加入今天</span>
                    </button>
                  </div>
                ))}
              </div>
            )}

            {planItems.length === 0 ? (
              <p className="text-xs text-stone-400 py-1">
                {isToday ? '今天还没有安排任务。' : '该日期无计划安排。'}输入标题添加，或从已有任务中选择。
              </p>
            ) : (
              <ul className="divide-y divide-stone-200/70 dark:divide-stone-800 rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950">
                {planItems.map(({ id, task }) => {
                  if (!task) {
                    return (
                      <li key={id} className="flex items-center justify-between gap-3 px-3 py-2.5 text-xs bg-rose-50/40 dark:bg-rose-950/20">
                        <div className="flex items-center gap-2 text-rose-700 dark:text-rose-300 min-w-0">
                          <AlertCircle className="w-4 h-4 shrink-0" />
                          <span className="font-mono text-[11px] truncate">[已删除任务: {id}]</span>
                        </div>
                        <button
                          type="button"
                          onClick={() => void handleRemove(id)}
                          disabled={saving}
                          className="px-2 py-0.5 rounded text-rose-700 dark:text-rose-300 hover:bg-rose-100 dark:hover:bg-rose-900/40 font-medium shrink-0"
                          title="只清除计划中的失效引用"
                        >
                          清除占位
                        </button>
                      </li>
                    );
                  }

                  const isDone = task.status === TaskStatus.TaskStatusDone;
                  const idx = validPlanIds.indexOf(task.id);
                  let dueBadge: React.ReactNode = null;
                  if (task.due && !isDone) {
                    dueBadge =
                      task.due < todayStr ? (
                        <span className="text-[10px] px-1.5 rounded font-medium bg-rose-100 text-rose-700 dark:bg-rose-950/70 dark:text-rose-300 shrink-0">
                          逾期 {task.due}
                        </span>
                      ) : task.due === todayStr ? (
                        <span className="text-[10px] px-1.5 rounded font-medium bg-amber-100 text-amber-800 dark:bg-amber-950/70 dark:text-amber-300 shrink-0">
                          今日到期
                        </span>
                      ) : (
                        <span className="text-[10px] text-stone-400 shrink-0">due {task.due}</span>
                      );
                  }

                  return (
                    <li
                      key={task.id}
                      onClick={() => void openTask(task.id)}
                      onKeyDown={(e) => {
                        if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
                          e.preventDefault();
                          void openTask(task.id);
                        }
                      }}
                      tabIndex={0}
                      role="button"
                      className={`group flex items-center gap-3 px-3 py-2.5 cursor-pointer transition first:rounded-t-xl last:rounded-b-xl hover:bg-stone-50 dark:hover:bg-stone-900/60 focus:outline-none focus:ring-0 ${
                        task.id === openTaskId ? 'bg-stone-100/80 dark:bg-stone-800/50' : ''
                      }`}
                    >
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          void handleToggleStatus(task);
                        }}
                        className="p-0.5 rounded shrink-0 focus:outline-none focus:ring-0"
                        title={isDone ? '点击恢复为待办' : '点击标记为完成'}
                      >
                        {isDone ? (
                          <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                        ) : (
                          <Circle className="w-4 h-4 text-stone-400 group-hover:text-stone-600" />
                        )}
                      </button>

                      <div className="flex items-center gap-2 min-w-0 flex-1 text-xs">
                        <span
                          className={`font-medium truncate ${
                            isDone ? 'line-through text-stone-400 dark:text-stone-500' : 'text-stone-900 dark:text-stone-100'
                          }`}
                        >
                          {task.title}
                        </span>
                        {dueBadge}
                        {(task.tags ?? []).length > 0 && (
                          <span className="hidden sm:inline-flex items-center gap-1 shrink-0">
                            {(task.tags ?? []).map((tag) => (
                              <span key={tag} className="text-[10px] text-stone-400">
                                #{tag}
                              </span>
                            ))}
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-0.5 shrink-0" onClick={(e) => e.stopPropagation()}>
                        <button
                          type="button"
                          onClick={() => void handleMove(task.id, 'up')}
                          disabled={idx <= 0 || saving}
                          className={iconBtn}
                          title="上移"
                        >
                          <ArrowUp className="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          onClick={() => void handleMove(task.id, 'down')}
                          disabled={idx === validPlanIds.length - 1 || saving}
                          className={iconBtn}
                          title="下移"
                        >
                          <ArrowDown className="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          onClick={() => void handleRemove(task.id)}
                          disabled={saving}
                          className={iconBtn + ' hover:text-amber-700'}
                          title={`移出${planWord}计划（不删除任务）`}
                          aria-label={`移出${planWord}计划`}
                        >
                          <CalendarMinus className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}

            <p className="text-[11px] text-stone-400">
              计划只是当天的执行安排，不改变截止日期（due）。
              {!isToday && '此处显示任务的当前状态与属性。'}
            </p>
          </section>

          {/* Section B: timeline */}
          <section className="space-y-3 pt-4 border-t border-stone-200/80 dark:border-stone-800">
            <div className="flex items-baseline gap-2">
              <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">{isToday ? '今日记录' : '当日记录'}</h2>
              <span className="text-xs font-mono text-stone-400">{timelineItems.length}</span>
            </div>

            <div className="space-y-1.5">
              <div className="flex items-center space-x-2">
                <div className="relative flex-1 min-w-0">
                  <NoteRefTextarea
                    value={quickActivityBody}
                    onChange={setQuickActivityBody}
                    refs={quickActivityRefs}
                    onRefsChange={setQuickActivityRefs}
                    notes={noteRefs}
                    aria-label="今日记录"
                    onKeyDown={(e) => {
                      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter' && !e.nativeEvent.isComposing && e.keyCode !== 229) {
                        e.preventDefault();
                        void handleCreateQuickActivity();
                      }
                    }}
                    placeholder="记录一句话（输入 [[ 引用笔记，⌘+Enter 发送）…"
                    rows={1}
                    disabled={creatingActivity}
                    className="block w-full px-3 py-2 text-xs rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 text-stone-900 dark:text-stone-100 placeholder-stone-400 quick-entry shadow-2xs resize-none max-h-32 leading-4"
                  />
                </div>
                <button
                  type="button"
                  onMouseDown={(e) => {
                    e.preventDefault();
                  }}
                  onClick={() => void handleCreateQuickActivity()}
                  disabled={creatingActivity || !quickActivityBody.trim()}
                  className="flex items-center space-x-1 px-3 py-2 h-[34px] rounded-lg bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition disabled:opacity-40 shadow-2xs shrink-0"
                  title="发送 (⌘+Enter)"
                >
                  <Send className="w-3.5 h-3.5" />
                  <span>{creatingActivity ? '发送中' : '发送'}</span>
                </button>
              </div>
              {!isToday && <div className="text-[11px] text-stone-400 px-1">记录将记入 {selectedDate} 的日计划</div>}
              {activityError && (
                <Banner tone="rose" onClose={() => setActivityError(null)}>
                  记录保存失败: {activityError}
                </Banner>
              )}
            </div>

            {timelineItems.length === 0 ? (
              <p className="text-xs text-stone-400 py-1">该日期暂无记录。</p>
            ) : (
              <ul className="divide-y divide-stone-200/70 dark:divide-stone-800">
                {timelineItems.map((item, idx) => {
                  const time = formatTimelineTime(item.time);
                  const exists = !!item.task_id && taskMap.has(item.task_id);
                  const title = item.task_title || item.task_id || '';
                  const label = (txt: string) => <span className="text-stone-500 dark:text-stone-400">{txt}</span>;

                  if (item.kind === 'completion' || item.kind === 'reopen') {
                    const done = item.kind === 'completion';
                    return (
                      <li key={`ev-${item.kind}-${item.task_id}-${item.time}-${idx}`} className="flex items-center gap-3 py-2 text-xs">
                        <span className="w-10 shrink-0 font-mono text-[11px] text-stone-400">{time}</span>
                        {done ? (
                          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600 shrink-0" />
                        ) : (
                          <Undo2 className="w-3.5 h-3.5 text-blue-600 shrink-0" />
                        )}
                        <span className="min-w-0 truncate">
                          {label(done ? '完成了 ' : '重新打开 ')}
                          {exists ? taskLink(item.task_id!, title) : <span className="font-medium text-stone-700 dark:text-stone-300">{title}</span>}
                          {!exists && item.task_id && <span className="ml-1 text-[10px] text-rose-500/80">(任务已删除)</span>}
                        </span>
                      </li>
                    );
                  }

                  const act = item.activity;
                  const editing = !!act && editingActivityId === act.id;
                  return (
                    <li key={`activity-${act?.id ?? idx}-${item.time}`} className="group flex items-start gap-3 py-2 text-xs">
                      <span className="w-10 shrink-0 font-mono text-[11px] text-stone-400 pt-px">{time}</span>
                      <FileText className="w-3.5 h-3.5 text-stone-400 shrink-0 mt-0.5" />
                      <div className="min-w-0 flex-1 space-y-1">
                        {editing && act ? (
                          <div className="space-y-1.5">
                            <NoteRefTextarea
                              value={editBody}
                              onChange={setEditBody}
                              refs={editRefs}
                              onRefsChange={setEditRefs}
                              notes={noteRefs}
                              aria-label="编辑记录"
                              disabled={editSaving}
                              onKeyDown={(e) => {
                                if (e.nativeEvent.isComposing || e.keyCode === 229) return;
                                if (e.key === 'Escape') setEditingActivityId(null);
                                if ((e.metaKey || e.ctrlKey) && e.key === 'Enter' && editBody.trim()) {
                                  e.preventDefault();
                                  void handleSaveActivityEdit(act.id, act.tags ?? []);
                                }
                              }}
                              autoFocus
                              rows={3}
                              className="w-full p-2 text-xs rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-0 focus:border-stone-400 dark:focus:border-stone-600 resize-y leading-relaxed"
                            />
                            <div className="flex gap-2">
                              <button
                                type="button"
                                onMouseDown={(e) => e.preventDefault()}
                                onClick={() => void handleSaveActivityEdit(act.id, act.tags ?? [])}
                                disabled={editSaving || !editBody.trim()}
                                className="px-2.5 py-1 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white font-medium disabled:opacity-40"
                              >
                                {editSaving ? '保存中' : '保存'}
                              </button>
                              <button
                                type="button"
                                onMouseDown={(e) => e.preventDefault()}
                                onClick={() => setEditingActivityId(null)}
                                className="px-2.5 py-1 rounded-md text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800"
                              >
                                取消
                              </button>
                            </div>
                          </div>
                        ) : (
                          <NoteRefText
                            text={act?.body ?? ''}
                            refs={act?.note_refs ?? undefined}
                            notes={noteRefs}
                            onOpenNote={onOpenNote}
                            className="text-stone-800 dark:text-stone-200 leading-relaxed"
                          />
                        )}
                        {(item.task_id || (act?.tags ?? []).length > 0) && !editing && (
                          <div className="flex flex-wrap items-center gap-2 text-[11px] text-stone-400">
                            {item.task_id &&
                              (exists ? (
                                <span className="truncate max-w-full">
                                  任务：{taskLink(item.task_id, title)}
                                </span>
                              ) : (
                                <span className="font-mono truncate">
                                  {item.task_id}
                                  <span className="ml-1 text-rose-500/80">(任务已删除)</span>
                                </span>
                              ))}
                            {(act?.tags ?? []).map((tag) => (
                              <span key={tag}>#{tag}</span>
                            ))}
                          </div>
                        )}
                      </div>
                      {act && !editing && (
                        <button
                          type="button"
                          onClick={() => {
                            setEditingActivityId(act.id);
                            setEditBody(act.body);
                            setEditRefs(act.note_refs ?? {});
                          }}
                          className={iconBtn + ' opacity-0 group-hover:opacity-100 focus:opacity-100'}
                          title="编辑记录"
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      </DetailSplit>

      {leavePrompt && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-label="未保存的记录">
          <div className="w-full max-w-sm rounded-xl bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">有未保存的记录</h3>
            <p className="text-xs text-stone-500">离开前是否保存今日记录及编辑中的草稿？</p>
            <div className="flex justify-end gap-2 text-xs">
              <button type="button" autoFocus disabled={creatingActivity || editSaving} onClick={() => void finishLeavePrompt('cancel')} className="px-3 py-1.5 rounded text-stone-600 dark:text-stone-300">取消</button>
              <button type="button" disabled={creatingActivity || editSaving} onClick={() => void finishLeavePrompt('discard')} className="px-3 py-1.5 rounded text-rose-600">放弃</button>
              <button type="button" disabled={creatingActivity || editSaving} onClick={() => void finishLeavePrompt('save')} className="px-3 py-1.5 rounded bg-emerald-700 text-white disabled:opacity-40">保存并离开</button>
            </div>
          </div>
        </div>
      )}

      {/* Task Picker Modal */}
      {addModalOpen && (
        <div
          className="pata-fade fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4"
          onKeyDown={(e) => e.key === 'Escape' && setAddModalOpen(false)}
        >
          <div className="w-full max-w-md rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-stone-100 dark:border-stone-800">
              <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">选择任务加入{planWord}计划</h3>
              <button type="button" onClick={() => setAddModalOpen(false)} className="text-stone-400 hover:text-stone-600 dark:hover:text-stone-200">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="relative">
              <Search className="w-3.5 h-3.5 text-stone-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={addSearch}
                onChange={(e) => setAddSearch(e.target.value)}
                placeholder="搜索任务标题或标签..."
                autoFocus
                className="w-full pl-8 pr-3 py-1.5 text-xs rounded-lg border border-stone-200 dark:border-stone-800 bg-stone-50 dark:bg-stone-950 text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none focus:ring-0 focus:border-stone-400 dark:focus:border-stone-600"
              />
            </div>

            <div className="max-h-60 overflow-y-auto space-y-1.5 pr-1">
              {availableTasksToAdd.length === 0 ? (
                <div className="py-8 text-center text-xs text-stone-400">
                  {tasks.length === 0 ? '任务池为空' : '没有可添加的任务（已全部加入或无匹配项）'}
                </div>
              ) : (
                availableTasksToAdd.map((t) => (
                  <button
                    key={t.id}
                    type="button"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={async () => {
                      await handleAddExisting(t.id);
                      setAddModalOpen(false);
                    }}
                    className="w-full text-left p-2.5 rounded-lg border border-stone-100 dark:border-stone-800 hover:border-emerald-500/60 hover:bg-stone-50 dark:hover:bg-stone-800/50 transition flex items-center justify-between gap-2"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="text-xs truncate text-stone-900 dark:text-stone-100">{t.title}</span>
                    </div>
                    <Plus className="w-3.5 h-3.5 text-emerald-600 shrink-0" />
                  </button>
                ))
              )}
            </div>

            <div className="flex justify-end pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => setAddModalOpen(false)}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                关闭
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
