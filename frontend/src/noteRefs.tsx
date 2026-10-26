// 阶段 7/9：统一引用（`[[` 搜索选择 Note 与 File、阅读态点击与预览、路径/链接辅助）。
// Note 保留稳定 ID 绑定与相对链接；File 统一为标准 Markdown 相对链接（如 [文件名](../files/...)），
// 纯文本区域（Task 描述与 Activity）识别并渲染文件可点击项，不引入富文本。
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Events } from '@wailsio/runtime';
import { Paperclip, FileText, ExternalLink } from 'lucide-react';
import * as VaultService from '../bindings/pata/internal/app/vaultservice';
import {
  CandidateItem,
  FileRef,
  NoteRef,
  NoteRefMap,
  escapeLinkPath,
  fileLinkRe,
  filterCandidates,
  isVaultFileLink,
  matchTrigger,
  pickerKey,
  relativePath,
  resolveFileHref,
  resolveRef,
  textRefRe,
} from './noteRefsCore';

export * from './noteRefsCore';

/** 当前 Vault 全部笔记（ID/标题/相对路径），随 vault:changed 刷新。 */
export function useNoteRefs(): NoteRef[] {
  const [notes, setNotes] = useState<NoteRef[]>([]);
  const load = useCallback(() => {
    VaultService.ListNoteRefs()
      .then((r) => setNotes((r ?? []).filter((n): n is NoteRef => n !== null)))
      .catch(() => {});
  }, []);
  useEffect(() => {
    load();
    const off = Events.On('vault:changed', load);
    return () => {
      off();
    };
  }, [load]);
  return notes;
}

/** 当前 Vault 全部普通文件（files/ 相对路径/文件名/后缀/大小），随 vault:changed 刷新。 */
export function useFileRefs(): FileRef[] {
  const [files, setFiles] = useState<FileRef[]>([]);
  const load = useCallback(() => {
    VaultService.ListFiles()
      .then((r) =>
        setFiles(
          (r ?? [])
            .filter((f): f is NonNullable<typeof f> => f !== null)
            .map((f) => ({
              name: f.name,
              path: f.path,
              ext: f.ext,
              size: f.size,
              mod_time: f.mod_time,
            }))
        )
      )
      .catch(() => {});
  }, []);
  useEffect(() => {
    load();
    const off = Events.On('vault:changed', load);
    return () => {
      off();
    };
  }, [load]);
  return files;
}

export function NotePicker({
  items,
  allNotes,
  index,
  left,
  top,
  bottom,
  onPick,
  onHover,
}: {
  items: (NoteRef | CandidateItem)[];
  allNotes: NoteRef[];
  index: number;
  left: number;
  top?: number;
  bottom?: number;
  onPick: (item: any) => void;
  onHover: (i: number) => void;
}) {
  const dup = (title: string) => allNotes.filter((n) => n.title === title).length > 1;
  const isCandidate = (it: any): it is CandidateItem => it && 'kind' in it;

  const picker = (
    <div
      role="listbox"
      aria-label="引用笔记或文件"
      style={{
        position: 'fixed',
        left: Math.min(left, Math.max(16, window.innerWidth - 300)),
        ...(bottom !== undefined ? { bottom } : { top }),
        width: 280,
      }}
      className="z-50 max-h-64 overflow-y-auto rounded-lg border border-stone-200 dark:border-stone-700 bg-white dark:bg-stone-900 shadow-xl py-1 text-xs"
    >
      {items.length === 0 ? (
        <div className="px-3 py-2 text-stone-400">没有找到匹配项</div>
      ) : (
        items.map((it, i) => {
          const kind = isCandidate(it) ? it.kind : 'note';
          const title = isCandidate(it) ? (it.kind === 'note' ? it.note.title : it.file.name) : it.title;
          const path = isCandidate(it) ? (it.kind === 'note' ? it.note.path : it.file.path) : it.path;
          const showPath = kind === 'file' || dup(title);

          return (
            <div
              key={isCandidate(it) ? `${it.kind}-${path}` : it.id}
              role="option"
              aria-selected={i === index}
              onMouseDown={(e) => {
                e.preventDefault();
                onPick(it);
              }}
              onMouseEnter={() => onHover(i)}
              className={`px-3 py-1.5 cursor-pointer flex items-center gap-2 ${
                i === index
                  ? 'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-800 dark:text-emerald-200'
                  : 'text-stone-700 dark:text-stone-300'
              }`}
            >
              {kind === 'file' ? (
                <Paperclip className="w-3.5 h-3.5 text-blue-500 shrink-0" />
              ) : (
                <FileText className="w-3.5 h-3.5 text-stone-400 shrink-0" />
              )}
              <div className="min-w-0 flex-1">
                <div className="truncate font-medium">{title}</div>
                {showPath && <div className="truncate text-[10px] text-stone-400">{path}</div>}
              </div>
            </div>
          );
        })
      )}
    </div>
  );

  if (typeof document !== 'undefined') {
    return createPortal(picker, document.body);
  }
  return picker;
}

/** 阅读态：按纯文本显示，把 `[[名称]]` 渲染成笔记链接，把 `[文件名](files/...)` 渲染成文件预览项。 */
export function NoteRefText({
  text,
  refs,
  notes,
  files,
  onOpenNote,
  className,
}: {
  text: string;
  refs?: NoteRefMap;
  notes: NoteRef[];
  files?: FileRef[];
  onOpenNote?: (id: string) => void;
  className?: string;
}) {
  const loadedFiles = useFileRefs();
  const allFiles = files ?? loadedFiles;

  type Token =
    | { type: 'note'; start: number; end: number; name: string; escaped: boolean }
    | { type: 'file'; start: number; end: number; title: string; href: string };

  const tokens: Token[] = [];

  for (const m of text.matchAll(textRefRe())) {
    const at = m.index ?? 0;
    tokens.push({
      type: 'note',
      start: at,
      end: at + m[0].length,
      name: m[2],
      escaped: Boolean(m[1]),
    });
  }

  for (const m of text.matchAll(fileLinkRe())) {
    const at = m.index ?? 0;
    const dest = m[3];
    if (isVaultFileLink(dest)) {
      tokens.push({
        type: 'file',
        start: at,
        end: at + m[0].length,
        title: m[2],
        href: dest,
      });
    }
  }

  tokens.sort((a, b) => a.start - b.start);

  const nonOverlapping: Token[] = [];
  let curEnd = 0;
  for (const t of tokens) {
    if (t.start >= curEnd) {
      nonOverlapping.push(t);
      curEnd = t.end;
    }
  }

  const parts: React.ReactNode[] = [];
  let last = 0;

  for (const t of nonOverlapping) {
    parts.push(text.slice(last, t.start));
    last = t.end;

    if (t.type === 'note') {
      if (t.escaped) {
        parts.push(`[[${t.name}]]`);
        continue;
      }
      const { note, reason } = resolveRef(t.name, refs, notes);
      parts.push(
        note ? (
          <button
            key={`note-${t.start}`}
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onOpenNote?.(note.id);
            }}
            title={note.path}
            className="text-emerald-700 dark:text-emerald-400 underline decoration-dotted underline-offset-2 hover:decoration-solid cursor-pointer text-left"
          >
            {t.name}
          </button>
        ) : (
          <span key={`note-${t.start}`} title={reason} className="text-amber-700 dark:text-amber-400">
            [[{t.name}]]
          </span>
        )
      );
    } else {
      const fileTarget = resolveFileHref('tasks/task.md', t.href, allFiles);
      if (allFiles.length > 0 && !fileTarget) {
        parts.push(
          <span
            key={`file-${t.start}`}
            title="文件不存在或已移动"
            className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 text-amber-700 dark:text-amber-400 font-sans text-xs leading-none align-[-1px]"
          >
            <Paperclip className="w-3 h-3 shrink-0" />
            <span className="leading-none">{t.title} (文件已丢失)</span>
          </span>
        );
      } else {
        const targetPath = fileTarget?.path || (t.href.includes('files/') ? t.href.slice(t.href.indexOf('files/')) : t.href);
        parts.push(
          <span
            key={`file-${t.start}`}
            className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-stone-100 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 text-stone-800 dark:text-stone-200 font-sans text-xs leading-none align-[-1px]"
          >
            <Paperclip className="w-3 h-3 text-stone-400 shrink-0" />
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                VaultService.PreviewFile(targetPath).catch((err) => {
                  console.warn('Preview file error:', err);
                });
              }}
              title={`点击预览 ${t.title}`}
              className="hover:underline text-emerald-700 dark:text-emerald-400 font-medium cursor-pointer leading-none"
            >
              {t.title}
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                VaultService.RevealInFinder(targetPath).catch((err) => {
                  console.warn('Reveal in finder error:', err);
                });
              }}
              title="在 Finder 中显示"
              className="p-0.5 text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 rounded cursor-pointer leading-none inline-flex items-center"
            >
              <ExternalLink className="w-2.5 h-2.5" />
            </button>
          </span>
        );
      }
    }
  }

  parts.push(text.slice(last));
  return <div className={`whitespace-pre-wrap break-words ${className ?? ''}`}>{parts}</div>;
}

type TAProps = Omit<React.TextareaHTMLAttributes<HTMLTextAreaElement>, 'value' | 'onChange'> & {
  value: string;
  onChange: (v: string) => void;
  refs: NoteRefMap;
  onRefsChange: (r: NoteRefMap) => void;
  notes: NoteRef[];
  files?: FileRef[];
  hostPath?: string;
  autoAdjustHeight?: boolean;
  minHeight?: number;
};

/** 带 `[[` 笔记与文件候选的纯文本输入框，支持拖入/粘贴文件导入。 */
export function NoteRefTextarea({
  value,
  onChange,
  refs,
  onRefsChange,
  notes,
  files,
  hostPath = 'tasks/task.md',
  autoAdjustHeight,
  minHeight = 22,
  onKeyDown,
  ...rest
}: TAProps) {
  const ta = useRef<HTMLTextAreaElement>(null);
  const dismissed = useRef(-1);
  const loadedFiles = useFileRefs();
  const allFiles = files ?? loadedFiles;

  const [st, setSt] = useState<{
    start: number;
    query: string;
    index: number;
    left: number;
    top?: number;
    bottom?: number;
  } | null>(null);

  const items = st ? filterCandidates(notes, allFiles, st.query) : [];

  useEffect(() => {
    if (autoAdjustHeight && ta.current) {
      ta.current.style.height = 'auto';
      ta.current.style.height = `${Math.max(ta.current.scrollHeight, minHeight)}px`;
    }
  }, [value, autoAdjustHeight, minHeight]);

  const sync = (el: HTMLTextAreaElement) => {
    const m = matchTrigger(el.value.slice(0, el.selectionStart));
    if (!m) {
      dismissed.current = -1;
      setSt(null);
      return;
    }
    if (dismissed.current === m.start) return;
    const r = el.getBoundingClientRect();
    const pickerHeight = 240;
    const spaceBelow = window.innerHeight - r.bottom;
    const showAbove = spaceBelow < pickerHeight && r.top > pickerHeight;
    setSt((p) => ({
      ...m,
      index: p && p.query === m.query ? p.index : 0,
      left: r.left,
      top: showAbove ? undefined : r.bottom + 4,
      bottom: showAbove ? window.innerHeight - r.top + 4 : undefined,
    }));
  };

  const pick = (it: CandidateItem | NoteRef) => {
    const el = ta.current;
    if (!el || !st) return;
    const isCand = 'kind' in it;
    if (isCand && it.kind === 'file') {
      const f = it.file;
      const host = hostPath || 'tasks/task.md';
      const rel = relativePath(host, f.path);
      const ins = `[${f.name}](${escapeLinkPath(rel)}) `;
      const caret = el.selectionStart;
      onChange(value.slice(0, st.start) + ins + value.slice(caret));
      setSt(null);
      const pos = st.start + ins.length;
      requestAnimationFrame(() => {
        el.focus();
        el.setSelectionRange(pos, pos);
      });
      return;
    }

    const n = isCand && it.kind === 'note' ? it.note : (it as NoteRef);
    let key = n.title.replace(/[\[\]]/g, '').trim() || n.path;
    if (refs[key] && refs[key] !== n.id) key = `${key} (${n.path})`.replace(/[\[\]]/g, '');
    const caret = el.selectionStart;
    const ins = `[[${key}]]`;
    onChange(value.slice(0, st.start) + ins + value.slice(caret));
    onRefsChange({ ...refs, [key]: n.id });
    setSt(null);
    const pos = st.start + ins.length;
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(pos, pos);
    });
  };

  const handleDroppedFiles = async (fileList: FileList | File[]) => {
    if (!fileList || fileList.length === 0) return;
    const el = ta.current;
    let insertion = '';
    for (let i = 0; i < fileList.length; i++) {
      const f = fileList[i];
      try {
        let imported: FileRef | null = null;
        if ((f as any).path) {
          imported = await VaultService.ImportFile((f as any).path);
        } else {
          const b64 = await new Promise<string>((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result as string);
            reader.onerror = reject;
            reader.readAsDataURL(f);
          });
          imported = await VaultService.ImportFileData(f.name, b64);
        }
        if (imported) {
          const host = hostPath || 'tasks/task.md';
          const rel = relativePath(host, imported.path);
          insertion += `[${imported.name}](${escapeLinkPath(rel)}) `;
        }
      } catch (err) {
        console.error('Failed to import file:', err);
      }
    }
    if (insertion) {
      const pos = el ? el.selectionStart : value.length;
      onChange(value.slice(0, pos) + insertion + value.slice(pos));
    }
  };

  return (
    <>
      <textarea
        {...rest}
        ref={ta}
        value={value}
        onChange={(e) => {
          onChange(e.target.value);
          if (autoAdjustHeight) {
            e.target.style.height = 'auto';
            e.target.style.height = `${Math.max(e.target.scrollHeight, minHeight)}px`;
          }
          sync(e.target);
        }}
        onSelect={(e) => sync(e.currentTarget)}
        onBlur={(e) => {
          if (st) setSt(null);
          rest.onBlur?.(e);
        }}
        onDrop={(e) => {
          if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
            e.preventDefault();
            void handleDroppedFiles(e.dataTransfer.files);
          }
        }}
        onPaste={(e) => {
          if (e.clipboardData.files && e.clipboardData.files.length > 0) {
            e.preventDefault();
            void handleDroppedFiles(e.clipboardData.files);
          }
        }}
        onKeyDown={(e) => {
          if (
            st &&
            pickerKey(
              e,
              e.nativeEvent.isComposing || e.keyCode === 229,
              items.length,
              st.index,
              (i) => setSt({ ...st, index: i }),
              () => pick(items[st.index]),
              () => {
                dismissed.current = st.start;
                setSt(null);
              }
            )
          )
            return;
          onKeyDown?.(e);
        }}
      />
      {st && (
        <NotePicker
          items={items}
          allNotes={notes}
          index={st.index}
          left={st.left}
          top={st.top}
          bottom={st.bottom}
          onPick={pick}
          onHover={(i) => setSt({ ...st, index: i })}
        />
      )}
    </>
  );
}

