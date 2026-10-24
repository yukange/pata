export interface TaskActivity {
  id: string;
  at: string;
  by?: string;
  tags?: string[] | null;
  note_refs?: { [_ in string]?: string } | null;
  body: string;
  task_id?: string;
}

export interface TaskStatusEvent {
  action: string;
  at: string;
  by?: string;
}

export interface TaskLike {
  id: string;
  title?: string;
  status: string;
  created_at?: string;
  created_by?: string;
  completed_at?: string | null;
  status_events?: TaskStatusEvent[] | null;
}

export interface ActivityTimelineItem {
  kind: 'activity';
  key: string;
  at: string;
  activity: TaskActivity;
}

export interface StatusEventTimelineItem {
  kind: 'status_event';
  key: string;
  at: string;
  action: string;
  by?: string;
}

export type TaskTimelineItem = ActivityTimelineItem | StatusEventTimelineItem;

export function formatFullLocalTimestamp(isoString?: string | null): string {
  if (!isoString) return '';
  try {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;
    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  } catch {
    return isoString;
  }
}

export function formatActivityTimestamp(isoString: string, now: Date = new Date()): string {
  if (!isoString) return '';
  try {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;

    const pad = (n: number) => n.toString().padStart(2, '0');
    const hours = pad(d.getHours());
    const minutes = pad(d.getMinutes());

    const isToday =
      d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() &&
      d.getDate() === now.getDate();

    if (isToday) {
      return `${hours}:${minutes}`;
    }

    const year = d.getFullYear();
    const month = pad(d.getMonth() + 1);
    const day = pad(d.getDate());
    if (year === now.getFullYear()) {
      return `${month}-${day} ${hours}:${minutes}`;
    }
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  } catch {
    return isoString;
  }
}

/**
 * 混排任务的创建、完成/重开事件与普通 Activity。
 * 按时间正向排序（由早到晚，最早的在最前，最新的在末尾），同时间戳保持稳定排序。
 */
export function buildTaskTimelineItems(
  task: TaskLike | null,
  activities: TaskActivity[]
): TaskTimelineItem[] {
  const items: TaskTimelineItem[] = [];

  if (task?.created_at) {
    items.push({
      kind: 'status_event', key: `0-created-${task.id}`,
      at: task.created_at, action: 'creation', by: task.created_by,
    });
  }

  for (const act of activities) {
    if (act && act.at) {
      items.push({
        kind: 'activity',
        key: `2-activity-${act.id}`,
        at: act.at,
        activity: act,
      });
    }
  }

  const rawEvents: TaskStatusEvent[] = task?.status_events ?? [];
  const statusEvents: TaskStatusEvent[] = [...rawEvents];

  // completed_at 没有对应历史事件时只读兜底，不补写历史。
  const completedAt = task?.completed_at;
  if (
    task?.status === 'done' &&
    completedAt &&
    !statusEvents.some((e) => e.action === 'completed' && new Date(e.at).getTime() === new Date(completedAt).getTime())
  ) {
    statusEvents.push({
      action: 'completed',
      at: completedAt,
    });
  }

  statusEvents.forEach((ev, idx) => {
    if (ev?.at) {
      items.push({
        kind: 'status_event',
        key: `1-status-${task?.id}-${String(idx).padStart(9, '0')}`,
        at: ev.at,
        action: ev.action,
        by: ev.by,
      });
    }
  });

  return items.sort((a, b) => {
    const tA = new Date(a.at).getTime();
    const tB = new Date(b.at).getTime();
    const validA = !isNaN(tA);
    const validB = !isNaN(tB);
    if (validA && validB && tA !== tB) {
      return tA - tB; // ascending (chronological: oldest first, newest last)
    }
    if (validA && !validB) return -1;
    if (!validA && validB) return 1;
    if (!validA && !validB && a.at !== b.at) {
      return a.at.localeCompare(b.at);
    }
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
  });
}
