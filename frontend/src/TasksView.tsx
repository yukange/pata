import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Events } from '@wailsio/runtime';
import {
  Circle,
  CheckCircle2,
  AlertCircle,
  Calendar,
  FolderOpen,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { Task, TaskStatus } from '../bindings/pata/internal/storage/markdown/models';
import { VaultStatus, CreateTaskInput } from '../bindings/pata/models';
import { QuickCreateInput } from './QuickCreateInput';
import { WorkspacePage } from './DetailSplit';

interface TasksViewProps {
  vaultStatus: VaultStatus | null;
  onSelectVault: () => void;
  vaultBusy?: boolean;
  selectedTaskId: string | null;
  onOpenTask: (taskId: string) => void;
  onGuardTask: (taskId: string) => Promise<boolean>;
  onTaskWritten: (taskId: string) => Promise<void>;
  detailRevision: number;
  /** 已有全局标签名（不带 #），用于快速创建补全。 */
  tagNames: string[];
  /** 任务写入成功后刷新全局标签等跨页面数据。 */
  onVaultDataChanged: () => void;
}

export function TasksView({
  vaultStatus,
  onSelectVault,
  vaultBusy = false,
  selectedTaskId,
  onOpenTask,
  onGuardTask,
  onTaskWritten,
  detailRevision,
  tagNames,
  onVaultDataChanged,
}: TasksViewProps) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [listError, setListError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'done'>('all');

  const loadTasks = useCallback(async () => {
    if (!vaultStatus?.open) {
      setTasks([]);
      setListError(null);
      return;
    }
    setListError(null);
    try {
      const result = await VaultService.ListTasks();
      setTasks((result ?? []).filter((t): t is Task => t !== null));
    } catch (err: any) {
      console.error('Failed to list tasks:', err);
      setListError(err?.message || String(err));
    }
  }, [vaultStatus?.open, vaultStatus?.path]);

  useEffect(() => {
    void loadTasks();
  }, [loadTasks]);

  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', () => {
      void loadTasks();
    });
    return () => {
      unsubscribe();
    };
  }, [loadTasks]);

  useEffect(() => {
    if (detailRevision) void loadTasks();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detailRevision]);

  const openTask = onOpenTask;

  const refreshAll = useCallback(() => {
    void loadTasks();
    onVaultDataChanged();
  }, [loadTasks, onVaultDataChanged]);

  // Tasks 只创建，不自动安排到任何日期
  const handleQuickCreate = async (title: string, tags: string[]) => {
    const input: CreateTaskInput = {
      title,
      tags,
      status: TaskStatus.TaskStatusTodo,
    };
    await VaultService.CreateTask(input);
    refreshAll();
  };

  const handleToggleStatus = async (task: Task, e: React.MouseEvent) => {
    e.stopPropagation();
    // 同一任务有未保存草稿时，先让用户决定，避免随后的保存覆盖这次状态修改
    if (!(await onGuardTask(task.id))) return;
    const nextStatus =
      task.status === TaskStatus.TaskStatusDone
        ? TaskStatus.TaskStatusTodo
        : TaskStatus.TaskStatusDone;

    try {
      await VaultService.SetTaskStatus(task.id, nextStatus);
      refreshAll();
      await onTaskWritten(task.id);
    } catch (err: any) {
      const isConflict =
        typeof err?.message === 'string' &&
        (err.message.includes('write conflict') || err.message.includes('conflict at'));
      if (isConflict) {
        alert(`任务「${task.title}」文件已被外部修改，无法直接变更状态。列表已自动刷新。`);
        await loadTasks();
      } else {
        alert(`变更状态失败: ${err?.message || err}`);
      }
    }
  };

  const filteredTasks = useMemo(() => {
    return tasks.filter((t) => {
      if (statusFilter === 'active' && t.status === TaskStatus.TaskStatusDone) return false;
      if (statusFilter === 'done' && t.status !== TaskStatus.TaskStatusDone) return false;
      return true;
    });
  }, [tasks, statusFilter]);

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

  return (
    <WorkspacePage>
      <div className="space-y-5">
        {/* Quick Create Bar */}
        <QuickCreateInput
          placeholder="添加任务…  末尾可加 #标签，如：完成设计 #工作"
          submitLabel="快速创建"
          tagNames={tagNames}
          onSubmit={handleQuickCreate}
        />

        {/* Status Filters */}
        <div className="flex items-center space-x-1 p-0.5 rounded-lg bg-stone-200/60 dark:bg-stone-800/80 text-xs w-fit">
          <button
            onClick={() => setStatusFilter('all')}
            className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
              statusFilter === 'all'
                ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-100 shadow-2xs'
                : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200'
            }`}
          >
            全部 ({tasks.length})
          </button>
          <button
            onClick={() => setStatusFilter('active')}
            className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
              statusFilter === 'active'
                ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-100 shadow-2xs'
                : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200'
            }`}
          >
            未完成 ({tasks.filter((t) => t.status !== TaskStatus.TaskStatusDone).length})
          </button>
          <button
            onClick={() => setStatusFilter('done')}
            className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
              statusFilter === 'done'
                ? 'bg-white dark:bg-stone-900 text-stone-900 dark:text-stone-100 shadow-2xs'
                : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200'
            }`}
          >
            已完成 ({tasks.filter((t) => t.status === TaskStatus.TaskStatusDone).length})
          </button>
        </div>

        {/* List Error Banner */}
        {listError && (
          <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center space-x-2">
            <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
            <span>加载任务列表失败: {listError}</span>
          </div>
        )}

        {/* Task List */}
        {filteredTasks.length === 0 ? (
          <div className="py-12 text-center text-xs text-stone-500 dark:text-stone-400 space-y-1">
            {listError ? (
              <div className="text-rose-600 dark:text-rose-400 font-mono text-[11px]">
                列表加载失败: {listError}
              </div>
            ) : tasks.length === 0 ? (
              <>
                <div>Vault 中暂无任务</div>
                <div className="text-[11px] text-stone-400">输入上方标题快速创建第一条任务吧</div>
              </>
            ) : (
              <div>当前分类下暂无任务</div>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            {filteredTasks.map((t) => {
              const isDone = t.status === TaskStatus.TaskStatusDone;

              return (
                <div
                  key={t.id}
                  onClick={() => void openTask(t.id)}
                  onKeyDown={(e) => {
                    if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
                      e.preventDefault();
                      void openTask(t.id);
                    }
                  }}
                  tabIndex={0}
                  role="button"
                  className={`group p-3.5 rounded-xl border bg-white dark:bg-stone-950 hover:border-stone-300 dark:hover:border-stone-700 hover:shadow-2xs transition cursor-pointer select-none focus:outline-none focus:ring-0 ${
                    t.id === selectedTaskId
                      ? 'border-stone-400 dark:border-stone-600 bg-stone-50/70 dark:bg-stone-900/50'
                      : 'border-stone-200 dark:border-stone-800'
                  }`}
                >
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center space-x-2.5 min-w-0">
                      {/* Status Toggle Button */}
                      <button
                        type="button"
                        onClick={(e) => handleToggleStatus(t, e)}
                        className="p-0.5 rounded text-stone-400 hover:text-emerald-600 dark:hover:text-emerald-400 transition shrink-0"
                        title={isDone ? '点击恢复为待办' : '点击标记为完成'}
                      >
                        {isDone ? (
                          <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                        ) : (
                          <Circle className="w-4 h-4 text-stone-400 group-hover:text-stone-600" />
                        )}
                      </button>

                      <span
                        className={`text-xs font-medium truncate ${
                          isDone
                            ? 'line-through text-stone-400 dark:text-stone-500'
                            : 'text-stone-900 dark:text-stone-100'
                        }`}
                      >
                        {t.title}
                      </span>
                    </div>

                    <div className="flex items-center space-x-1.5 shrink-0">
                      {/* Status Badge */}
                      <span
                        className={`text-[10px] px-1.5 py-0.5 rounded font-medium ${
                          isDone
                            ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/70 dark:text-emerald-300'
                            : 'bg-stone-100 text-stone-600 dark:bg-stone-800 dark:text-stone-400'
                        }`}
                      >
                        {isDone ? '已完成' : '待办'}
                      </span>
                    </div>
                  </div>

                  {/* Sub row: Due date, Tags, Updated At */}
                  <div className="flex items-center gap-3 mt-2 text-[11px] text-stone-400">
                    {t.due && (
                      <span className="flex items-center space-x-1 text-stone-500 dark:text-stone-400">
                        <Calendar className="w-3 h-3" />
                        <span>due {t.due}</span>
                      </span>
                    )}

                    {t.tags && t.tags.length > 0 && (
                      <span className="flex items-center gap-1.5">
                        {t.tags.map((tag) => (
                          <span
                            key={tag}
                            className="inline-flex items-center text-[10px] px-1.5 py-0.2 rounded bg-stone-100 dark:bg-stone-800 text-emerald-700 dark:text-emerald-300"
                          >
                            #{tag}
                          </span>
                        ))}
                      </span>
                    )}

                    <span className="ml-auto font-mono text-[10px] text-stone-400">
                      {t.updated_at ? t.updated_at.slice(0, 10) : ''}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </WorkspacePage>
  );
}
