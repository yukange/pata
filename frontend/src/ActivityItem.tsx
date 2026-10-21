import {
  CheckCircle2,
  Undo2,
  Pencil,
  AlertCircle,
} from 'lucide-react';
import { NoteRefText, NoteRefTextarea, NoteRefMap, NoteRef } from './noteRefs';
import { formatStatusAction } from './activityUtils';

export { formatStatusAction };

export interface ActivityTaskContext {
  taskId: string;
  taskTitle?: string;
  taskExists?: boolean;
  onOpenTask: (taskId: string) => void;
}

export interface ActivityItemProps {
  timeStr: string;
  fullTimeStr?: string;
  taskContext?: ActivityTaskContext;
  activity?: {
    id: string;
    body: string;
    tags?: string[] | null;
    note_refs?: NoteRefMap | null;
  };
  statusEvent?: {
    action: string; // 'completed' | 'reopened' | 'completion' | 'reopen'
  };
  notes: NoteRef[];
  onOpenNote?: (noteId: string) => void;
  // Inline editing props
  isEditing?: boolean;
  editBody?: string;
  editRefs?: NoteRefMap;
  editSaving?: boolean;
  editError?: string | null;
  onStartEdit?: () => void;
  onEditBodyChange?: (body: string) => void;
  onEditRefsChange?: (refs: NoteRefMap) => void;
  onSaveEdit?: () => void;
  onCancelEdit?: () => void;
  className?: string;
}

/**
 * 统一的 Activity 单项展示与原地编辑组件。
 * 遵循 013 统一规范：
 * 1. 时间位于正文上方；
 * 2. Today 在时间右侧展示同字号任务标题链接；Task 详情不重复任务标题；
 * 3. 悬停出现编辑入口，原地编辑，保存/取消就地呈现；
 * 4. 系统事件（完成/重新打开）保持单行只读。
 */
export function ActivityItem({
  timeStr,
  fullTimeStr,
  taskContext,
  activity,
  statusEvent,
  notes,
  onOpenNote,
  isEditing = false,
  editBody = '',
  editRefs = {},
  editSaving = false,
  editError,
  onStartEdit,
  onEditBodyChange,
  onEditRefsChange,
  onSaveEdit,
  onCancelEdit,
  className = '',
}: ActivityItemProps) {
  // 1. 系统状态事件（完成 / 重新打开）
  if (statusEvent) {
    const isCompleted =
      statusEvent.action === 'completed' || statusEvent.action === 'completion';
    return (
      <div
        className={`flex items-center gap-2 py-1.5 text-xs text-stone-600 dark:text-stone-300 ${className}`.trim()}
      >
        <span
          className="font-mono text-[11px] text-stone-400 dark:text-stone-500 shrink-0 select-none"
          title={fullTimeStr}
        >
          {timeStr}
        </span>
        {isCompleted ? (
          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400 shrink-0" />
        ) : (
          <Undo2 className="w-3.5 h-3.5 text-blue-600 dark:text-blue-400 shrink-0" />
        )}
        <span className="min-w-0">
          <span>{formatStatusAction(statusEvent.action, Boolean(taskContext))}</span>
          {taskContext && (
            taskContext.taskExists !== false ? (
              <button
                type="button"
                // 避免点击任务链接时先触发右栏输入框 blur 保存，任务切换统一由 App Shell 确认。
                onMouseDown={(e) => e.preventDefault()}
                onClick={(e) => {
                  e.stopPropagation();
                  taskContext.onOpenTask(taskContext.taskId);
                }}
                className="text-xs font-medium text-emerald-700 dark:text-emerald-400 hover:underline cursor-pointer align-baseline break-words text-left"
                title="在右侧打开任务详情"
              >
                {taskContext.taskTitle || taskContext.taskId}
              </button>
            ) : (
              <span className="text-xs font-mono text-stone-400 dark:text-stone-500 break-words">
                {taskContext.taskTitle || taskContext.taskId}
                <span className="ml-1 text-[10px] text-rose-500/80">(任务已删除)</span>
              </span>
            )
          )}
        </span>
      </div>
    );
  }

  // 2. 人工 Activity 记录
  if (!activity) return null;

  return (
    <div className={`group space-y-1 py-2 text-xs ${className}`.trim()}>
      {/* 顶部元信息栏：时间在上，Today 的任务链接在时间右侧（同正文字号），编辑入口悬停出现 */}
      <div className="flex items-start justify-between gap-2 min-w-0">
        <div className="flex items-baseline gap-2 min-w-0 flex-wrap">
          <span
            className="font-mono text-[11px] text-stone-400 dark:text-stone-500 shrink-0 select-none"
            title={fullTimeStr}
          >
            {timeStr}
          </span>

          {taskContext && (
            taskContext.taskExists !== false ? (
              <button
                type="button"
                // 避免触发右栏输入框独立的 blur 保存，防止与切换前保存并发。
                onMouseDown={(e) => e.preventDefault()}
                onClick={(e) => {
                  e.stopPropagation();
                  taskContext.onOpenTask(taskContext.taskId);
                }}
                className="text-xs font-medium text-emerald-700 dark:text-emerald-400 hover:underline cursor-pointer text-left break-words"
                title="在右侧打开任务详情"
              >
                {taskContext.taskTitle || taskContext.taskId}
              </button>
            ) : (
              <span className="text-xs font-mono text-stone-400 dark:text-stone-500">
                {taskContext.taskTitle || taskContext.taskId}
                <span className="ml-1 text-[10px] text-rose-500/80">(任务已删除)</span>
              </span>
            )
          )}
        </div>

        {/* 悬停编辑按钮 */}
        {!isEditing && onStartEdit && (
          <button
            type="button"
            onClick={onStartEdit}
            className="opacity-0 group-hover:opacity-100 focus:opacity-100 p-1 rounded-md text-stone-400 hover:text-stone-600 dark:hover:text-stone-200 transition shrink-0 cursor-pointer"
            title="编辑记录"
            aria-label="编辑记录"
          >
            <Pencil className="w-3.5 h-3.5" />
          </button>
        )}
      </div>

      {/* 正文区域 / 原地编辑区域 */}
      {isEditing ? (
        <div className="space-y-1.5 pt-0.5">
          <NoteRefTextarea
            value={editBody}
            onChange={(val) => onEditBodyChange?.(val)}
            refs={editRefs}
            onRefsChange={(refs) => onEditRefsChange?.(refs)}
            notes={notes}
            aria-label="编辑记录"
            disabled={editSaving}
            onKeyDown={(e) => {
              if (e.nativeEvent.isComposing || e.keyCode === 229) return;
              if (e.key === 'Escape') onCancelEdit?.();
              if ((e.metaKey || e.ctrlKey) && e.key === 'Enter' && editBody.trim()) {
                e.preventDefault();
                onSaveEdit?.();
              }
            }}
            autoFocus
            rows={3}
            className="w-full p-2 text-xs rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-0 focus:border-stone-400 dark:focus:border-stone-600 resize-y leading-relaxed"
          />

          <div className="flex items-center gap-2">
            <button
              type="button"
              onMouseDown={(e) => e.preventDefault()}
              onClick={onSaveEdit}
              disabled={editSaving || !editBody.trim()}
              className="px-2.5 py-1 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium disabled:opacity-40 transition cursor-pointer"
            >
              {editSaving ? '保存中' : '保存'}
            </button>
            <button
              type="button"
              onMouseDown={(e) => e.preventDefault()}
              onClick={onCancelEdit}
              disabled={editSaving}
              className="px-2.5 py-1 rounded-md text-xs text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition cursor-pointer"
            >
              取消
            </button>
          </div>

          {editError && (
            <div className="p-1.5 rounded-md border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-start space-x-1.5">
              <AlertCircle className="w-3.5 h-3.5 text-rose-600 shrink-0 mt-0.5" />
              <div className="font-mono text-[11px] break-all">{editError}</div>
            </div>
          )}
        </div>
      ) : (
        <div className="space-y-1">
          <NoteRefText
            text={activity.body}
            refs={activity.note_refs ?? undefined}
            notes={notes}
            onOpenNote={onOpenNote}
            className="text-xs text-stone-800 dark:text-stone-200 leading-relaxed font-sans whitespace-pre-wrap break-words"
          />

          {activity.tags && activity.tags.length > 0 && (
            <div className="flex flex-wrap gap-1 pt-0.5">
              {activity.tags.map((tag) => (
                <span
                  key={tag}
                  className="inline-flex items-center text-[10px] text-stone-400 font-mono"
                >
                  #{tag}
                </span>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
