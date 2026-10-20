import React, { useState, useEffect, useMemo, useRef } from 'react';
import { CheckCircle2, Circle, GripVertical, AlertCircle } from 'lucide-react';
import { Task, TaskStatus } from '../bindings/pata/internal/storage/markdown/models';
import {
  reorderTaskIds,
  computeSnapOffset,
  computeKeyboardReorder,
  evaluateDragSession,
} from './todayReorder';

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
  const isDraggingRef = useRef(false);
  const isSnappingRef = useRef(false);

  // 当外部计划任务 ID 发生改变且当前不在拖拽/吸附时，同步本地状态
  useEffect(() => {
    if (!isDraggingRef.current && !isSnappingRef.current) {
      setLocalTaskIds(taskIds);
    }
  }, [taskIds]);

  const containerRef = useRef<HTMLUListElement>(null);
  const justDraggedRef = useRef(false);
  const activeSessionCleanupRef = useRef<(() => void) | null>(null);

  // 切换日期或组件卸载时清理未完成的拖拽会话
  useEffect(() => {
    return () => {
      activeSessionCleanupRef.current?.();
    };
  }, [selectedDate]);

  const validPlanIds = useMemo(
    () => localTaskIds.filter((id) => taskMap.has(id)),
    [localTaskIds, taskMap]
  );

  const planItems = useMemo(
    () => localTaskIds.map((id) => ({ id, task: taskMap.get(id) ?? null })),
    [localTaskIds, taskMap]
  );

  const handlePointerDown = (e: React.PointerEvent, taskId: string) => {
    if (e.button !== 0 || validPlanIds.length <= 1 || saving || isSnappingRef.current) return;
    e.preventDefault();
    e.stopPropagation();

    const container = containerRef.current;
    if (!container) return;

    const initialIndex = validPlanIds.indexOf(taskId);
    if (initialIndex === -1) return;

    const itemElements = Array.from(container.querySelectorAll<HTMLElement>('[data-plan-task-id]'));
    if (itemElements.length <= 1 || initialIndex >= itemElements.length) return;

    const draggedEl = itemElements[initialIndex];
    if (!draggedEl) return;

    const scrollParent = container.closest('.overflow-y-auto') as HTMLElement | null;
    const initialScrollTop = scrollParent?.scrollTop ?? 0;

    // 一次性测量几何数据，拖拽全周期绝不反复调用 getBoundingClientRect，杜绝布局回流
    const containerRect = container.getBoundingClientRect();
    const scrollParentRect = scrollParent?.getBoundingClientRect() ?? null;
    const itemRects = itemElements.map((el) => {
      const r = el.getBoundingClientRect();
      return { top: r.top, bottom: r.bottom, height: r.height };
    });

    const startX = e.clientX;
    const startY = e.clientY;
    let currentPointerX = startX;
    let currentPointerY = startY;

    let draggingActive = false;
    let currentTargetIndex = initialIndex;
    let currentIsOver = true;
    let autoScrollSpeed = 0;
    let rafId = 0;

    const applyActiveStyles = () => {
      draggingActive = true;
      isDraggingRef.current = true;
      document.body.style.cursor = 'grabbing';
      document.body.style.userSelect = 'none';

      // 拖拽项浮起高亮：绝对跟手、提升层级与阴影
      draggedEl.style.position = 'relative';
      draggedEl.style.zIndex = '30';
      draggedEl.style.transition = 'none';
      draggedEl.classList.add(
        'shadow-xl',
        'bg-white',
        'dark:bg-stone-900',
        'ring-2',
        'ring-emerald-500/70',
        'rounded-xl'
      );

      // 其余兄弟项添加平滑让位过渡
      itemElements.forEach((el, idx) => {
        if (idx !== initialIndex) {
          el.style.transition = 'transform 160ms cubic-bezier(0.2, 0, 0, 1)';
        }
      });
    };

    const cleanupStyles = () => {
      isDraggingRef.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';

      itemElements.forEach((el) => {
        el.style.transform = '';
        el.style.transition = '';
        el.style.zIndex = '';
        el.style.position = '';
        el.style.opacity = '';
        el.classList.remove(
          'shadow-xl',
          'bg-white',
          'dark:bg-stone-900',
          'ring-2',
          'ring-emerald-500/70',
          'ring-amber-500/70',
          'opacity-40',
          'rounded-xl'
        );
      });
    };

    // 统一每帧渲染函数：自动滚动、连续跟手位移与兄弟项平滑让位紧密联动
    const updateFrame = () => {
      if (!isDraggingRef.current && !draggingActive) return;

      // 1. 若有滚动速度，持续平滑滚动
      if (scrollParent && autoScrollSpeed !== 0) {
        scrollParent.scrollTop += autoScrollSpeed;
      }

      const currentScrollTop = scrollParent?.scrollTop ?? 0;
      const snapshot = evaluateDragSession(
        {
          taskIds: validPlanIds,
          initialIndex,
          itemRects,
          containerRect,
          initialScrollTop,
          startY,
        },
        {
          pointerX: currentPointerX,
          pointerY: currentPointerY,
          scrollTop: currentScrollTop,
        }
      );

      // 2. 连续跟手：更新拖动项自身的 translateY，物理无阶跃
      draggedEl.style.transform = `translateY(${snapshot.draggedTranslateY}px)`;

      // 3. 超出有效区域时切换视觉反馈
      if (snapshot.isOver !== currentIsOver) {
        currentIsOver = snapshot.isOver;
        if (!snapshot.isOver) {
          draggedEl.classList.remove('ring-emerald-500/70');
          draggedEl.classList.add('ring-amber-500/70', 'opacity-40');
        } else {
          draggedEl.classList.remove('ring-amber-500/70', 'opacity-40');
          draggedEl.classList.add('ring-emerald-500/70');
        }
      }

      // 4. 目标索引变化或进出有效区时，更新兄弟项让位变换
      if (snapshot.targetIndex !== currentTargetIndex || !snapshot.isOver) {
        currentTargetIndex = snapshot.targetIndex;
        itemElements.forEach((el, idx) => {
          if (idx === initialIndex) return;
          const disp = snapshot.siblingDisplacements[idx] ?? 0;
          el.style.transform = disp === 0 ? '' : `translateY(${disp}px)`;
        });
      }

      // 5. 自动滚动未停止时保持 RAF 循环，确保指针静止时落点持续随滚动刷新
      if (autoScrollSpeed !== 0) {
        rafId = requestAnimationFrame(updateFrame);
      } else {
        rafId = 0;
      }
    };

    const onPointerMove = (moveEvent: PointerEvent) => {
      currentPointerX = moveEvent.clientX;
      currentPointerY = moveEvent.clientY;

      if (!draggingActive) {
        if (Math.hypot(moveEvent.clientX - startX, moveEvent.clientY - startY) > 3) {
          applyActiveStyles();
        } else {
          return;
        }
      }

      // 边缘自动滚动检测与自适应速度计算
      if (scrollParent && scrollParentRect) {
        const edgeDistance = 36;
        if (moveEvent.clientY < scrollParentRect.top + edgeDistance) {
          const depth = Math.max(0, scrollParentRect.top + edgeDistance - moveEvent.clientY);
          autoScrollSpeed = -Math.round(2 + Math.min(1, depth / edgeDistance) * 7);
        } else if (moveEvent.clientY > scrollParentRect.bottom - edgeDistance) {
          const depth = Math.max(0, moveEvent.clientY - (scrollParentRect.bottom - edgeDistance));
          autoScrollSpeed = Math.round(2 + Math.min(1, depth / edgeDistance) * 7);
        } else {
          autoScrollSpeed = 0;
        }
      }

      if (!rafId) {
        rafId = requestAnimationFrame(updateFrame);
      }
    };

    const onScroll = () => {
      if (draggingActive && !rafId) {
        rafId = requestAnimationFrame(updateFrame);
      }
    };

    const stopListeners = () => {
      if (rafId) {
        cancelAnimationFrame(rafId);
        rafId = 0;
      }
      autoScrollSpeed = 0;
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('pointerup', onPointerUp);
      window.removeEventListener('pointercancel', cancelDrag);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('blur', cancelDrag);
      scrollParent?.removeEventListener('scroll', onScroll);
      activeSessionCleanupRef.current = null;
    };

    const cancelDrag = () => {
      stopListeners();
      if (draggingActive) {
        draggedEl.style.transition = 'transform 140ms cubic-bezier(0.2, 0, 0, 1)';
        draggedEl.style.transform = 'translateY(0px)';
        itemElements.forEach((el, idx) => {
          if (idx !== initialIndex) el.style.transform = '';
        });
        setTimeout(() => {
          cleanupStyles();
        }, 140);
      } else {
        cleanupStyles();
      }
    };

    const onPointerUp = () => {
      stopListeners();
      if (!draggingActive) {
        cleanupStyles();
        return;
      }

      justDraggedRef.current = true;
      setTimeout(() => {
        justDraggedRef.current = false;
      }, 150);

      // 无效落点或未改变位置：吸附回原位，不触发持久化
      if (!currentIsOver || currentTargetIndex === initialIndex) {
        draggedEl.style.transition = 'transform 140ms cubic-bezier(0.2, 0, 0, 1)';
        draggedEl.style.transform = 'translateY(0px)';
        draggedEl.classList.remove('opacity-40', 'ring-amber-500/70');
        draggedEl.classList.add('ring-emerald-500/70');
        itemElements.forEach((el, idx) => {
          if (idx !== initialIndex) el.style.transform = '';
        });
        setTimeout(() => {
          cleanupStyles();
        }, 140);
        return;
      }

      // 有效落点：吸附到目标位置，动画结束后无缝切换 DOM 并乐观提交
      isSnappingRef.current = true;
      const targetShift = computeSnapOffset(initialIndex, currentTargetIndex, itemRects);
      draggedEl.style.transition = 'transform 120ms cubic-bezier(0.2, 0, 0, 1)';
      draggedEl.style.transform = `translateY(${targetShift}px)`;

      const nextIds = reorderTaskIds(validPlanIds, initialIndex, currentTargetIndex);

      setTimeout(async () => {
        cleanupStyles();
        setLocalTaskIds(nextIds);
        isSnappingRef.current = false;
        const ok = await onReorder(nextIds);
        if (!ok) {
          // 保存失败回滚
          setLocalTaskIds(validPlanIds);
        }
      }, 120);
    };

    const onKeyDown = (ke: KeyboardEvent) => {
      if (ke.key === 'Escape') {
        ke.preventDefault();
        cancelDrag();
      }
    };

    activeSessionCleanupRef.current = () => {
      stopListeners();
      cleanupStyles();
      isSnappingRef.current = false;
    };

    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointercancel', cancelDrag);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('blur', cancelDrag);
    scrollParent?.addEventListener('scroll', onScroll, { passive: true });
  };

  const handleHandleKeyDown = async (e: React.KeyboardEvent, taskId: string) => {
    if (saving || validPlanIds.length <= 1 || isSnappingRef.current) return;
    if (['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(e.key)) {
      e.preventDefault();
      e.stopPropagation();
      const res = computeKeyboardReorder(validPlanIds, taskId, e.key);
      if (res) {
        const prev = localTaskIds;
        setLocalTaskIds(res.nextIds);
        const ok = await onReorder(res.nextIds);
        if (!ok) {
          setLocalTaskIds(prev);
        } else {
          requestAnimationFrame(() => {
            const handleEl = containerRef.current?.querySelector<HTMLButtonElement>(`[data-drag-handle="${taskId}"]`);
            handleEl?.focus();
          });
        }
      }
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
    }
  };

  if (planItems.length === 0) {
    return (
      <p className="text-xs text-stone-400 py-1">
        {isToday ? '今天还没有安排任务。' : '该日期无计划安排。'}输入标题添加，或从已有任务中选择。
      </p>
    );
  }

  return (
    <ul
      ref={containerRef}
      className="divide-y divide-stone-200/70 dark:divide-stone-800 rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 relative"
    >
      {planItems.map(({ id, task }) => {
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

        const isDone = task.status === TaskStatus.TaskStatusDone;
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
            className={`group flex items-center gap-3 px-3 py-2.5 cursor-pointer first:rounded-t-xl last:rounded-b-xl hover:bg-stone-50 dark:hover:bg-stone-900/60 focus:outline-none focus:ring-0 transition-colors ${
              task.id === openTaskId ? 'bg-stone-100/80 dark:bg-stone-800/50' : ''
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
                data-drag-handle={task.id}
                tabIndex={0}
                aria-label={`任务「${task.title}」排序手柄，按上下方向键调整顺序`}
                title="按住拖拽排序，或按上下方向键调整顺序"
                className="w-6 h-6 flex items-center justify-center rounded text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 transition focus:outline-none focus-visible:ring-1 focus-visible:ring-emerald-500 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus:opacity-100 cursor-grab disabled:opacity-20"
                disabled={saving || validPlanIds.length <= 1}
                onPointerDown={(e) => handlePointerDown(e, task.id)}
                onKeyDown={(e) => void handleHandleKeyDown(e, task.id)}
              >
                <GripVertical className="w-3.5 h-3.5" />
              </button>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
