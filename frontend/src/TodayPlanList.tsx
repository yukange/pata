import React, { useState, useEffect, useMemo, useRef } from 'react';
import { DragDropProvider, DragOverlay } from '@dnd-kit/react';
import { useSortable } from '@dnd-kit/react/sortable';
import { move } from '@dnd-kit/helpers';
import { CheckCircle2, Circle, GripVertical, AlertCircle } from 'lucide-react';
import { Task, TaskStatus } from '../bindings/pata/internal/storage/markdown/models';

export interface TodayPlanListProps {
  taskIds: string[];
  taskMap: Map<string, Task>;
  isToday: boolean;
  todayStr: string;
  selectedDate: string;
  openTaskId: string | null;
  saving: boolean;
  onOpenTask: (taskId: string) => void;
  onToggleStatus: (task: Task) => void;
  onRemoveTask: (taskId: string) => void;
  onReorder: (newTaskIds: string[]) => Promise<boolean>;
}

function renderDueBadge(task: Task, todayStr: string): React.ReactNode {
  if (!task.due || task.status === TaskStatus.TaskStatusDone) return null;
  if (task.due < todayStr) {
    return (
      <span className="text-[10px] px-1.5 rounded font-medium bg-rose-100 text-rose-700 dark:bg-rose-950/70 dark:text-rose-300 shrink-0">
        逾期 {task.due}
      </span>
    );
  }
  if (task.due === todayStr) {
    return (
      <span className="text-[10px] px-1.5 rounded font-medium bg-amber-100 text-amber-800 dark:bg-amber-950/70 dark:text-amber-300 shrink-0">
        今日到期
      </span>
    );
  }
  return <span className="text-[10px] text-stone-400 shrink-0">due {task.due}</span>;
}

interface SortableTaskItemProps {
  task: Task;
  index: number;
  todayStr: string;
  isSelected: boolean;
  disabled: boolean;
  justDraggedRef: React.MutableRefObject<boolean>;
  onOpenTask: (taskId: string) => void;
  onToggleStatus: (task: Task) => void;
}

function SortableTaskItem({
  task,
  index,
  todayStr,
  isSelected,
  disabled,
  justDraggedRef,
  onOpenTask,
  onToggleStatus,
}: SortableTaskItemProps) {
  const { ref, handleRef, isDragging } = useSortable({
    id: task.id,
    index,
    disabled,
  });

  const isDone = task.status === TaskStatus.TaskStatusDone;
  const dueBadge = renderDueBadge(task, todayStr);

  return (
    <li
      ref={ref}
      data-plan-task-id={task.id}
      onClick={() => {
        if (justDraggedRef.current) return;
        onOpenTask(task.id);
      }}
      onKeyDown={(e) => {
        if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
          e.preventDefault();
          onOpenTask(task.id);
        }
      }}
      tabIndex={0}
      role="button"
      style={{ opacity: isDragging ? 0.35 : 1 }}
      className={`group flex items-center gap-3 px-3 py-2.5 cursor-pointer first:rounded-t-xl last:rounded-b-xl hover:bg-stone-50 dark:hover:bg-stone-900/60 focus:outline-none focus:ring-0 transition-colors ${
        isSelected ? 'bg-stone-100/80 dark:bg-stone-800/50' : ''
      }`}
    >
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          onToggleStatus(task);
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

      <div className="w-6 h-6 flex items-center justify-center shrink-0" onClick={(e) => e.stopPropagation()}>
        <button
          type="button"
          ref={handleRef}
          data-drag-handle={task.id}
          tabIndex={0}
          aria-label={`任务「${task.title}」排序手柄，按空格或回车抓取，按上下方向键移动，再次按空格或回车放下`}
          title="按住拖拽排序，或按空格/回车抓取后按上下方向键调整顺序"
          className="w-6 h-6 flex items-center justify-center rounded text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 transition focus:outline-none focus-visible:ring-1 focus-visible:ring-emerald-500 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus:opacity-100 cursor-grab disabled:opacity-20"
          disabled={disabled}
        >
          <GripVertical className="w-3.5 h-3.5" />
        </button>
      </div>
    </li>
  );
}

function TaskOverlayPreview({ task, todayStr }: { task: Task; todayStr: string }) {
  const isDone = task.status === TaskStatus.TaskStatusDone;
  const dueBadge = renderDueBadge(task, todayStr);
  return (
    <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl border border-emerald-500/60 bg-white dark:bg-stone-900 shadow-2xl select-none cursor-grabbing">
      <div className="p-0.5 rounded shrink-0">
        {isDone ? (
          <CheckCircle2 className="w-4 h-4 text-emerald-600" />
        ) : (
          <Circle className="w-4 h-4 text-stone-400" />
        )}
      </div>
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
      <div className="w-6 h-6 flex items-center justify-center shrink-0 text-emerald-600 dark:text-emerald-400">
        <GripVertical className="w-3.5 h-3.5" />
      </div>
    </div>
  );
}

export function TodayPlanList({
  taskIds,
  taskMap,
  isToday,
  todayStr,
  selectedDate,
  openTaskId,
  saving,
  onOpenTask,
  onToggleStatus,
  onRemoveTask,
  onReorder,
}: TodayPlanListProps) {
  const [localTaskIds, setLocalTaskIds] = useState<string[]>(taskIds);
  const justDraggedRef = useRef(false);

  useEffect(() => {
    setLocalTaskIds(taskIds);
  }, [taskIds, selectedDate]);

  const validPlanIds = useMemo(
    () => localTaskIds.filter((id) => taskMap.has(id)),
    [localTaskIds, taskMap]
  );

  const planItems = useMemo(
    () => localTaskIds.map((id) => ({ id, task: taskMap.get(id) ?? null })),
    [localTaskIds, taskMap]
  );

  if (planItems.length === 0) {
    return (
      <p className="text-xs text-stone-400 py-1">
        {isToday ? '今天还没有安排任务。' : '该日期无计划安排。'}输入标题添加，或从已有任务中选择。
      </p>
    );
  }

  const handleDragStart = () => {
    justDraggedRef.current = true;
  };

  const handleDragEnd = async (event: any) => {
    setTimeout(() => {
      justDraggedRef.current = false;
    }, 150);

    if (event.canceled) return;
    const { operation } = event;
    if (!operation?.target) return;

    const sourceId = String(operation.source?.id);
    const targetId = String(operation.target?.id);
    if (!sourceId || !targetId || sourceId === targetId) return;

    const nextIds = move(localTaskIds, event) as string[];
    if (nextIds.join(',') === localTaskIds.join(',')) return;

    const prevIds = localTaskIds;
    setLocalTaskIds(nextIds);
    const ok = await onReorder(nextIds);
    if (!ok) {
      setLocalTaskIds(prevIds);
    }
  };

  return (
    <DragDropProvider onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
      <ul className="divide-y divide-stone-200/70 dark:divide-stone-800 rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 relative">
        {planItems.map(({ id, task }, index) => {
          if (!task) {
            return (
              <li
                key={id}
                className="flex items-center justify-between gap-3 px-3 py-2.5 text-xs bg-rose-50/40 dark:bg-rose-950/20"
              >
                <div className="flex items-center gap-2 text-rose-700 dark:text-rose-300 min-w-0">
                  <AlertCircle className="w-4 h-4 shrink-0" />
                  <span className="font-mono text-[11px] truncate">[已删除任务: {id}]</span>
                </div>
                <button
                  type="button"
                  onClick={() => void onRemoveTask(id)}
                  disabled={saving}
                  className="px-2 py-0.5 rounded text-rose-700 dark:text-rose-300 hover:bg-rose-100 dark:hover:bg-rose-900/40 font-medium shrink-0"
                  title="只清除计划中的失效引用"
                >
                  清除占位
                </button>
              </li>
            );
          }

          return (
            <SortableTaskItem
              key={task.id}
              task={task}
              index={index}
              todayStr={todayStr}
              isSelected={task.id === openTaskId}
              disabled={saving || validPlanIds.length <= 1}
              justDraggedRef={justDraggedRef}
              onOpenTask={onOpenTask}
              onToggleStatus={onToggleStatus}
            />
          );
        })}
      </ul>

      <DragOverlay dropAnimation={{ duration: 150, easing: 'cubic-bezier(0.2, 0, 0, 1)' }}>
        {(source) => {
          const task = taskMap.get(String(source.id));
          if (!task) return null;
          return <TaskOverlayPreview task={task} todayStr={todayStr} />;
        }}
      </DragOverlay>
    </DragDropProvider>
  );
}
