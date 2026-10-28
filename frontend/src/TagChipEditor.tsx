import React, { useState, useRef, useEffect, useMemo } from 'react';
import { Plus, X } from 'lucide-react';
import { validateTag, hasTag, filterSuggestedTags } from './tagUtils';

export interface TagChipEditorProps {
  tags: string[];
  suggestedTags?: string[];
  onAddTag: (tag: string) => boolean | Promise<boolean>;
  onRemoveTag: (tag: string) => void | Promise<void>;
  readOnly?: boolean;
  className?: string;
  addLabel?: string;
  addLabelEmpty?: string;
}

export function TagChipEditor({
  tags,
  suggestedTags = [],
  onAddTag,
  onRemoveTag,
  readOnly = false,
  className = '',
  addLabel = '标签',
  addLabelEmpty = '添加标签',
}: TagChipEditorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const [error, setError] = useState<string | null>(null);

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Focus input when popover opens
  useEffect(() => {
    if (isOpen) {
      inputRef.current?.focus();
    }
  }, [isOpen]);

  // Outside click closes popover and discards uncommitted input
  useEffect(() => {
    if (!isOpen) return;
    const handleMouseDown = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
        setInputValue('');
        setError(null);
      }
    };
    window.addEventListener('mousedown', handleMouseDown);
    return () => window.removeEventListener('mousedown', handleMouseDown);
  }, [isOpen]);

  // Escape key closes popover and discards uncommitted input without bubbling
  useEffect(() => {
    if (!isOpen) return;
    const handleGlobalKeyDown = (e: KeyboardEvent) => {
      if (e.isComposing || e.keyCode === 229) {
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        setIsOpen(false);
        setInputValue('');
        setError(null);
      }
    };
    window.addEventListener('keydown', handleGlobalKeyDown, true);
    return () => window.removeEventListener('keydown', handleGlobalKeyDown, true);
  }, [isOpen]);

  const availableSuggestions = useMemo(() => {
    return filterSuggestedTags(suggestedTags, tags, inputValue, 6);
  }, [suggestedTags, tags, inputValue]);

  const submitTag = async (raw: string) => {
    const res = validateTag(raw);
    if (!res.ok) {
      setError(res.error ?? '标签格式不正确');
      return;
    }
    const clean = res.tag!;
    if (hasTag(tags, clean)) {
      // Tag already exists (case-insensitive deduplication), cleanly close popover
      setIsOpen(false);
      setInputValue('');
      setError(null);
      return;
    }

    const accepted = await onAddTag(clean);
    if (accepted !== false) {
      setIsOpen(false);
      setInputValue('');
      setError(null);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    // Prevent submission during IME composition (e.g. Chinese pinyin)
    if (e.nativeEvent.isComposing || e.key === 'Process' || e.keyCode === 229) {
      return;
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      void submitTag(inputValue);
      return;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      setIsOpen(false);
      setInputValue('');
      setError(null);
      return;
    }
  };

  return (
    <div className={`flex flex-wrap items-center gap-1.5 ${className}`}>
      {tags.map((tag) => (
        <span
          key={tag}
          className="group inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-mono text-stone-600 dark:text-stone-400 bg-stone-100 dark:bg-stone-800/80 hover:bg-stone-200/70 dark:hover:bg-stone-700/70 transition select-none"
        >
          <span>#{tag}</span>
          {!readOnly && (
            <button
              type="button"
              onClick={() => void onRemoveTag(tag)}
              className="text-stone-400 hover:text-rose-600 dark:hover:text-rose-400 transition cursor-pointer"
              title={`移除 #${tag}`}
              aria-label={`移除标签 #${tag}`}
            >
              <X className="w-2.5 h-2.5" />
            </button>
          )}
        </span>
      ))}

      {!readOnly && (
        <div className="relative" ref={containerRef}>
          <button
            type="button"
            onClick={() => {
              setIsOpen((v) => !v);
              setInputValue('');
              setError(null);
            }}
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs text-muted-foreground hover:text-stone-700 dark:hover:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition cursor-pointer select-none"
            title="添加标签"
          >
            <Plus className="w-3 h-3" />
            <span>{tags.length === 0 ? addLabelEmpty : addLabel}</span>
          </button>

          {isOpen && (
            <div className="absolute left-0 top-full mt-1 w-52 rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 shadow-lg p-2 z-30 space-y-2">
              <input
                ref={inputRef}
                type="text"
                value={inputValue}
                onChange={(e) => {
                  setInputValue(e.target.value);
                  if (error) setError(null);
                }}
                onKeyDown={handleKeyDown}
                placeholder="输入标签名称..."
                autoFocus
                className="w-full px-2 py-1 text-xs rounded border border-stone-200 dark:border-stone-800 bg-stone-50 dark:bg-stone-950 text-stone-900 dark:text-stone-100 placeholder:text-muted-foreground focus:outline-hidden focus:border-stone-400 dark:focus:border-stone-600"
              />

              {error && (
                <div className="text-[11px] text-rose-500 dark:text-rose-400 px-1 font-medium">
                  {error}
                </div>
              )}

              {availableSuggestions.length > 0 && (
                <div className="space-y-0.5 max-h-32 overflow-y-auto">
                  <div className="text-[11px] text-muted-foreground px-1">已有标签</div>
                  {availableSuggestions.map((t) => (
                    <button
                      key={t}
                      type="button"
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => void submitTag(t)}
                      className="w-full text-left px-2 py-1 rounded text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition font-mono truncate cursor-pointer"
                    >
                      #{t}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
