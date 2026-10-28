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
      return timeA - timeB;
    }
    return a.id.localeCompare(b.id);
  });
}

/**
 * 将可选任务区分为「未完成」与「已完成」两块，并按时间正向排序（由早到晚）。
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

/** Inline Today suggestions: show a few unfinished tasks on focus; completed ones only when searching. */
export function getInlineTaskCandidates(
  tasks: Task[],
  dayPlanTaskIds: string[],
  titleQuery: string
): Pick<TaskPickerSections, 'uncompletedTasks' | 'completedTasks'> {
  const sections = splitAndSortTasksForPicker(tasks, dayPlanTaskIds, titleQuery);
  return {
    uncompletedTasks: sections.uncompletedTasks.slice(0, 5),
    completedTasks: titleQuery.trim() ? sections.completedTasks.slice(0, 5) : [],
  };
}
