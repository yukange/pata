import { useEffect, useRef, useState, useImperativeHandle, forwardRef } from 'react';
import { parseTranscript, findSentenceAtTime } from './audioTranscript';
import { Clock, Loader2 } from 'lucide-react';

export interface TranscriptViewerRef {
  scrollToTime: (timeMs: number) => void;
}

interface TranscriptViewerProps {
  body: string;
  isTranscribing: boolean;
  onJumpToTime: (timeMs: number) => void;
}

export const TranscriptViewer = forwardRef<TranscriptViewerRef, TranscriptViewerProps>(
  function TranscriptViewer({ body, isTranscribing, onJumpToTime }, ref) {
    const blocks = parseTranscript(body);
    const [highlightedId, setHighlightedId] = useState<string | null>(null);
    const blockRefs = useRef<Map<string, HTMLDivElement>>(new Map());
    const highlightTimeoutRef = useRef<number | null>(null);

    useImperativeHandle(ref, () => ({
      scrollToTime(timeMs: number) {
        if (blocks.length === 0) return;
        const targetIdx = findSentenceAtTime(blocks, timeMs);
        if (targetIdx >= 0 && targetIdx < blocks.length) {
          const targetBlock = blocks[targetIdx];
          const el = blockRefs.current.get(targetBlock.id);
          if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            setHighlightedId(targetBlock.id);
            if (highlightTimeoutRef.current) {
              clearTimeout(highlightTimeoutRef.current);
            }
            highlightTimeoutRef.current = setTimeout(() => {
              setHighlightedId(null);
            }, 1800);
          }
        }
      },
    }));

    useEffect(() => {
      return () => {
        if (highlightTimeoutRef.current) {
          clearTimeout(highlightTimeoutRef.current);
        }
      };
    }, []);

    if (blocks.length === 0) {
      return (
        <div className="py-20 text-center rounded-xl border border-dashed border-stone-200 dark:border-stone-800 text-stone-400 space-y-2 select-none">
          {isTranscribing ? (
            <div className="flex flex-col items-center space-y-2">
              <Loader2 className="w-6 h-6 animate-spin text-emerald-600 dark:text-emerald-400" />
              <div className="text-xs font-medium text-stone-600 dark:text-stone-300">
                正在后台转写逐字稿...
              </div>
              <div className="text-[11px] text-stone-400 max-w-sm">
                您可以继续切换到其他笔记或任务，转写完成后会自动填充于此
              </div>
            </div>
          ) : (
            <div className="flex flex-col items-center space-y-1">
              <Clock className="w-6 h-6 text-stone-300 dark:text-stone-700" />
              <div className="text-xs font-medium text-stone-600 dark:text-stone-300">
                暂无逐字稿内容
              </div>
              <div className="text-[11px] text-stone-400">
                点击上方播放器菜单中的「开始转写」即可提取音频文本
              </div>
            </div>
          )}
        </div>
      );
    }

    return (
      <div className="space-y-4 py-2 select-text">
        {blocks.map((b) => {
          const isHighlighted = highlightedId === b.id;

          return (
            <div
              key={b.id}
              ref={(el) => {
                if (el) blockRefs.current.set(b.id, el);
                else blockRefs.current.delete(b.id);
              }}
              className={`p-3 rounded-xl transition-all duration-500 border ${
                isHighlighted
                  ? 'bg-emerald-50/90 dark:bg-emerald-950/40 border-emerald-500/40 shadow-xs ring-1 ring-emerald-500/20'
                  : 'bg-transparent border-transparent hover:bg-stone-50/60 dark:hover:bg-stone-900/40'
              }`}
            >
              {/* Sentence Header: Clickable Timestamp + Speaker attribution (selectable & copyable) */}
              {(b.timestampStr || b.speaker) && (
                <div className="flex items-center space-x-2 pb-1.5">
                  {b.timestampStr && (
                    <button
                      type="button"
                      onClick={() => b.timestampMs !== undefined && onJumpToTime(b.timestampMs)}
                      className="font-mono text-xs px-1.5 py-0.5 rounded bg-emerald-50 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400 hover:bg-emerald-100 dark:hover:bg-emerald-900/60 border border-emerald-200/80 dark:border-emerald-800/60 transition cursor-pointer"
                      title="点击跳到该时间播放"
                    >
                      [{b.timestampStr}]
                    </button>
                  )}
                  {b.speaker && (
                    <span className="text-xs font-semibold text-stone-700 dark:text-stone-300">
                      {b.speaker}
                    </span>
                  )}
                </div>
              )}

              {/* Read-only sentence body: selectable, copyable, searchable */}
              <div className="text-sm text-stone-800 dark:text-stone-200 leading-relaxed font-sans whitespace-pre-wrap break-words">
                {b.text}
              </div>
            </div>
          );
        })}
      </div>
    );
  }
);
