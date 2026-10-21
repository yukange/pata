import { Send, RefreshCw, AlertCircle, X } from 'lucide-react';
import type { ReactNode } from 'react';
import { NoteRefTextarea, NoteRefMap, NoteRef } from './noteRefs';
import { isActivitySubmitShortcut } from './activityUtils';

export { isActivitySubmitShortcut };

export interface ActivityComposerProps {
  value: string;
  onChange: (value: string) => void;
  refs: NoteRefMap;
  onRefsChange: (refs: NoteRefMap) => void;
  notes: NoteRef[];
  placeholder?: string;
  minRows?: number;
  submitting?: boolean;
  submitLabel?: string;
  onSubmit: () => void;
  error?: string | null;
  onClearError?: () => void;
  helperText?: ReactNode;
  ariaLabel?: string;
  className?: string;
}

/**
 * 统一的一体式 Activity 输入组件。
 * 输入框与发送按钮位于同一圆角卡片容器中，发送按钮在右下角。
 * 共享边框、焦点光圈、发送状态、错误反馈与快捷键 (⌘+Enter)。
 */
export function ActivityComposer({
  value,
  onChange,
  refs,
  onRefsChange,
  notes,
  placeholder = '记录进展… (输入 [[ 引用笔记)',
  minRows = 2,
  submitting = false,
  submitLabel = '发送',
  onSubmit,
  error,
  onClearError,
  helperText,
  ariaLabel = '记录输入',
  className = '',
}: ActivityComposerProps) {
  return (
    <div className={`space-y-1.5 ${className}`.trim()}>
      <div className="rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 p-2.5 focus-within:border-emerald-600/80 dark:focus-within:border-emerald-500/80 focus-within:ring-2 focus-within:ring-emerald-500/20 transition shadow-2xs">
        <NoteRefTextarea
          value={value}
          onChange={onChange}
          refs={refs}
          onRefsChange={onRefsChange}
          notes={notes}
          aria-label={ariaLabel}
          placeholder={placeholder}
          rows={minRows}
          disabled={submitting}
          onKeyDown={(e) => {
            if (
              isActivitySubmitShortcut({
                key: e.key,
                metaKey: e.metaKey,
                ctrlKey: e.ctrlKey,
                isComposing: e.nativeEvent.isComposing,
                keyCode: e.keyCode,
              }) &&
              !submitting &&
              value.trim()
            ) {
              e.preventDefault();
              onSubmit();
            }
          }}
          className="w-full text-xs text-stone-900 dark:text-stone-100 placeholder-stone-400 bg-transparent resize-none border-0 outline-none focus:outline-none focus:ring-0 leading-relaxed"
        />
        <div className="flex items-center justify-end pt-1.5">
          <button
            type="button"
            onMouseDown={(e) => e.preventDefault()}
            onClick={onSubmit}
            disabled={submitting || !value.trim()}
            className="inline-flex items-center space-x-1.5 px-3 py-1.5 rounded-lg bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition shadow-2xs disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
            title="发送 (⌘+Enter)"
          >
            {submitting ? (
              <RefreshCw className="w-3.5 h-3.5 animate-spin shrink-0" />
            ) : (
              <Send className="w-3.5 h-3.5 shrink-0" />
            )}
            <span>{submitting ? `${submitLabel}中` : submitLabel}</span>
            {!submitting && (
              <span className="text-[11px] font-mono opacity-60 select-none">⌘↵</span>
            )}
          </button>
        </div>
      </div>

      {helperText && (
        <div className="text-[11px] text-stone-400 px-1">{helperText}</div>
      )}

      {error && (
        <div className="p-2 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-start space-x-2">
          <AlertCircle className="w-3.5 h-3.5 text-rose-600 shrink-0 mt-0.5" />
          <div className="space-y-0.5 flex-1 min-w-0">
            <div className="font-semibold text-[11px]">记录保存失败</div>
            <div className="font-mono text-[10px] break-all">{error}</div>
          </div>
          {onClearError && (
            <button
              type="button"
              onClick={onClearError}
              className="text-stone-400 hover:text-stone-600 dark:hover:text-stone-200 transition cursor-pointer"
              title="关闭提示"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      )}
    </div>
  );
}
