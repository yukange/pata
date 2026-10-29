import type { Task } from '../bindings/pata/internal/storage/markdown/models.js';

export interface TaskPickerSections {
  uncompletedTasks: Task[];
  completedTasks: Task[];
  totalAvailableCount: number;
}

export function parseTimestamp(isoString?: string | null): number {
  if (!isoString) return 0;
  const time = new Date(isoString).getTime();
  return isNaN(time) ? 0 : time;
}

export function sortTasksChronologically(tasks: Task[]): Task[] {
  return [...tasks].sort((a, b) => {
    const timeA = parseTimestamp(a.created_at);
    const timeB = parseTimestamp(b.created_at);
    if (timeA !== timeB) {
      return timeB - timeA;
    }
    return a.id.localeCompare(b.id);
  });
}

/**
 * 将可选任务区分为「未完成」与「已完成」两块，并按时间倒序排序（由新到旧 / 最新创建在前）。
 * 过滤掉当前已在日计划中的任务，并支持标题和标签搜索。
 */
export function splitAndSortTasksForPicker(
  tasks: Task[],
  dayPlanTaskIds: string[],
  searchQuery: string
): TaskPickerSections {
  const currentSet = new Set(dayPlanTaskIds);
  const q = searchQuery.trim().toLowerCase();

  const uncompleted: Task[] = [];
  const completed: Task[] = [];

  for (const t of tasks) {
    if (currentSet.has(t.id)) continue;
    if (q) {
      const matchTitle = t.title.toLowerCase().includes(q);
      const matchTags = (t.tags ?? []).some((tag) => tag.toLowerCase().includes(q));
      if (!matchTitle && !matchTags) continue;
    }

    if (t.status === 'done') {
      completed.push(t);
    } else {
      uncompleted.push(t);
    }
  }

  return {
    uncompletedTasks: sortTasksChronologically(uncompleted),
    completedTasks: sortTasksChronologically(completed),
    totalAvailableCount: uncompleted.length + completed.length,
  };
}

export interface InlineTaskCandidates {
  uncompletedTasks: Task[];
  completedTasks: Task[];
  searchResults: Task[];
}

/** Inline Today suggestions: show uncompleted/completed in tabs on focus; unified results when searching. */
export function getInlineTaskCandidates(
  tasks: Task[],
  dayPlanTaskIds: string[],
  titleQuery: string
): InlineTaskCandidates {
  const sections = splitAndSortTasksForPicker(tasks, dayPlanTaskIds, titleQuery);
  const isSearch = Boolean(titleQuery.trim());
  return {
    uncompletedTasks: sections.uncompletedTasks,
    completedTasks: sections.completedTasks,
    searchResults: isSearch
      ? [...sections.uncompletedTasks, ...sections.completedTasks]
      : [],
  };
}

/** Footer guide for inline suggestions depending on selection and input presence. */
export function getInlineTaskFooterHint(hasActiveSelection: boolean, hasInput: boolean): string {
  if (hasInput) {
    return hasActiveSelection ? '↵ 加入已有任务 · ↑↓ 移动' : '↵ 创建新任务 · ↑↓ 选择';
  }
  return '↵ 加入今日 · ↑↓ 移动 · ←→ 分类';
}
