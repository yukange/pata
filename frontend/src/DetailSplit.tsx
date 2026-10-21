import { useEffect, useRef, useState } from 'react';
import type { ReactNode, PointerEvent, KeyboardEvent } from 'react';
import {
  DEFAULT_INSPECTOR_WIDTH,
  MIN_INSPECTOR_WIDTH,
  MAX_INSPECTOR_WIDTH,
  clampInspectorWidth,
  maxInspectorWidth,
  parseInspectorWidth,
} from './inspectorWidth';

/** 记录详情打开前的焦点元素，关闭后恢复。 */
export function useDetailOrigin() {
  const origin = useRef<HTMLElement | null>(null);
  return {
    capture() {
      if (!origin.current) origin.current = document.activeElement as HTMLElement | null;
    },
    restore() {
      const el = origin.current;
      origin.current = null;
      requestAnimationFrame(() => el?.isConnected && el.focus());
    },
  };
}

const WIDTH_STORAGE_KEY = 'pata_detail_panel_width';
function loadPanelWidth(): number {
  try {
    return parseInspectorWidth(localStorage.getItem(WIDTH_STORAGE_KEY));
  } catch {
    return DEFAULT_INSPECTOR_WIDTH;
  }
}

/** 主工作区的排版与滚动。详情面板不再由具体页面提供。 */
export function WorkspacePage({ children }: { children: ReactNode }) {
  return (
    <div className="h-full min-h-0 overflow-y-auto p-6">
      <div className="mx-auto max-w-3xl">{children}</div>
    </div>
  );
}

/**
 * App 级中间工作区 + 可选右侧 Inspector。
 * 组件始终位于 Today / Tasks / Notes / Tag 之外；各页面只负责工作区内容。
 */
export function DetailSplit({ panel, children }: { panel: ReactNode | null; children: ReactNode }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const currentWidthRef = useRef(DEFAULT_INSPECTOR_WIDTH);
  const [panelWidth, setPanelWidth] = useState(loadPanelWidth);
  const [containerWidth, setContainerWidth] = useState(0);

  currentWidthRef.current = panelWidth;

  useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const observer = new ResizeObserver(() => {
      setContainerWidth(element.getBoundingClientRect().width);
    });
    observer.observe(element);
    setContainerWidth(element.getBoundingClientRect().width);
    return () => {
      observer.disconnect();
      // 面板在指针捕获期间卸载时，也不能遗留系统 resize 光标。
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };
  }, []);

  useEffect(() => {
    if (!panel) {
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    }
  }, [panel]);

  const maxWidthForWindow = maxInspectorWidth(containerWidth);
  const effectiveWidth = Math.min(panelWidth, maxWidthForWindow);

  const setClampedWidth = (next: number) => {
    const available = containerRef.current?.getBoundingClientRect().width ?? 0;
    const value = clampInspectorWidth(next, available);
    currentWidthRef.current = value;
    setPanelWidth(value);
  };

  const saveWidth = () => {
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
    try {
      localStorage.setItem(WIDTH_STORAGE_KEY, String(currentWidthRef.current));
    } catch {
      // Persisting user preference must not block the resize interaction.
    }
  };

  const handlePointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  };

  const handlePointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.currentTarget.hasPointerCapture(event.pointerId)) return;
    const rect = containerRef.current?.getBoundingClientRect();
    if (rect) setClampedWidth(rect.right - event.clientX);
  };

  const handlePointerUp = (event: PointerEvent<HTMLDivElement>) => {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    saveWidth();
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault();
      setClampedWidth(currentWidthRef.current + (event.key === 'ArrowLeft' ? 16 : -16));
      saveWidth();
    } else if (event.key === 'Home') {
      event.preventDefault();
      setClampedWidth(MIN_INSPECTOR_WIDTH);
      saveWidth();
    } else if (event.key === 'End') {
      event.preventDefault();
      setClampedWidth(MAX_INSPECTOR_WIDTH);
      saveWidth();
    }
  };

  return (
    <div ref={containerRef} className="relative h-full min-h-0 flex overflow-hidden">
      <div className="flex-1 min-w-0 min-h-0 overflow-hidden">{children}</div>
      {panel && (
        <>
          <div
            role="separator"
            aria-label="调整任务详情宽度"
            aria-orientation="vertical"
            aria-valuemin={MIN_INSPECTOR_WIDTH}
            aria-valuemax={Math.round(maxWidthForWindow)}
            aria-valuenow={Math.round(effectiveWidth)}
            tabIndex={0}
            onKeyDown={handleKeyDown}
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
            onLostPointerCapture={saveWidth}
            className="relative z-10 w-1.5 shrink-0 cursor-col-resize touch-none no-drag-region focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--pata-accent)] before:absolute before:inset-y-0 before:left-[2px] before:w-px before:bg-stone-200 dark:before:bg-stone-800 hover:before:bg-stone-400 dark:hover:before:bg-stone-600"
            title="拖拽调整任务详情宽度（方向键微调）"
          />
          <aside
            style={{ width: effectiveWidth }}
            className="shrink-0 h-full min-h-0 overflow-hidden flex flex-col"
            aria-label="任务详情"
          >
            {panel}
          </aside>
        </>
      )}
    </div>
  );
}
