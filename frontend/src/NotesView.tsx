import { useState, useEffect, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Events } from '@wailsio/runtime';
import {
  FileText,
  Plus,
  AlertCircle,
  RefreshCw,
  FolderOpen,
  ArrowLeft,
  Loader2,
  Check,
  Copy,
  Volume2,
  ChevronDown,
} from 'lucide-react';
import Vditor from 'vditor';
import * as VaultService from '../bindings/pata/vaultservice';
import { VaultStatus, CreateNoteInput, UpdateNoteInput } from '../bindings/pata/models';
import { Note, LinkSource, EntityType } from '../bindings/pata/internal/storage/markdown/models';
import { ASRTaskStatus, ASRTaskState } from '../bindings/pata/internal/asr/models';
import { AudioPlayer } from './AudioPlayer';
import { TranscriptViewer, TranscriptViewerRef } from './TranscriptViewer';
import {
  CandidateItem,
  FileRef,
  NotePicker,
  NoteRef,
  escapeLinkPath,
  filterCandidates,
  matchTrigger,
  pickerKey,
  relativePath,
  resolveFileHref,
  resolveHref,
  useFileRefs,
  useNoteRefs,
} from './noteRefs';

interface NotesViewProps {
  vaultStatus: VaultStatus | null;
  onSelectVault: () => void;
  onRescanVault: () => void;
  vaultBusy?: boolean;
  focusNoteId?: string | null;
  onClearFocusNote?: () => void;
  /** 从任务打开笔记时的返回入口（回到来源任务详情）。 */
  returnToTask?: { label: string; go: () => void } | null;
  onOpenTask?: (taskId: string) => void;
  onEditingChange?: (isEditing: boolean) => void;
  leaveGuardRef?: React.MutableRefObject<(() => Promise<boolean>) | null>;
  onOpenSettings?: (section?: 'appearance' | 'storage' | 'transcription') => void;
}

function formatRelativeTime(isoString: string): string {
  if (!isoString) return '';
  try {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;
    const now = new Date();
    const diffSec = Math.floor((now.getTime() - d.getTime()) / 1000);
    if (diffSec < 60) return '刚刚';
    const diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return `${diffMin} 分钟前`;
    const diffHour = Math.floor(diffMin / 60);
    if (diffHour < 24) return `${diffHour} 小时前`;

    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    const isYesterday =
      d.getFullYear() === yesterday.getFullYear() &&
      d.getMonth() === yesterday.getMonth() &&
      d.getDate() === yesterday.getDate();
    if (isYesterday) return '昨天';

    const diffDay = Math.floor(diffHour / 24);
    if (diffDay < 7) return `${diffDay} 天前`;

    const pad = (n: number) => n.toString().padStart(2, '0');
    const y = d.getFullYear();
    const m = pad(d.getMonth() + 1);
    const day = pad(d.getDate());
    if (y === now.getFullYear()) {
      return `${m}-${day}`;
    }
    return `${y}-${m}-${day}`;
  } catch {
    return isoString;
  }
}

function isAudioTranscriptNote(note?: Note | null): note is Note & { audio_transcript: true; audio_file: string } {
  return Boolean(note && note.audio_transcript && note.audio_file && note.audio_file.trim().length > 0);
}

function getNoteExcerpt(title: string, body?: string): string {
  if (!body) return '';
  const lines = body.split('\n');
  let startIdx = 0;
  if (lines.length > 0) {
    const firstLine = lines[0].trim();
    if (firstLine.startsWith('#')) {
      const headingText = firstLine.replace(/^#+\s*/, '').trim();
      if (headingText.toLowerCase() === title.trim().toLowerCase()) {
        startIdx = 1;
      }
    }
  }
  const remaining = lines.slice(startIdx).join(' ');
  const cleaned = remaining
    .replace(/[#*`>_~\[\]]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned;
}

function parseTags(tagStr: string): string[] {
  return tagStr
    .split(/[,，]/)
    .map((t) => t.trim().replace(/^#+/, ''))
    .filter((t) => t.length > 0);
}

interface NoteEditorProps {
  noteId: string;
  isNew?: boolean;
  onBack: () => void;
  backLabel: string;
  onOpenNote: (id: string) => void;
  onOpenTask?: (id: string) => void;
  onNoteUpdated: () => void;
  onNoteCreated?: (newId: string) => void;
  leaveGuardRef?: React.MutableRefObject<(() => Promise<boolean>) | null>;
  onOpenSettings?: (section?: 'appearance' | 'storage' | 'transcription') => void;
}

function NoteEditor({
  noteId,
  isNew = false,
  onBack,
  backLabel,
  onOpenNote,
  onOpenTask,
  onNoteUpdated,
  onNoteCreated,
  leaveGuardRef,
  onOpenSettings,
}: NoteEditorProps) {
  const [initialNote, setInitialNote] = useState<Note | null>(null);
  const initialNoteRef = useRef<Note | null>(initialNote);
  initialNoteRef.current = initialNote;
  const [loadingNote, setLoadingNote] = useState<boolean>(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Audio transcript specific states
  const [asrStatus, setAsrStatus] = useState<ASRTaskStatus | null>(null);
  const audioElRef = useRef<HTMLAudioElement | null>(null);
  const transcriptViewerRef = useRef<TranscriptViewerRef | null>(null);
  const [showReplaceConfirm, setShowReplaceConfirm] = useState<boolean>(false);
  const [replaceError, setReplaceError] = useState<string | null>(null);

  const [editTitle, setEditTitle] = useState<string>('');
  const [editTags, setEditTags] = useState<string>('');
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving' | 'unsaved' | 'failed' | 'conflict'>('saved');
  const [saveError, setSaveError] = useState<string | null>(null);
  const [conflictError, setConflictError] = useState<string | null>(null);
  const [titleError, setTitleError] = useState<string | null>(null);

  const [showReloadConfirm, setShowReloadConfirm] = useState<boolean>(false);
  const [showLeaveConflictConfirm, setShowLeaveConflictConfirm] = useState<boolean>(false);
  const [showSaveFailedConfirm, setShowSaveFailedConfirm] = useState<boolean>(false);
  const [showDraftNoTitleConfirm, setShowDraftNoTitleConfirm] = useState<boolean>(false);
  const [copiedDraft, setCopiedDraft] = useState<boolean>(false);
  const [isEditingTags, setIsEditingTags] = useState<boolean>(false);
  const tagsInputRef = useRef<HTMLInputElement | null>(null);
  const titleInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (isNew) {
      titleInputRef.current?.focus();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isNewDraftRef = useRef<boolean>(isNew);
  const currentNoteIdRef = useRef<string>(noteId);

  const allNotes = useNoteRefs();
  const allNotesRef = useRef<NoteRef[]>([]);
  allNotesRef.current = allNotes;
  const allFiles = useFileRefs();
  const allFilesRef = useRef<FileRef[]>([]);
  allFilesRef.current = allFiles;
  const [backlinks, setBacklinks] = useState<LinkSource[]>([]);
  const [backlinksOpen, setBacklinksOpen] = useState(false);
  // `[[` 笔记候选：node 为正在输入的文本节点
  const [picker, setPicker] = useState<{ start: number; query: string; index: number; left: number; top?: number; bottom?: number } | null>(null);
  const pickerRef = useRef(picker);
  pickerRef.current = picker;
  const pickerDismissedRef = useRef(-1);
  const pendingGoRef = useRef<(() => void) | null>(null);
  const leavePromptResolverRef = useRef<((proceed: boolean) => void) | null>(null);

  const askUserConfirm = (openDialog: () => void): Promise<boolean> => {
    return new Promise<boolean>((resolve) => {
      leavePromptResolverRef.current = resolve;
      openDialog();
    });
  };

  const vditorRef = useRef<Vditor | null>(null);
  const vditorContainerRef = useRef<HTMLDivElement | null>(null);
  const lastSavedStateRef = useRef<{ title: string; tags: string[]; body: string } | null>(null);
  const debounceTimerRef = useRef<number | null>(null);
  const hasConflictRef = useRef<boolean>(false);
  const isSavingRef = useRef<boolean>(false);

  const editTitleRef = useRef<string>('');
  const editTagsRef = useRef<string>('');
  const triggerDebouncedSaveRef = useRef<() => void>(() => {});
  const isVditorMountedRef = useRef<boolean>(false);
  const onNoteCreatedRef = useRef(onNoteCreated);
  onNoteCreatedRef.current = onNoteCreated;
  const onNoteUpdatedRef = useRef(onNoteUpdated);
  onNoteUpdatedRef.current = onNoteUpdated;
  const onBackRef = useRef(onBack);
  onBackRef.current = onBack;
  const onOpenNoteRef = useRef(onOpenNote);
  onOpenNoteRef.current = onOpenNote;
  const onOpenTaskRef = useRef(onOpenTask);
  onOpenTaskRef.current = onOpenTask;

  // Dirty check: comparison with last persisted state
  const isDirty = useCallback((currentTitle: string, currentTags: string[], currentBody: string): boolean => {
    if (isNewDraftRef.current) {
      return !!currentTitle.trim() || !!currentBody || currentTags.length > 0;
    }
    if (!lastSavedStateRef.current) return false;
    const last = lastSavedStateRef.current;
    if (currentTitle.trim() !== last.title.trim()) return true;
    if (!isAudioTranscriptNote(initialNoteRef.current) && currentBody !== last.body) return true;
    if (currentTags.length !== last.tags.length) return true;
    for (let i = 0; i < currentTags.length; i++) {
      if (currentTags[i] !== last.tags[i]) return true;
    }
    return false;
  }, []);

  const isDirtyRef = useRef(isDirty);
  isDirtyRef.current = isDirty;
  const doSaveRef = useRef<() => Promise<boolean>>(() => Promise.resolve(false));

  // Save implementation (D19)
  const doSave = useCallback(async (force: boolean = false): Promise<boolean> => {
    if (hasConflictRef.current && !force) {
      return false;
    }

    // must-fix 2: vditorRef 为 null (初始化未完成) 时绝对不能写盘，避免空 body 清空正文（只读逐字稿 Note 无需 vditorRef）
    if (!vditorRef.current && !isAudioTranscriptNote(initialNoteRef.current)) {
      return false;
    }

    const currentTitle = editTitleRef.current.trim();
    const currentBody = isAudioTranscriptNote(initialNoteRef.current)
      ? (initialNoteRef.current?.body ?? '')
      : (vditorRef.current ? vditorRef.current.getValue() : '');
    const currentTags = parseTags(editTagsRef.current);

    // 新建草稿保存分支：标题为空时维持安全草稿状态，不写非法空文件到磁盘
    if (isNewDraftRef.current) {
      if (!currentTitle) {
        if (currentBody.trim() || currentTags.length > 0) {
          setTitleError('笔记标题不能为空，请输入标题以保存');
          setSaveStatus('unsaved');
        } else {
          setTitleError(null);
          setSaveStatus('saved');
        }
        return false;
      }
      setTitleError(null);

      if (isSavingRef.current) {
        return false;
      }

      isSavingRef.current = true;
      setSaveStatus('saving');
      let createdNote = false;

      try {
        const input: CreateNoteInput = {
          title: currentTitle,
          tags: currentTags,
          body: currentBody,
        };

        const created = await VaultService.CreateNote(input);
        if (created) {
          isNewDraftRef.current = false;
          currentNoteIdRef.current = created.id;
          lastSavedStateRef.current = {
            title: currentTitle,
            tags: currentTags,
            body: currentBody,
          };
          hasConflictRef.current = false;
          setConflictError(null);
          setSaveStatus('saved');
          setSaveError(null);
          onNoteCreatedRef.current?.(created.id);
          onNoteUpdatedRef.current();
          createdNote = true;
        }
        return createdNote;
      } catch (err: any) {
        console.error('CreateNote failed:', err);
        setSaveStatus('failed');
        setSaveError(err?.message || String(err));
        setTitleError(err?.message || String(err));
        return false;
      } finally {
        isSavingRef.current = false;
        if (createdNote && vditorRef.current) {
          const bodyNow = vditorRef.current.getValue();
          const titleNow = editTitleRef.current;
          const tagsNow = parseTags(editTagsRef.current);
          if (isDirtyRef.current(titleNow, tagsNow, bodyNow) && !hasConflictRef.current) {
            triggerDebouncedSaveRef.current();
          }
        }
      }
    }

    // 既有笔记更新分支
    if (!currentTitle) {
      setTitleError('笔记标题不能为空，无法保存');
      setSaveStatus('failed');
      setSaveError('笔记标题不能为空');
      return false;
    }
    setTitleError(null);

    if (!isDirtyRef.current(currentTitle, currentTags, currentBody)) {
      setSaveStatus('saved');
      setSaveError(null);
      return true;
    }

    if (isSavingRef.current) {
      return false;
    }

    isSavingRef.current = true;
    setSaveStatus('saving');
    let saved = false;

    try {
      // Frontmatter separation: title and tags from top inputs, body from Vditor
      const input: UpdateNoteInput = {
        id: currentNoteIdRef.current,
        title: currentTitle,
        tags: currentTags,
        body: currentBody,
      };

      const updated = await VaultService.UpdateNote(input);
      if (updated) {
        lastSavedStateRef.current = {
          title: currentTitle,
          tags: currentTags,
          body: currentBody,
        };
        hasConflictRef.current = false;
        setConflictError(null);
        setSaveStatus('saved');
        setSaveError(null);
        onNoteUpdatedRef.current();
        saved = true;
      }
      return saved;
    } catch (err: any) {
      console.error('UpdateNote failed:', err);
      const errMsg = err?.message || String(err);
      const isConflict = errMsg.includes('conflict') || errMsg.includes('写入冲突');

      if (isConflict) {
        hasConflictRef.current = true;
        setSaveStatus('conflict');
        setConflictError('文件已被外部修改（保存冲突）。自动保存已停止，当前本地草稿尚未写盘。为防内容丢失，建议先复制草稿到剪贴板后再重新加载或返回。');
        if (debounceTimerRef.current) {
          window.clearTimeout(debounceTimerRef.current);
          debounceTimerRef.current = null;
        }
      } else {
        setSaveStatus('failed');
        setSaveError(errMsg);
        setTitleError(errMsg);
      }
      return false;
    } finally {
      isSavingRef.current = false;
      // 仅当本次保存成功时才重排（保存 in-flight 期间新输入不丢）；若保存失败则不自动重排，避免无限重试
      if (saved && (vditorRef.current || isAudioTranscriptNote(initialNoteRef.current))) {
        const bodyNow = vditorRef.current ? vditorRef.current.getValue() : (initialNoteRef.current?.body ?? '');
        const titleNow = editTitleRef.current;
        const tagsNow = parseTags(editTagsRef.current);
        if (isDirtyRef.current(titleNow, tagsNow, bodyNow) && !hasConflictRef.current) {
          triggerDebouncedSaveRef.current();
        }
      }
    }
  }, []);

  doSaveRef.current = doSave;

  // Debounced auto-save (0.5s as per D19)
  const triggerDebouncedSave = useCallback(() => {
    if (hasConflictRef.current) return;
    setSaveStatus('unsaved');
    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }
    debounceTimerRef.current = window.setTimeout(() => {
      debounceTimerRef.current = null;
      doSaveRef.current();
    }, 500);
  }, []);

  useEffect(() => {
    triggerDebouncedSaveRef.current = triggerDebouncedSave;
  }, [triggerDebouncedSave]);

  const handleTitleChange = (val: string) => {
    setEditTitle(val);
    editTitleRef.current = val;
    if (!val.trim()) {
      if (!isNewDraftRef.current) {
        setTitleError('笔记标题不能为空');
      }
    } else {
      setTitleError(null);
      setSaveError(null);
      setSaveStatus('unsaved');
    }
    triggerDebouncedSave();
  };

  const handleTagsChange = (val: string) => {
    setEditTags(val);
    editTagsRef.current = val;
    setSaveError(null);
    setSaveStatus('unsaved');
    triggerDebouncedSave();
  };

  // Load note details on mount
  useEffect(() => {
    if (isNewDraftRef.current) {
      setInitialNote({
        id: '',
        type: EntityType.EntityTypeNote,
        title: '',
        tags: [],
        body: '',
        created_at: '',
        updated_at: '',
      });
      setEditTitle('');
      editTitleRef.current = '';
      setEditTags('');
      editTagsRef.current = '';
      lastSavedStateRef.current = {
        title: '',
        tags: [],
        body: '',
      };
      setLoadingNote(false);
      return;
    }

    let mounted = true;
    setLoadingNote(true);
    setLoadError(null);
    VaultService.GetNote(currentNoteIdRef.current)
      .then((n) => {
        if (!mounted || !n) return;
        setInitialNote(n);
        setEditTitle(n.title);
        editTitleRef.current = n.title;
        const tagsStr = (n.tags ?? []).join(', ');
        setEditTags(tagsStr);
        editTagsRef.current = tagsStr;
        lastSavedStateRef.current = {
          title: n.title,
          tags: n.tags ?? [],
          body: n.body ?? '',
        };
        setLoadingNote(false);
      })
      .catch((err) => {
        if (!mounted) return;
        setLoadError(err?.message || String(err));
        setLoadingNote(false);
      });
    return () => {
      mounted = false;
    };
  }, []);

  // Listen to ASR status events and task updates
  useEffect(() => {
    let unlistenStatus: (() => void) | undefined;
    let unlistenVault: (() => void) | undefined;
    let active = true;

    if (isAudioTranscriptNote(initialNote)) {
      VaultService.GetASRTaskStatus(noteId)
        .then((st) => {
          if (!active) return;
          setAsrStatus(st);
          if (st.state === ASRTaskState.StatePendingConfirmation) {
            setShowReplaceConfirm(true);
          }
          if (st.state === ASRTaskState.StateCompleted) {
            VaultService.GetNote(noteId).then((updated) => {
              if (active && updated) {
                setInitialNote(updated);
                lastSavedStateRef.current = {
                  title: updated.title,
                  tags: updated.tags || [],
                  body: updated.body || '',
                };
              }
            });
          }
        })
        .catch(() => {});

      const subStatus = Events.On('asr:status', (event: any) => {
        if (!active) return;
        if (event.data && event.data.note_id === noteId) {
          const st = event.data as ASRTaskStatus;
          setAsrStatus(st);
          if (st.state === ASRTaskState.StatePendingConfirmation) {
            setShowReplaceConfirm(true);
          }
          if (st.state === ASRTaskState.StateCompleted) {
            VaultService.GetNote(noteId).then((updated) => {
              if (active && updated) {
                setInitialNote(updated);
                lastSavedStateRef.current = {
                  title: updated.title,
                  tags: updated.tags || [],
                  body: updated.body || '',
                };
              }
            });
          }
        }
      });
      unlistenStatus = () => subStatus();

      const subVault = Events.On('vault:changed', (event: any) => {
        if (!active) return;
        if (event.data && event.data.entity_id === noteId && event.data.op === 'update') {
          VaultService.GetNote(noteId).then((updated) => {
            if (active && updated) {
              setInitialNote(updated);
              lastSavedStateRef.current = {
                title: updated.title,
                tags: updated.tags || [],
                body: updated.body || '',
              };
            }
          });
        }
      });
      unlistenVault = () => subVault();
    }

    return () => {
      active = false;
      if (unlistenStatus) unlistenStatus();
      if (unlistenVault) unlistenVault();
    };
  }, [noteId, isAudioTranscriptNote(initialNote)]);

  const handleRetranscribe = async () => {
    try {
      const cfg = await VaultService.GetASRConfigStatus();
      if (!cfg.configured) {
        onOpenSettings?.('transcription');
        return;
      }
      await VaultService.StartAudioTranscription(noteId);
      const st = await VaultService.GetASRTaskStatus(noteId);
      setAsrStatus(st);
    } catch (err: any) {
      console.error('StartAudioTranscription failed:', err);
      const errMsg = err?.message || String(err) || '启动转写失败';
      setAsrStatus((prev) => ({
        ...(prev || {}),
        note_id: noteId,
        state: ASRTaskState.StateFailed,
        stage_message: '重试失败',
        error: errMsg,
        updated_at: new Date().toISOString(),
      }));
    }
  };

  const handleConfirmReplace = async () => {
    try {
      setReplaceError(null);
      const updated = await VaultService.ConfirmReplaceTranscript(noteId);
      if (updated) {
        setInitialNote(updated);
        lastSavedStateRef.current = {
          title: updated.title,
          tags: updated.tags || [],
          body: updated.body || '',
        };
        setShowReplaceConfirm(false);
      }
    } catch (err: any) {
      setReplaceError(err?.message || '替换逐字稿失败');
    }
  };

  const handleDiscardCandidate = async () => {
    try {
      await VaultService.DiscardCandidateTranscript(noteId);
      setShowReplaceConfirm(false);
      const st = await VaultService.GetASRTaskStatus(noteId);
      setAsrStatus(st);
    } catch (err: any) {
      console.error('DiscardCandidateTranscript failed:', err);
    }
  };

  // Mount Vditor editor when note is loaded (only for normal editable notes)
  useEffect(() => {
    if (loadingNote || !initialNote || !vditorContainerRef.current || isVditorMountedRef.current || isAudioTranscriptNote(initialNote)) return;
    isVditorMountedRef.current = true;

    const isDark = document.documentElement.classList.contains('dark');

    // Vditor 离线包已裁剪至 <=8MB (从 23MB 裁剪至 7.5MB，保留 lute, highlight.js, icons, i18n, content-theme; 移除数学公式、流程图、脑图等重型图表库)
    // 若未来从 node_modules 重新同步，需参照 docs/02-foundation/spike-desktop-result.md §4 重新裁剪。
    const vditor = new Vditor(vditorContainerRef.current, {
      cdn: '/vditor',
      mode: 'ir',
      value: initialNote.body ?? '',
      height: '100%',
      placeholder: '开始记录内容...（支持 Markdown 语法、表格、代码块）',
      theme: isDark ? 'dark' : 'classic',
      preview: {
        theme: {
          current: isDark ? 'dark' : 'light',
        },
        hljs: {
          style: isDark ? 'github-dark' : 'github',
        },
        markdown: {
          toc: true,
          mark: true,
          footnotes: true,
          autoSpace: true,
        },
      },
      cache: {
        enable: false,
      },
      toolbar: [],
      toolbarConfig: {
        hide: true,
      },
      link: { isOpen: true, click: (a: Element) => linkClickRef.current(a as HTMLElement) },
      input: () => {
        triggerDebouncedSaveRef.current();
        syncPickerRef.current();
      },
      after: () => {
        vditorRef.current = vditor;
        // 如果在加载期间用户编辑了标题/标签，触发一次防抖保存检查
        const bodyNow = vditor.getValue();
        if (isDirtyRef.current(editTitleRef.current, parseTags(editTagsRef.current), bodyNow)) {
          triggerDebouncedSaveRef.current();
        }
      },
    });

    // Dark mode observer
    const observer = new MutationObserver(() => {
      const dark = document.documentElement.classList.contains('dark');
      vditor.setTheme(
        dark ? 'dark' : 'classic',
        dark ? 'dark' : 'light',
        dark ? 'github-dark' : 'github'
      );
    });
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class'],
    });

    return () => {
      observer.disconnect();
      if (debounceTimerRef.current) {
        window.clearTimeout(debounceTimerRef.current);
        debounceTimerRef.current = null;
      }
      try {
        vditor.destroy();
      } catch {
        // ignore
      }
      vditorRef.current = null;
      isVditorMountedRef.current = false;
    };
  }, [loadingNote]);

  // Subscribe to vault:changed: if hitting current note, trigger conflict path
  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', (ev) => {
      if (isNewDraftRef.current) return;
      const data = ev.data as { op?: string; path?: string; entity_id?: string; type?: string } | undefined;
      if (data?.entity_id === currentNoteIdRef.current) {
        hasConflictRef.current = true;
        if (debounceTimerRef.current) {
          window.clearTimeout(debounceTimerRef.current);
          debounceTimerRef.current = null;
        }
        setSaveStatus('conflict');
        setConflictError('外部检测到文件变动，自动保存已停止，当前本地草稿尚未写盘。为防内容丢失，建议先复制草稿到剪贴板后再重新加载或返回。');
      }
    });
    return () => {
      unsubscribe();
    };
  }, []);

  // Window beforeunload flush
  useEffect(() => {
    const handleBeforeUnload = () => {
      // shortcut: 导航切走时 best-effort flush,关窗/极速切换仍可能丢 ≤0.5s 输入,实机走查评估
      // 注：beforeunload 异步 IPC 关窗由于浏览器生命周期与 IPC 异步性亦可能丢失未保存数据，接受现状，不实现 Go 退出钩子
      if (debounceTimerRef.current) {
        window.clearTimeout(debounceTimerRef.current);
        debounceTimerRef.current = null;
        doSaveRef.current();
      }
    };
    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, []);

  // Unmount cleanup best-effort flush (should-fix 4)
  useEffect(() => {
    return () => {
      // shortcut: 导航切走时 best-effort flush,关窗/极速切换仍可能丢 ≤0.5s 输入,实机走查评估
      // 注：beforeunload 异步 IPC 关窗由于浏览器生命周期与 IPC 异步性亦可能丢失未保存数据，接受现状，不实现 Go 退出钩子
      if (debounceTimerRef.current) {
        window.clearTimeout(debounceTimerRef.current);
        debounceTimerRef.current = null;
      }
      doSaveRef.current();
    };
  }, []);

  // Keyboard shortcut Cmd+S / Ctrl+S to save immediately
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        if (debounceTimerRef.current) {
          window.clearTimeout(debounceTimerRef.current);
          debounceTimerRef.current = null;
        }
        doSaveRef.current();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  // 离开当前笔记（返回/打开引用/打开来源任务）前先 flush 自动保存；冲突或保存失败时留在原处（D19）
  const leaveThen = async (go: () => void) => {
    pendingGoRef.current = go;
    if (hasConflictRef.current) {
      setShowLeaveConflictConfirm(true);
      return;
    }
    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = null;
    }

    // 新建草稿离开判定
    if (isNewDraftRef.current) {
      const currentTitle = editTitleRef.current.trim();
      const currentBody = vditorRef.current ? vditorRef.current.getValue().trim() : '';
      const currentTags = parseTags(editTagsRef.current);

      // 若完全未输入任何内容，直接安全退出，不创建任何磁盘文件
      if (!currentTitle && !currentBody && currentTags.length === 0) {
        pendingGoRef.current = null;
        go();
        return;
      }

      // 若已输入有效标题，执行保存后退出
      if (currentTitle) {
        const saved = await doSave();
        if (saved) {
          pendingGoRef.current = null;
          go();
        } else {
          setShowSaveFailedConfirm(true);
        }
        return;
      }

      // 未输入标题但已输入正文或标签，弹窗警告防误丢
      setShowDraftNoTitleConfirm(true);
      return;
    }

    const currentTitle = editTitleRef.current;
    const currentTags = parseTags(editTagsRef.current);
    const currentBody = vditorRef.current ? vditorRef.current.getValue() : (initialNote?.body ?? '');
    const dirty = isDirty(currentTitle, currentTags, currentBody);

    if (!dirty) {
      pendingGoRef.current = null;
      go();
      return;
    }

    const saved = await doSave();
    if (saved) {
      pendingGoRef.current = null;
      go();
    } else {
      setShowSaveFailedConfirm(true);
    }
  };
  const handleBackClick = () => leaveThen(onBackRef.current);

  useEffect(() => {
    if (!leaveGuardRef) return;
    leaveGuardRef.current = async () => {
      if (hasConflictRef.current) {
        return askUserConfirm(() => setShowLeaveConflictConfirm(true));
      }

      if (debounceTimerRef.current) {
        window.clearTimeout(debounceTimerRef.current);
        debounceTimerRef.current = null;
      }

      const currentTitle = editTitleRef.current.trim();
      const currentTags = parseTags(editTagsRef.current);
      const currentBody = vditorRef.current ? vditorRef.current.getValue() : (initialNote?.body ?? '');
      const dirty = isDirty(currentTitle, currentTags, currentBody);
      if (!dirty) return true;

      if (isNewDraftRef.current && !currentTitle) {
        if (!currentBody.trim() && currentTags.length === 0) {
          return true;
        }
        return askUserConfirm(() => setShowDraftNoTitleConfirm(true));
      }

      const saved = await doSave();
      if (!saved) {
        return askUserConfirm(() => setShowSaveFailedConfirm(true));
      }
      return true;
    };
    return () => {
      leaveGuardRef.current = null;
      if (leavePromptResolverRef.current) {
        leavePromptResolverRef.current(false);
        leavePromptResolverRef.current = null;
      }
      pendingGoRef.current = null;
    };
  }, [leaveGuardRef, isDirty, doSave, initialNote]);

  // ---- `[[` 笔记候选 + 链接点击 ----
  const syncPicker = () => {
    const sel = window.getSelection();
    const root = vditorContainerRef.current;
    const node = sel?.anchorNode;
    const isCode = !!node?.parentElement?.closest('code, [data-type="code-block"], pre:not(.vditor-reset)');
    const m =
      sel && sel.isCollapsed && root && node && node.nodeType === 3 && root.contains(node) && !isCode
        ? matchTrigger((node.textContent ?? '').slice(0, sel.anchorOffset))
        : null;
    if (!sel || !m) {
      pickerDismissedRef.current = -1;
      setPicker((p) => (p ? null : p));
      return;
    }
    if (pickerDismissedRef.current === m.start) return;
    const selRange = sel.getRangeAt(0);
    let r = selRange.getBoundingClientRect();
    if (!r.height && !r.width) {
      if (node!.nodeType === 3 && sel.anchorOffset > 0) {
        const clone = selRange.cloneRange();
        clone.setStart(node!, sel.anchorOffset - 1);
        const cr = clone.getBoundingClientRect();
        r = { ...cr, left: cr.right };
      } else if (node!.parentElement) {
        r = node!.parentElement.getBoundingClientRect();
      }
    }
    const pickerHeight = 240;
    const spaceBelow = window.innerHeight - r.bottom;
    const showAbove = spaceBelow < pickerHeight && r.top > pickerHeight;
    setPicker((p) => ({
      ...m,
      index: p && p.query === m.query ? p.index : 0,
      left: r.left,
      top: showAbove ? undefined : r.bottom + 4,
      bottom: showAbove ? window.innerHeight - r.top + 4 : undefined,
    }));
  };

  const pickNote = (it: CandidateItem | NoteRef) => {
    const vd = vditorRef.current;
    const st = pickerRef.current;
    const sel = window.getSelection();
    const node = sel?.anchorNode;
    if (!vd || !st || !sel || !node || node.nodeType !== 3) return;
    const textBefore = (node.textContent ?? '').slice(0, sel.anchorOffset);
    const m = matchTrigger(textBefore);
    const start = m ? m.start : st.start;
    const end = sel.anchorOffset;
    const range = sel.getRangeAt(0);
    range.setStart(node, start);
    range.setEnd(node, end);
    range.deleteContents();
    sel.removeAllRanges();
    sel.addRange(range);

    const self = allNotesRef.current.find((x) => x.id === (currentNoteIdRef.current || noteId));
    const esc = (t: string) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
    const isCand = 'kind' in it;

    if (isCand && it.kind === 'file') {
      const f = it.file;
      const href = escapeLinkPath(self ? relativePath(self.path, f.path) : f.path);
      const isImg = /\.(png|jpe?g|gif|webp|svg)$/i.test(f.ext);
      if (isImg) {
        vd.insertValue(`![${esc(f.name)}](${esc(href)})&nbsp;`);
      } else {
        vd.insertValue(`<a href="${esc(href)}">${esc(f.name)}</a>&nbsp;`);
      }
    } else {
      const n = isCand && it.kind === 'note' ? it.note : (it as NoteRef);
      const href = escapeLinkPath(self ? relativePath(self.path, n.path) : n.path);
      vd.insertValue(`<a href="${esc(href)}">${esc(n.title)}</a>&nbsp;`);
    }

    setPicker(null);
    vd.focus();
  };

  // Vditor 的点击回调需要最新的闭包
  const syncPickerRef = useRef(syncPicker);
  syncPickerRef.current = syncPicker;
  const pickNoteRef = useRef(pickNote);
  pickNoteRef.current = pickNote;
  const linkClickRef = useRef<(el: HTMLElement) => void>(() => {});
  linkClickRef.current = (el) => {
    if (!el) return;
    // 兼容 WYSIWYG <a> 与 IR 模式下的 .vditor-ir__marker--link
    const href = el.getAttribute('href') || (el.textContent ?? '').trim();
    const self = allNotesRef.current.find((x) => x.id === (currentNoteIdRef.current || noteId));
    const fromPath = self?.path ?? '';
    const target = resolveHref(fromPath, href, allNotesRef.current);
    if (target) {
      void leaveThen(() => onOpenNoteRef.current(target.id));
      return;
    }
    const targetFile = resolveFileHref(fromPath, href, allFilesRef.current);
    if (targetFile) {
      VaultService.PreviewFile(targetFile.path).catch((err) => {
        console.warn('Preview file error:', err);
      });
      return;
    }
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(href)) {
      window.open(href);
      return;
    }
    if (href && !href.startsWith('#')) {
      setTitleError('笔记或文件不存在或已移动');
    }
  };

  // 被引用来源：从文件计算，保存/外部变更后刷新
  const loadBacklinks = useCallback(() => {
    if (isNewDraftRef.current || !currentNoteIdRef.current) {
      setBacklinks([]);
      return;
    }
    VaultService.GetNoteBacklinks(currentNoteIdRef.current)
      .then((r) => setBacklinks((r ?? []).filter((x): x is LinkSource => x !== null)))
      .catch(() => setBacklinks([]));
  }, []);
  useEffect(() => {
    loadBacklinks();
    const off = Events.On('vault:changed', loadBacklinks);
    return () => {
      off();
    };
  }, [loadBacklinks]);

  useEffect(() => {
    const onSelectionChange = () => syncPickerRef.current();
    document.addEventListener('selectionchange', onSelectionChange);
    return () => document.removeEventListener('selectionchange', onSelectionChange);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 候选打开时在捕获阶段接管方向键/回车/Esc（组合输入期间不拦截）
  useEffect(() => {
    const root = vditorContainerRef.current;
    if (!root) return;
    const onKey = (e: KeyboardEvent) => {
      const st = pickerRef.current;
      if (!st) return;
      const items = filterCandidates(allNotesRef.current, allFilesRef.current, st.query);
      const used = pickerKey(
        e,
        e.isComposing || e.keyCode === 229,
        items.length,
        st.index,
        (i) => setPicker({ ...st, index: i }),
        () => pickNoteRef.current(items[st.index]),
        () => {
          pickerDismissedRef.current = st.start;
          setPicker(null);
        }
      );
      if (used) e.stopPropagation();
    };
    root.addEventListener('keydown', onKey, true);
    return () => root.removeEventListener('keydown', onKey, true);
  }, [loadingNote]);

  // Copy draft to clipboard (should-fix 3)
  const handleCopyDraft = async () => {
    const currentTitle = editTitleRef.current;
    const currentBody = isAudioTranscriptNote(initialNoteRef.current)
      ? (initialNoteRef.current?.body ?? '')
      : (vditorRef.current ? vditorRef.current.getValue() : '');
    const draftText = currentTitle ? `# ${currentTitle}\n\n${currentBody}` : currentBody;
    try {
      await navigator.clipboard.writeText(draftText);
      setCopiedDraft(true);
      setTimeout(() => setCopiedDraft(false), 2500);
    } catch (err) {
      console.error('Failed to copy draft to clipboard:', err);
    }
  };

  // Reload handler (discard local changes and reload from disk)
  const handleConfirmReload = async () => {
    setShowReloadConfirm(false);
    if (isNewDraftRef.current) {
      setEditTitle('');
      editTitleRef.current = '';
      setEditTags('');
      editTagsRef.current = '';
      if (vditorRef.current) vditorRef.current.setValue('');
      hasConflictRef.current = false;
      setConflictError(null);
      setSaveStatus('saved');
      return;
    }
    try {
      const diskNote = await VaultService.GetNote(currentNoteIdRef.current);
      if (!diskNote) return;

      setEditTitle(diskNote.title);
      editTitleRef.current = diskNote.title;
      const tagsStr = (diskNote.tags ?? []).join(', ');
      setEditTags(tagsStr);
      editTagsRef.current = tagsStr;
      setTitleError(null);

      const body = diskNote.body ?? '';
      if (vditorRef.current) {
        vditorRef.current.setValue(body);
      }

      lastSavedStateRef.current = {
        title: diskNote.title,
        tags: diskNote.tags ?? [],
        body,
      };

      hasConflictRef.current = false;
      setConflictError(null);
      setSaveStatus('saved');
      onNoteUpdatedRef.current();
    } catch (err: any) {
      console.error('Failed to reload note:', err);
      setConflictError(`重新加载失败: ${err?.message || err}`);
    }
  };

  // Abandon changes and return to list
  const handleAbandonAndReturn = () => {
    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = null;
    }
    hasConflictRef.current = false;
    const go = pendingGoRef.current ?? onBack;
    pendingGoRef.current = null;
    go();
  };

  if (loadingNote) {
    return (
      <div className="flex items-center justify-center py-24 text-xs text-stone-400">
        <Loader2 className="w-5 h-5 animate-spin mr-2 text-emerald-600" />
        <span>加载笔记中...</span>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="p-6 max-w-xl mx-auto space-y-4">
        <div className="p-3.5 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center space-x-2">
          <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
          <span>加载笔记失败: {loadError}</span>
        </div>
        <button
          type="button"
          onClick={onBack}
          className="flex items-center space-x-1 px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 transition"
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>返回笔记列表</span>
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full max-w-3xl mx-auto p-6 space-y-2">
      {/* Top Header / Status Toolbar */}
      <div className="flex items-center justify-between pb-1 shrink-0 drag-region">
        <button
          type="button"
          onClick={handleBackClick}
          className="no-drag-region flex items-center space-x-1.5 px-2 py-1 -ml-2 rounded-md text-xs font-medium text-stone-500 hover:text-stone-800 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 transition shrink-0"
          title={`${backLabel}（将自动保存未提交改动）`}
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>{backLabel}</span>
        </button>

        {/* Status Indicator: 仅在保存中或保存失败/冲突时提示，保存成功不打扰 */}
        <div className="no-drag-region flex items-center space-x-2 text-xs shrink-0 min-h-[20px]">
          {saveStatus === 'saving' && (
            <span className="text-stone-400 flex items-center space-x-1.5">
              <Loader2 className="w-3 h-3 animate-spin text-emerald-600" />
              <span>保存中...</span>
            </span>
          )}
          {saveStatus === 'failed' && (
            <span className="text-rose-600 dark:text-rose-400 font-medium flex items-center space-x-1.5" title={saveError || '保存失败'}>
              <AlertCircle className="w-3.5 h-3.5 text-rose-600 shrink-0" />
              <span>保存失败</span>
            </span>
          )}
          {saveStatus === 'conflict' && (
            <span className="text-rose-600 dark:text-rose-400 font-semibold flex items-center space-x-1.5">
              <AlertCircle className="w-3.5 h-3.5 text-rose-600 shrink-0" />
              <span>保存冲突</span>
            </span>
          )}
        </div>
      </div>

      {/* Conflict Warning Banner (Stops auto-save) */}
      {(hasConflictRef.current || conflictError) && (
        <div className="p-3.5 rounded-xl border border-amber-300 dark:border-amber-800/80 bg-amber-50 dark:bg-amber-950/40 text-amber-900 dark:text-amber-200 text-xs flex items-center justify-between gap-3 shadow-xs shrink-0">
          <div className="flex items-center space-x-2.5 min-w-0">
            <AlertCircle className="w-4 h-4 text-amber-600 shrink-0" />
            <span className="font-medium">
              {conflictError ||
                '文件已被外部修改（保存冲突）。自动保存已停止，当前本地草稿尚未写盘。为防内容丢失，建议先复制草稿到剪贴板后再重新加载或返回。'}
            </span>
          </div>
          <div className="flex items-center space-x-2 shrink-0">
            <button
              type="button"
              onClick={handleCopyDraft}
              className="flex items-center space-x-1 px-3 py-1 rounded-md bg-stone-700 hover:bg-stone-800 text-white text-xs font-medium transition shadow-2xs"
              title="将当前编辑器中的草稿（标题与正文）复制到剪贴板"
            >
              {copiedDraft ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
              <span>{copiedDraft ? '已复制草稿' : '复制草稿到剪贴板'}</span>
            </button>
            <button
              type="button"
              onClick={() => setShowReloadConfirm(true)}
              className="flex items-center space-x-1 px-3 py-1 rounded-md bg-amber-600 hover:bg-amber-700 text-white text-xs font-medium transition shadow-2xs"
            >
              <RefreshCw className="w-3 h-3" />
              <span>重新加载（丢弃本地改动）</span>
            </button>
            <button
              type="button"
              onClick={handleAbandonAndReturn}
              className="px-2.5 py-1 rounded-md border border-amber-300 dark:border-amber-700 hover:bg-amber-100 dark:hover:bg-amber-900/40 text-xs transition"
            >
              放弃保存返回
            </button>
          </div>
        </div>
      )}

      {/* Document Header: Title & Tags */}
      <div className="pt-2 pb-1 space-y-2 shrink-0">
        <input
          ref={titleInputRef}
          type="text"
          value={editTitle}
          onChange={(e) => handleTitleChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              vditorRef.current?.focus();
            }
          }}
          placeholder="无标题笔记"
          className="w-full text-2xl font-bold bg-transparent text-stone-900 dark:text-stone-100 placeholder-stone-300 dark:placeholder-stone-700 focus:outline-hidden border-none p-0 leading-tight tracking-tight"
        />

        {titleError && (
          <div className="text-[11px] text-rose-600 dark:text-rose-400 font-medium">
            {titleError}
          </div>
        )}

        {/* Lightweight Tag Chips / Inline Edit */}
        <div>
          {isEditingTags ? (
            <div className="flex items-center gap-2">
              <input
                ref={tagsInputRef}
                type="text"
                autoFocus
                value={editTags}
                onChange={(e) => handleTagsChange(e.target.value)}
                onBlur={() => setIsEditingTags(false)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === 'Escape') {
                    setIsEditingTags(false);
                  }
                }}
                placeholder="输入标签，用逗号分隔（如：架构设计, 医疗数仓）"
                className="text-xs px-2.5 py-1 rounded-md border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 text-stone-800 dark:text-stone-200 placeholder-stone-400 focus:outline-hidden focus:ring-1 focus:ring-emerald-600 w-72 shadow-2xs"
              />
              <button
                type="button"
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => setIsEditingTags(false)}
                className="text-xs px-2 py-1 rounded-md text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                完成
              </button>
            </div>
          ) : (
            <div className="flex flex-wrap items-center gap-1.5">
              {parseTags(editTags).map((tag) => (
                <span
                  key={tag}
                  onClick={() => setIsEditingTags(true)}
                  className="inline-flex items-center text-xs px-2 py-0.5 rounded-md bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300 font-mono hover:bg-stone-200/70 dark:hover:bg-stone-700/60 cursor-pointer transition select-none"
                  title="点击编辑标签"
                >
                  #{tag}
                </span>
              ))}
              <button
                type="button"
                onClick={() => setIsEditingTags(true)}
                className="inline-flex items-center text-xs px-2 py-0.5 rounded-md text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/60 transition cursor-pointer select-none"
                title="编辑标签"
              >
                <Plus className="w-3 h-3 mr-0.5" />
                <span>{parseTags(editTags).length === 0 ? '添加标签' : '标签'}</span>
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Audio Player and Transcript Viewer for audio transcript notes, or Vditor for ordinary notes */}
      {isAudioTranscriptNote(initialNote) ? (
        <div className="flex-1 min-h-0 flex flex-col space-y-3 overflow-hidden">
          <AudioPlayer
            noteId={currentNoteIdRef.current || noteId}
            audioFile={initialNote.audio_file}
            taskStatus={asrStatus}
            onSeekCommitted={(timeMs) => transcriptViewerRef.current?.scrollToTime(timeMs)}
            onRetranscribe={handleRetranscribe}
            audioRef={audioElRef}
            isTranscribing={
              asrStatus?.state === ASRTaskState.StateUploading ||
              asrStatus?.state === ASRTaskState.StateTranscribing ||
              asrStatus?.state === ASRTaskState.StateWriting
            }
            hasTranscriptBody={Boolean(initialNote.body && initialNote.body.trim().length > 0)}
          />
          <div className="flex-1 min-h-0 overflow-y-auto">
            <TranscriptViewer
              ref={transcriptViewerRef}
              body={initialNote.body || ''}
              isTranscribing={
                asrStatus?.state === ASRTaskState.StateUploading ||
                asrStatus?.state === ASRTaskState.StateTranscribing ||
                asrStatus?.state === ASRTaskState.StateWriting
              }
              onJumpToTime={(timeMs) => {
                if (audioElRef.current) {
                  audioElRef.current.currentTime = timeMs / 1000;
                  audioElRef.current.play().catch(() => {});
                }
              }}
            />
          </div>
        </div>
      ) : (
        <div
          ref={vditorContainerRef}
          className="vditor-editor-wrapper flex-1 min-h-0 overflow-hidden border-none outline-hidden bg-transparent"
          style={{ border: 'none', outline: 'none' }}
          onDragOver={(e) => {
            if (e.dataTransfer.types.includes('Files')) {
              e.preventDefault();
            }
          }}
          onDrop={async (e) => {
            if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
              e.preventDefault();
              const vd = vditorRef.current;
              if (!vd) return;
              const self = allNotesRef.current.find((x) => x.id === (currentNoteIdRef.current || noteId));
              const fromPath = self?.path ?? 'notes/untitled.md';
              for (let i = 0; i < e.dataTransfer.files.length; i++) {
                const file = e.dataTransfer.files[i];
                try {
                  let imported: FileRef | null = null;
                  if ((file as any).path) {
                    imported = await VaultService.ImportFile((file as any).path);
                  } else {
                    const b64 = await new Promise<string>((resolve, reject) => {
                      const reader = new FileReader();
                      reader.onload = () => resolve(reader.result as string);
                      reader.onerror = reject;
                      reader.readAsDataURL(file);
                    });
                    imported = await VaultService.ImportFileData(file.name, b64);
                  }
                  if (imported) {
                    const href = escapeLinkPath(relativePath(fromPath, imported.path));
                    const isImg = /\.(png|jpe?g|gif|webp|svg)$/i.test(imported.ext);
                    const esc = (t: string) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
                    if (isImg) {
                      vd.insertValue(`![${esc(imported.name)}](${esc(href)}) `);
                    } else {
                      vd.insertValue(`[${esc(imported.name)}](${esc(href)}) `);
                    }
                  }
                } catch (err) {
                  console.error('Failed to import dropped file in note:', err);
                }
              }
            }
          }}
          onClick={(e) => {
            const target = e.target as HTMLElement;
            if (
              target === vditorContainerRef.current ||
              target.classList?.contains('vditor') ||
              target.classList?.contains('vditor-content') ||
              target.classList?.contains('vditor-ir')
            ) {
              vditorRef.current?.focus();
            }
          }}
        />
      )}

      {picker && (
        <NotePicker
          items={filterCandidates(allNotes, allFiles, picker.query)}
          allNotes={allNotes}
          index={picker.index}
          left={picker.left}
          top={picker.top}
          bottom={picker.bottom}
          onPick={pickNote}
          onHover={(i) => setPicker({ ...picker, index: i })}
        />
      )}

      {/* 被引用来源：默认折叠，无来源时隐藏 */}
      {backlinks.length > 0 && (
        <div className="shrink-0 text-xs">
          <button
            type="button"
            aria-expanded={backlinksOpen}
            onClick={() => setBacklinksOpen((o) => !o)}
            className="px-1 py-1 text-stone-500 hover:text-stone-700 dark:hover:text-stone-300"
          >
            {backlinksOpen ? '▾' : '▸'} 被引用 · {backlinks.length}
          </button>
          {backlinksOpen && (
            <ul className="max-h-32 overflow-y-auto pl-4 space-y-0.5">
              {backlinks.map((b) => {
                const dup = backlinks.filter((x) => x.title === b.title).length > 1;
                return (
                  <li key={`${b.type}:${b.id}`}>
                    <button
                      type="button"
                      onClick={() => void leaveThen(() => (b.type === EntityType.EntityTypeTask ? onOpenTaskRef.current?.(b.id) : onOpenNoteRef.current(b.id)))}
                      className="text-emerald-700 dark:text-emerald-400 hover:underline"
                    >
                      {b.type === EntityType.EntityTypeTask ? '任务 · ' : ''}
                      {b.title}
                    </button>
                    {dup && <span className="ml-1.5 text-[10px] text-stone-400">{b.path}</span>}
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}

      {/* Confirmation Modal for Discarding Local Changes on Reload */}
      {showReloadConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-amber-100 dark:bg-amber-950/60 text-amber-600 shrink-0">
                <AlertCircle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  确认重新加载？
                </h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  重新加载将从磁盘读取最新的笔记内容，您当前在编辑器中未保存的本地修改将被全部丢弃。
                </p>
              </div>
            </div>
            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => setShowReloadConfirm(false)}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                取消
              </button>
              <button
                type="button"
                onClick={handleConfirmReload}
                className="px-3 py-1.5 rounded-md bg-amber-600 hover:bg-amber-700 text-white text-xs font-medium transition shadow-xs"
              >
                确认重新加载
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirmation Modal for Leaving During Conflict */}
      {showLeaveConflictConfirm && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 shrink-0">
                <AlertCircle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  存在未解决冲突
                </h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  当前笔记存在外部文件修改冲突。直接返回列表将放弃本地未保存的内容。确认离开吗？
                </p>
              </div>
            </div>
            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => {
                  setShowLeaveConflictConfirm(false);
                  pendingGoRef.current = null;
                  const resolve = leavePromptResolverRef.current;
                  leavePromptResolverRef.current = null;
                  resolve?.(false);
                }}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                继续编辑
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowLeaveConflictConfirm(false);
                  handleAbandonAndReturn();
                  const resolve = leavePromptResolverRef.current;
                  leavePromptResolverRef.current = null;
                  resolve?.(true);
                }}
                className="px-3 py-1.5 rounded-md bg-rose-600 hover:bg-rose-700 text-white text-xs font-medium transition shadow-xs"
              >
                放弃修改并离开
              </button>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* Confirmation Modal for Save Failure on Exit (must-fix 3) */}
      {showSaveFailedConfirm && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 shrink-0">
                <AlertCircle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  保存未成功
                </h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  当前笔记未能成功保存到磁盘（可能标题为空或写入异常）。直接返回将丢弃未保存的修改，是否确定离开？
                </p>
              </div>
            </div>
            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => {
                  setShowSaveFailedConfirm(false);
                  pendingGoRef.current = null;
                  const resolve = leavePromptResolverRef.current;
                  leavePromptResolverRef.current = null;
                  resolve?.(false);
                }}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
              >
                留在页面
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowSaveFailedConfirm(false);
                  if (debounceTimerRef.current) {
                    window.clearTimeout(debounceTimerRef.current);
                    debounceTimerRef.current = null;
                  }
                  const go = pendingGoRef.current ?? onBack;
                  pendingGoRef.current = null;
                  go();
                  const resolve = leavePromptResolverRef.current;
                  leavePromptResolverRef.current = null;
                  resolve?.(true);
                }}
                className="px-3 py-1.5 rounded-md bg-rose-600 hover:bg-rose-700 text-white text-xs font-medium transition shadow-xs"
              >
                丢弃并返回
              </button>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* Confirmation Modal for Leaving Empty-Title Draft with Content */}
      {showDraftNoTitleConfirm && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-amber-100 dark:bg-amber-950/60 text-amber-600 shrink-0">
                <AlertCircle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  草稿未设置标题
                </h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  当前草稿尚未填写标题，无法写入文件。如果现在离开，您刚刚输入的内容将被丢弃。
                </p>
              </div>
            </div>
            <div className="flex items-center justify-between pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={handleCopyDraft}
                className="flex items-center space-x-1 px-2.5 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition"
                title="将当前草稿复制到剪贴板"
              >
                {copiedDraft ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
                <span>{copiedDraft ? '已复制' : '复制草稿'}</span>
              </button>
              <div className="flex items-center space-x-2">
                <button
                  type="button"
                  onClick={() => {
                    setShowDraftNoTitleConfirm(false);
                    pendingGoRef.current = null;
                    const resolve = leavePromptResolverRef.current;
                    leavePromptResolverRef.current = null;
                    resolve?.(false);
                  }}
                  className="px-3 py-1.5 rounded-md text-xs font-medium bg-emerald-700 hover:bg-emerald-800 text-white transition shadow-xs"
                >
                  继续编辑
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setShowDraftNoTitleConfirm(false);
                    if (debounceTimerRef.current) {
                      window.clearTimeout(debounceTimerRef.current);
                      debounceTimerRef.current = null;
                    }
                    const go = pendingGoRef.current ?? onBack;
                    pendingGoRef.current = null;
                    go();
                    const resolve = leavePromptResolverRef.current;
                    leavePromptResolverRef.current = null;
                    resolve?.(true);
                  }}
                  className="px-2.5 py-1.5 rounded-md border border-stone-200 dark:border-stone-700 text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 text-xs transition"
                >
                  放弃草稿
                </button>
              </div>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* Confirmation Modal for Replacing Transcript */}
      {showReplaceConfirm && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-emerald-100 dark:bg-emerald-950/60 text-emerald-600 shrink-0">
                <RefreshCw className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  发现新转写结果
                </h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  当前音频已生成新的逐字稿内容。您可以选择替换原逐字稿，或者保留原稿（保留原稿将放弃新生成的逐字稿）。
                </p>
                {replaceError && (
                  <p className="text-xs text-rose-600 dark:text-rose-400 font-medium pt-1">
                    {replaceError}
                  </p>
                )}
              </div>
            </div>
            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={handleDiscardCandidate}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition cursor-pointer"
              >
                保留原稿
              </button>
              <button
                type="button"
                onClick={handleConfirmReplace}
                className="px-3 py-1.5 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition shadow-xs cursor-pointer"
              >
                替换逐字稿
              </button>
            </div>
          </div>
        </div>,
        document.body
      )}
    </div>
  );
}

export function NotesView({
  vaultStatus,
  onSelectVault,
  onRescanVault,
  vaultBusy = false,
  focusNoteId,
  onClearFocusNote,
  returnToTask,
  onOpenTask,
  onEditingChange,
  leaveGuardRef,
  onOpenSettings,
}: NotesViewProps) {
  const [notes, setNotes] = useState<Note[]>([]);
  const [loading, setLoading] = useState(false);
  const [listError, setListError] = useState<string | null>(null);
  const [selectedNoteId, setSelectedNoteId] = useState<string | null>(null);
  const [isNewDraft, setIsNewDraft] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  // 经笔记链接/被引用来源依次打开的笔记栈，「返回」按栈回到上一篇
  const [trail, setTrail] = useState<string[]>([]);

  // Split-button / dropdown menu & audio note creation states
  const [createMenuOpen, setCreateMenuOpen] = useState(false);
  const [showMissingKeyModal, setShowMissingKeyModal] = useState(false);
  const [creatingAudioNote, setCreatingAudioNote] = useState(false);
  const [createAudioNoteError, setCreateAudioNoteError] = useState<string | null>(null);
  const createMenuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!createMenuOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (createMenuRef.current && !createMenuRef.current.contains(e.target as Node)) {
        setCreateMenuOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [createMenuOpen]);

  const handleStartCreateAudioNote = async () => {
    setCreateAudioNoteError(null);
    try {
      const cfg = await VaultService.GetASRConfigStatus();
      if (!cfg.configured) {
        setShowMissingKeyModal(true);
        return;
      }
      const audioPath = await VaultService.SelectAudioFile();
      if (!audioPath) {
        return;
      }
      setCreatingAudioNote(true);
      const created = await VaultService.CreateAudioNote(audioPath);
      if (created) {
        loadNotes();
        setTrail([]);
        setEditorKey(created.id);
        setSelectedNoteId(created.id);
        setIsNewDraft(false);
      }
    } catch (err: any) {
      console.error('CreateAudioNote failed:', err);
      setCreateAudioNoteError(err?.message || String(err));
    } finally {
      setCreatingAudioNote(false);
    }
  };

  useEffect(() => {
    onEditingChange?.(selectedNoteId !== null);
  }, [selectedNoteId, onEditingChange]);

  // Consume focusNoteId from parent navigation (one-time consumption)
  useEffect(() => {
    if (focusNoteId) {
      setEditorKey(focusNoteId);
      setSelectedNoteId(focusNoteId);
      setIsNewDraft(false);
      setTrail([]);
      onClearFocusNote?.();
    }
  }, [focusNoteId, onClearFocusNote]);

  // When vault path changes, reset active note & trail
  const currentPathRef = useRef(vaultStatus?.path);
  useEffect(() => {
    if (currentPathRef.current !== vaultStatus?.path) {
      currentPathRef.current = vaultStatus?.path;
      setSelectedNoteId(null);
      setIsNewDraft(false);
      setTrail([]);
      setEditorKey('');
    }
  }, [vaultStatus?.path]);

  // Scroll position preservation
  const rootRef = useRef<HTMLDivElement | null>(null);
  const scrollTopRef = useRef<number>(0);

  // Load notes
  const loadNotes = useCallback(async () => {
    if (!vaultStatus?.open) {
      setNotes([]);
      setListError(null);
      return;
    }
    setLoading(true);
    setListError(null);
    try {
      const result = await VaultService.ListNotes();
      const validNotes = (result ?? []).filter((n): n is Note => n !== null);
      setNotes(validNotes);
    } catch (err: any) {
      console.error('Failed to list notes:', err);
      setListError(err?.message || String(err));
    } finally {
      setLoading(false);
    }
  }, [vaultStatus?.open, vaultStatus?.path]);

  useEffect(() => {
    loadNotes();
  }, [loadNotes]);

  // Subscribe to external vault changes
  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', () => {
      loadNotes();
    });
    return () => {
      unsubscribe();
    };
  }, [loadNotes]);

  // Record scroll position while in list view
  useEffect(() => {
    if (selectedNoteId) return;
    const scrollContainer = rootRef.current?.closest('.overflow-y-auto') as HTMLElement | null;
    if (!scrollContainer) return;
    const handleScroll = () => {
      scrollTopRef.current = scrollContainer.scrollTop;
    };
    scrollContainer.addEventListener('scroll', handleScroll, { passive: true });
    return () => scrollContainer.removeEventListener('scroll', handleScroll);
  }, [selectedNoteId]);

  // Restore scroll position when returning to list view
  useEffect(() => {
    if (selectedNoteId === null) {
      const scrollContainer = rootRef.current?.closest('.overflow-y-auto') as HTMLElement | null;
      if (scrollContainer && scrollTopRef.current > 0) {
        requestAnimationFrame(() => {
          scrollContainer.scrollTop = scrollTopRef.current;
        });
      }
    }
  }, [selectedNoteId]);

  // Select note and record scroll position
  const handleSelectNote = (id: string) => {
    const scrollContainer = rootRef.current?.closest('.overflow-y-auto') as HTMLElement | null;
    if (scrollContainer) {
      scrollTopRef.current = scrollContainer.scrollTop;
      scrollContainer.scrollTop = 0;
    }
    setEditorKey(id);
    setSelectedNoteId(id);
    setIsNewDraft(false);
  };

  // Start creating new note directly in writing area
  const handleStartCreateNote = () => {
    const scrollContainer = rootRef.current?.closest('.overflow-y-auto') as HTMLElement | null;
    if (scrollContainer) {
      scrollTopRef.current = scrollContainer.scrollTop;
      scrollContainer.scrollTop = 0;
    }
    setTrail([]);
    setEditorKey('draft-' + Date.now());
    setSelectedNoteId('__draft__');
    setIsNewDraft(true);
  };

  // Unconfigured Vault state
  if (!vaultStatus?.configured) {
    return (
      <div className="py-16 text-center space-y-4 max-w-md mx-auto">
        <FolderOpen className="w-12 h-12 text-emerald-600 mx-auto opacity-75" />
        <h2 className="text-base font-semibold text-stone-800 dark:text-stone-200">尚未配置 Vault 目录</h2>
        <p className="text-xs text-stone-500 leading-relaxed">
          Pata 以本地纯文本 Markdown 作为唯一数据真相源（Local First）。请先选择一个本地目录。
        </p>
        <button
          onClick={onSelectVault}
          disabled={vaultBusy}
          className="mx-auto flex items-center space-x-1.5 px-4 py-2 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition disabled:opacity-50 shadow-xs"
        >
          <FolderOpen className="w-3.5 h-3.5" />
          <span>选择 Vault 目录</span>
        </button>
      </div>
    );
  }

  // Configured but unopened vault state
  if (!vaultStatus.open) {
    return (
      <div className="p-5 max-w-lg mx-auto rounded-xl border border-amber-200 dark:border-amber-900/60 bg-amber-50/70 dark:bg-amber-950/30 text-xs space-y-3">
        <div className="font-medium text-amber-900 dark:text-amber-200">Vault 打开异常</div>
        <p className="text-stone-600 dark:text-stone-400">
          无法加载目录：<code className="font-mono text-[11px] text-stone-800 dark:text-stone-200">{vaultStatus.path}</code>
        </p>
        <button
          onClick={onSelectVault}
          disabled={vaultBusy}
          className="px-3.5 py-1.5 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white font-medium transition disabled:opacity-50"
        >
          重新选择目录
        </button>
      </div>
    );
  }

  const handleNoteCreated = useCallback((newId: string) => {
    setSelectedNoteId(newId);
    setIsNewDraft(false);
    loadNotes();
  }, [loadNotes]);

  const handleBack = useCallback(() => {
    if (trail.length) {
      const prevId = trail[trail.length - 1];
      setEditorKey(prevId);
      setSelectedNoteId(prevId);
      setIsNewDraft(false);
      setTrail((prev) => prev.slice(0, -1));
    } else if (returnToTask) returnToTask.go();
    else {
      setSelectedNoteId(null);
      setIsNewDraft(false);
      setEditorKey('');
    }
  }, [trail, returnToTask]);

  const handleOpenNote = useCallback((id: string) => {
    setTrail((prev) => (selectedNoteId ? [...prev, selectedNoteId] : prev));
    setEditorKey(id);
    setSelectedNoteId(id);
    setIsNewDraft(false);
  }, [selectedNoteId]);

  // Editor View (occupies full main content area)
  if (selectedNoteId) {
    return (
      <NoteEditor
        key={editorKey}
        noteId={selectedNoteId}
        isNew={isNewDraft}
        onBack={handleBack}
        backLabel={trail.length ? '返回上一篇' : returnToTask ? returnToTask.label : '笔记列表'}
        onOpenNote={handleOpenNote}
        onOpenTask={onOpenTask}
        onNoteUpdated={loadNotes}
        onNoteCreated={handleNoteCreated}
        leaveGuardRef={leaveGuardRef}
        onOpenSettings={onOpenSettings}
      />
    );
  }

  // Single-column Card List View
  return (
    <div ref={rootRef} className="max-w-3xl mx-auto space-y-5">
      {/* Top Action Bar */}
      <div className="flex items-center justify-between pt-1">
        <div className="flex items-center space-x-2">
          <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
            全部笔记
          </h2>
          <span className="text-xs font-mono text-stone-400">
            {notes.length}
          </span>
          {loading && <span className="text-[11px] text-stone-400">加载中...</span>}
        </div>

        {/* Split Button: New Note / New Audio Note */}
        <div className="relative inline-flex items-center rounded-lg shadow-2xs" ref={createMenuRef}>
          <button
            type="button"
            onClick={handleStartCreateNote}
            className="flex items-center space-x-1 px-3 py-1.5 rounded-l-lg bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition cursor-pointer"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>新建笔记</span>
          </button>
          <button
            type="button"
            onClick={() => setCreateMenuOpen((v) => !v)}
            className="px-1.5 py-1.5 rounded-r-lg bg-emerald-700 hover:bg-emerald-800 border-l border-emerald-600 text-white text-xs transition cursor-pointer"
            title="更多新建选项"
          >
            <ChevronDown className="w-3.5 h-3.5" />
          </button>
          {createMenuOpen && (
            <div className="absolute right-0 top-full mt-1 w-44 rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 shadow-lg py-1 z-30">
              <button
                type="button"
                onClick={() => {
                  setCreateMenuOpen(false);
                  handleStartCreateNote();
                }}
                className="w-full flex items-center space-x-2 px-3 py-2 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer"
              >
                <FileText className="w-3.5 h-3.5 text-stone-400" />
                <span>新建空白笔记</span>
              </button>
              <button
                type="button"
                onClick={() => {
                  setCreateMenuOpen(false);
                  handleStartCreateAudioNote();
                }}
                className="w-full flex items-center space-x-2 px-3 py-2 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer"
              >
                <Volume2 className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400" />
                <span>从音频创建逐字稿</span>
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Error Feedback Banner */}
      {listError && (
        <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center space-x-2">
          <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
          <span>加载笔记列表失败: {listError}</span>
        </div>
      )}

      {/* Audio Note Creation Error Banner */}
      {createAudioNoteError && (
        <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center justify-between space-x-2">
          <div className="flex items-center space-x-2 min-w-0">
            <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
            <span className="truncate">导入音频创建笔记失败: {createAudioNoteError}</span>
          </div>
          <button
            type="button"
            onClick={() => setCreateAudioNoteError(null)}
            className="text-stone-400 hover:text-stone-600 text-xs shrink-0 cursor-pointer"
          >
            关闭
          </button>
        </div>
      )}

      {/* Single-column Card Stack */}
      {notes.length === 0 ? (
        <div className="py-16 text-center rounded-xl border border-dashed border-stone-200 dark:border-stone-800 bg-white/40 dark:bg-stone-950/20 text-xs text-stone-400 space-y-2">
          <FileText className="w-8 h-8 text-stone-300 dark:text-stone-700 mx-auto" />
          {loading ? (
            <div className="font-medium text-stone-600 dark:text-stone-300">
              加载中...
            </div>
          ) : (
            <>
              <div className="font-medium text-stone-600 dark:text-stone-300">
                Vault 中暂无笔记
              </div>
              <div className="text-[11px] text-stone-400 max-w-xs mx-auto">
                写下第一篇长文或记录吧，也可以直接从 MP3 音频导入生成逐字稿
              </div>
              <div className="flex items-center justify-center space-x-2 pt-2">
                <button
                  type="button"
                  onClick={handleStartCreateNote}
                  className="inline-flex items-center space-x-1 px-3 py-1.5 rounded-lg bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition shadow-2xs cursor-pointer"
                >
                  <Plus className="w-3 h-3" />
                  <span>新建空白笔记</span>
                </button>
                <button
                  type="button"
                  onClick={handleStartCreateAudioNote}
                  className="inline-flex items-center space-x-1 px-3 py-1.5 rounded-lg border border-stone-200 dark:border-stone-700 bg-white dark:bg-stone-900 text-stone-700 dark:text-stone-300 hover:bg-stone-50 dark:hover:bg-stone-800 text-xs font-medium transition shadow-2xs cursor-pointer"
                >
                  <Volume2 className="w-3 h-3 text-emerald-600 dark:text-emerald-400" />
                  <span>从音频创建 (MP3)</span>
                </button>
              </div>
            </>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          {notes.map((n) => {
            const excerpt = getNoteExcerpt(n.title, n.body);
            const relativeTime = formatRelativeTime(n.updated_at);

            return (
              <div
                key={n.id}
                onClick={() => handleSelectNote(n.id)}
                className="group p-4 rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 hover:border-emerald-500/60 dark:hover:border-emerald-600/60 hover:shadow-2xs transition cursor-pointer select-none space-y-2"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center space-x-2 min-w-0">
                    {isAudioTranscriptNote(n) && (
                      <span className="inline-flex items-center space-x-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-emerald-100 dark:bg-emerald-950/70 text-emerald-800 dark:text-emerald-300 shrink-0">
                        <Volume2 className="w-2.5 h-2.5" />
                        <span>逐字稿</span>
                      </span>
                    )}
                    <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100 group-hover:text-emerald-800 dark:group-hover:text-emerald-400 transition truncate">
                      {n.title}
                    </h3>
                  </div>
                  <span className="font-mono text-[11px] text-stone-400 shrink-0">
                    {relativeTime}
                  </span>
                </div>

                {excerpt ? (
                  <p className="text-xs text-stone-500 dark:text-stone-400 line-clamp-2 leading-relaxed break-words font-sans">
                    {excerpt}
                  </p>
                ) : (
                  <p className="text-xs text-stone-400/80 dark:text-stone-600 italic">
                    暂无正文描述
                  </p>
                )}

                {n.tags && n.tags.length > 0 && (
                  <div className="flex flex-wrap items-center gap-1.5 pt-1">
                    {n.tags.map((tag) => (
                      <span
                        key={tag}
                        className="inline-flex items-center text-[10px] px-1.5 py-0.2 rounded bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-400 font-mono"
                      >
                        #{tag}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Missing Key Modal */}
      {showMissingKeyModal && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 p-5 shadow-xl space-y-4">
            <div className="flex items-start space-x-3">
              <div className="p-2 rounded-full bg-amber-100 dark:bg-amber-950/60 text-amber-600 shrink-0">
                <AlertCircle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  需配置语音转写 API Key
                </h3>
                <p className="text-xs text-stone-500 leading-relaxed">
                  音频逐字稿生成依赖阿里云百炼 DashScope 语音服务。请先在「设置 - 语音转写」中配置 API Key。
                </p>
              </div>
            </div>
            <div className="flex items-center justify-end space-x-2 pt-2 border-t border-stone-100 dark:border-stone-800">
              <button
                type="button"
                onClick={() => setShowMissingKeyModal(false)}
                className="px-3 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition cursor-pointer"
              >
                取消
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowMissingKeyModal(false);
                  onOpenSettings?.('transcription');
                }}
                className="px-3 py-1.5 rounded-md bg-emerald-700 hover:bg-emerald-800 text-white text-xs font-medium transition shadow-xs cursor-pointer"
              >
                前往设置
              </button>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* Creating Audio Note Loading Overlay */}
      {creatingAudioNote && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-xs p-4">
          <div className="rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 px-6 py-4 shadow-xl flex items-center space-x-3 text-xs font-medium text-stone-700 dark:text-stone-200">
            <Loader2 className="w-4 h-4 animate-spin text-emerald-600" />
            <span>正在导入音频并创建逐字稿笔记...</span>
          </div>
        </div>,
        document.body
      )}
    </div>
  );
}
