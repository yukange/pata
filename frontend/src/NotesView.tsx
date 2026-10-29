import { useState, useEffect, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Events } from '@wailsio/runtime';
import {
  FileText,
  UserRound,
  Bot,
  Plus,
  AlertCircle,
  FolderOpen,
  ArrowLeft,
  Loader2,
  Check,
  Copy,
  Volume2,
  ChevronDown,
  ChevronRight,
  MoreHorizontal,
  Trash2,
  PanelLeftOpen,
} from 'lucide-react';
import Vditor from 'vditor';
import * as VaultService from '../bindings/pata/internal/app/vaultservice';
import { VaultStatus, CreateNoteInput, UpdateNoteInput } from '../bindings/pata/internal/app/models';
import { Note, LinkSource, EntityType } from '../bindings/pata/internal/storage/markdown/models';
import { ASRTaskStatus, ASRTaskState } from '../bindings/pata/internal/asr/models';
import { Button } from './components/ui/button';
import { ConfirmDialog } from './components/ui/confirm-dialog';
import { AudioPlayer } from './AudioPlayer';
import { formatStatusAction } from './activityUtils';
import { TranscriptViewer, TranscriptViewerRef } from './TranscriptViewer';
import { TagChipEditor } from './TagChipEditor';
import { validateTag, hasTag, dedupeTags, sameTags, formatDraftText } from './tagUtils';
import { copyToClipboard } from './clipboardUtils';
import { matchesVaultEventType } from './vaultEvents';
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
  onDraftCheck?: (checker: () => boolean) => () => void;
  onOpenSettings?: (section?: 'appearance' | 'storage' | 'transcription') => void;
  tagNames?: string[];
  onVaultDataChanged?: () => void;
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
void getNoteExcerpt;

function getDraftExcerpt(body?: string): string {
  if (!body) return '';
  const lines = body.split(/\r?\n/);
  const textLines: string[] = [];
  for (const line of lines) {
    let cleaned = line
      .replace(/^#{1,6}\s+/, '')
      .replace(/^>\s+/, '')
      .replace(/^[-*+]\s+(\[[ xX]\]\s+)?/, '')
      .replace(/^\d+\.\s+/, '')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g, '$1')
      .replace(/[`*_~=]/g, '')
      .trim();
    if (cleaned) {
      textLines.push(cleaned);
      if (textLines.length >= 2) break;
    }
  }
  return textLines.join('\n');
}

const DEFAULT_NOTES_LIST_WIDTH = 280;
const MIN_NOTES_LIST_WIDTH = 240;
const MAX_NOTES_LIST_WIDTH = 400;
const WIDTH_STORAGE_KEY = 'pata_notes_list_width';
const COLLAPSED_STORAGE_KEY = 'pata_notes_list_collapsed';
const DRAFTS_COLLAPSED_KEY = 'pata_notes_drafts_collapsed';
const FORMAL_COLLAPSED_KEY = 'pata_notes_formal_collapsed';
const LAST_NOTE_ID_KEY = 'pata_last_selected_note_id';

function loadPersistedNumber(key: string, fallback: number, min: number, max: number): number {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const parsed = parseInt(raw, 10);
    if (isNaN(parsed)) return fallback;
    return Math.max(min, Math.min(max, parsed));
  } catch {
    return fallback;
  }
}

function loadPersistedBool(key: string, fallback: boolean): boolean {
  try {
    const raw = localStorage.getItem(key);
    if (raw === null) return fallback;
    return raw === 'true';
  } catch {
    return fallback;
  }
}

interface NoteEditorProps {
  noteId: string;
  isNew?: boolean;
  isDraftType?: boolean;
  listCollapsed?: boolean;
  onToggleListCollapse?: () => void;
  returnToTask?: { label: string; go: () => void } | null;
  onOpenNote: (id: string) => void;
  onOpenTask?: (id: string) => void;
  onNoteUpdated: (updatedNote?: Note) => void;
  onNoteCreated?: (newId: string, isDraft: boolean, createdNote?: Note) => void;
  onNoteConverted?: (id: string, convertedNote?: Note) => void;
  onDeleteCurrentNote?: (id: string) => void;
  leaveGuardRef?: React.MutableRefObject<(() => Promise<boolean>) | null>;
  onDraftCheck?: (checker: () => boolean) => () => void;
  onOpenSettings?: (section?: 'appearance' | 'storage' | 'transcription') => void;
  tagNames?: string[];
  onVaultDataChanged?: () => void;
}

function NoteEditor({
  noteId,
  isNew = false,
  isDraftType = false,
  listCollapsed = false,
  onToggleListCollapse,
  returnToTask,
  onOpenNote,
  onOpenTask,
  onNoteUpdated,
  onNoteCreated,
  onNoteConverted,
  onDeleteCurrentNote,
  leaveGuardRef,
  onDraftCheck,
  onOpenSettings,
  tagNames = [],
  onVaultDataChanged,
}: NoteEditorProps) {
  const [initialNote, setInitialNote] = useState<Note | null>(null);
  const initialNoteRef = useRef<Note | null>(initialNote);
  initialNoteRef.current = initialNote;
  const [loadingNote, setLoadingNote] = useState<boolean>(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // In-place naming state (草稿原地转为笔记)
  const [isNaming, setIsNaming] = useState<boolean>(false);

  // Audio transcript specific states
  const [asrStatus, setAsrStatus] = useState<ASRTaskStatus | null>(null);
  const audioElRef = useRef<HTMLAudioElement | null>(null);
  const transcriptViewerRef = useRef<TranscriptViewerRef | null>(null);
  const [showReplaceConfirm, setShowReplaceConfirm] = useState<boolean>(false);
  const [replaceError, setReplaceError] = useState<string | null>(null);

  const [editTitle, setEditTitle] = useState<string>('');
  const [editTags, setEditTags] = useState<string[]>([]);
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving' | 'unsaved' | 'failed' | 'conflict'>('saved');
  const saveStatusRef = useRef(saveStatus);
  saveStatusRef.current = saveStatus;
  const [saveError, setSaveError] = useState<string | null>(null);
  const [conflictError, setConflictError] = useState<string | null>(null);
  const [titleError, setTitleError] = useState<string | null>(null);

  const [showReloadConfirm, setShowReloadConfirm] = useState<boolean>(false);
  const [showLeaveConflictConfirm, setShowLeaveConflictConfirm] = useState<boolean>(false);
  const [showSaveFailedConfirm, setShowSaveFailedConfirm] = useState<boolean>(false);
  const [copiedDraft, setCopiedDraft] = useState<boolean>(false);
  const titleInputRef = useRef<HTMLInputElement | null>(null);

  const [moreMenuOpen, setMoreMenuOpen] = useState<boolean>(false);
  const moreMenuRef = useRef<HTMLDivElement | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState<boolean>(false);
  const [isDeleting, setIsDeleting] = useState<boolean>(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const toastTimerRef = useRef<number | null>(null);

  const showToast = useCallback((msg: string) => {
    if (toastTimerRef.current) {
      window.clearTimeout(toastTimerRef.current);
    }
    setToastMessage(msg);
    toastTimerRef.current = window.setTimeout(() => {
      setToastMessage(null);
      toastTimerRef.current = null;
    }, 2000);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) {
        window.clearTimeout(toastTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!moreMenuOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (moreMenuRef.current && !moreMenuRef.current.contains(e.target as Node)) {
        setMoreMenuOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [moreMenuOpen]);

  useEffect(() => {
    if (isNew && !isDraftType) {
      titleInputRef.current?.focus();
    }
  }, [isNew, isDraftType]);

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
  const inFlightSaveRef = useRef<{ title: string; tags: string[]; body: string } | null>(null);
  const debounceTimerRef = useRef<number | null>(null);
  const isDeletedRef = useRef<boolean>(false);
  const isUnmountedRef = useRef<boolean>(false);

  const editTitleRef = useRef<string>('');
  const editTagsRef = useRef<string[]>([]);
  const triggerDebouncedSaveRef = useRef<() => void>(() => {});
  const onNoteCreatedRef = useRef(onNoteCreated);
  onNoteCreatedRef.current = onNoteCreated;
  const onNoteUpdatedRef = useRef(onNoteUpdated);
  onNoteUpdatedRef.current = onNoteUpdated;
  const onNoteConvertedRef = useRef(onNoteConverted);
  onNoteConvertedRef.current = onNoteConverted;
  const onOpenNoteRef = useRef(onOpenNote);
  onOpenNoteRef.current = onOpenNote;
  const onOpenTaskRef = useRef(onOpenTask);
  onOpenTaskRef.current = onOpenTask;
  const onVaultDataChangedRef = useRef(onVaultDataChanged);
  onVaultDataChangedRef.current = onVaultDataChanged;

  const isDraftNote = isNewDraftRef.current ? isDraftType : Boolean(initialNote?.draft);

  const normalizeBody = (s: string) => s.replace(/\r\n/g, '\n').trimEnd();

  // Dirty check: comparison with last persisted state
  const isDirty = useCallback((currentTitle: string, currentTags: string[], currentBody: string): boolean => {
    if (isNewDraftRef.current) {
      if (isDraftType) {
        return !!currentBody.trim();
      }
      return !!currentTitle.trim() || !!currentBody || currentTags.length > 0;
    }
    if (!lastSavedStateRef.current) return false;
    const last = lastSavedStateRef.current;
    if (currentTitle.trim() !== last.title.trim()) return true;
    if (!isAudioTranscriptNote(initialNoteRef.current) && normalizeBody(currentBody) !== normalizeBody(last.body)) return true;
    if (currentTags.length !== last.tags.length) return true;
    for (let i = 0; i < currentTags.length; i++) {
      if (currentTags[i].trim().toLowerCase() !== last.tags[i]?.trim().toLowerCase()) return true;
    }
    return false;
  }, [isDraftType]);

  const isDirtyRef = useRef(isDirty);
  isDirtyRef.current = isDirty;
  const doSaveRef = useRef<() => Promise<boolean>>(() => Promise.resolve(false));

  const doSave = useCallback(async (force: boolean = false): Promise<boolean> => {
    if (isDeletedRef.current) {
      return false;
    }

    if (saveStatusRef.current === 'conflict' && !force) {
      return false;
    }

    if (!vditorRef.current && !isAudioTranscriptNote(initialNoteRef.current)) {
      return false;
    }

    const currentTitle = editTitleRef.current.trim();
    const currentBody = isAudioTranscriptNote(initialNoteRef.current)
      ? (initialNoteRef.current?.body ?? '')
      : (vditorRef.current ? vditorRef.current.getValue() : '');
    const currentTags = editTagsRef.current;

    // 新建分支保存
    if (isNewDraftRef.current) {
      if (isDraftType) {
        // 新建草稿：正文有内容才首次落盘
        if (!currentBody.trim()) {
          setSaveStatus('saved');
          return false;
        }
      } else {
        // 新建正式笔记：要求非空标题
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
      }

      if (inFlightSaveRef.current !== null) {
        return false;
      }

      inFlightSaveRef.current = {
        title: currentTitle,
        tags: isDraftType ? [] : currentTags,
        body: currentBody,
      };
      setSaveStatus('saving');
      let createdNote = false;

      try {
        const input: CreateNoteInput = {
          draft: isDraftType,
          title: currentTitle,
          tags: isDraftType ? [] : currentTags,
          body: currentBody,
        };

        const created = await VaultService.CreateNote(input);
        if (created) {
          isNewDraftRef.current = false;
          currentNoteIdRef.current = created.id;
          setInitialNote(created);
          lastSavedStateRef.current = {
            title: currentTitle,
            tags: isDraftType ? [] : currentTags,
            body: currentBody,
          };
          setConflictError(null);
          setSaveStatus('saved');
          setSaveError(null);
          onNoteCreatedRef.current?.(created.id, isDraftType, created);
          onNoteUpdatedRef.current(created);
          createdNote = true;
          // 仅在新建正式笔记且包含标签等必要元数据时刷新全局 Vault
          if (!isDraftType && currentTags.length > 0) {
            onVaultDataChangedRef.current?.();
          }
        }
        return createdNote;
      } catch (err: any) {
        console.error('CreateNote failed:', err);
        setSaveStatus('failed');
        setSaveError(err?.message || String(err));
        if (!isDraftType) {
          setTitleError(err?.message || String(err));
        }
        return false;
      } finally {
        inFlightSaveRef.current = null;
        if (createdNote && vditorRef.current) {
          const bodyNow = vditorRef.current.getValue();
          const titleNow = editTitleRef.current;
          const tagsNow = editTagsRef.current;
          if (isDirtyRef.current(titleNow, tagsNow, bodyNow) && saveStatusRef.current !== 'conflict') {
            triggerDebouncedSaveRef.current();
          }
        }
      }
    }

    // 既有笔记更新分支
    const currentIsDraft = Boolean(initialNoteRef.current?.draft);

    // 正在命名草稿 -> 转为正式笔记
    if (currentIsDraft && isNaming) {
      if (!currentTitle) {
        // 标题仍为空：维持草稿状态，不写 formal note，但可保存正文改动
        if (!isDirtyRef.current(currentTitle, currentTags, currentBody)) {
          return true;
        }
        if (inFlightSaveRef.current !== null) return false;
        inFlightSaveRef.current = {
          title: '',
          tags: [],
          body: currentBody,
        };
        setSaveStatus('saving');
        try {
          const input: UpdateNoteInput = {
            id: currentNoteIdRef.current,
            draft: true,
            title: '',
            tags: [],
            body: currentBody,
          };
          const updated = await VaultService.UpdateNote(input);
          if (updated) {
            setInitialNote(updated);
            lastSavedStateRef.current = {
              title: '',
              tags: [],
              body: currentBody,
            };
            setSaveStatus('saved');
            setSaveError(null);
            onNoteUpdatedRef.current(updated);
          }
          return true;
        } catch (err: any) {
          console.error('Save draft body failed:', err);
          setSaveStatus('failed');
          setSaveError(err?.message || String(err));
          return false;
        } finally {
          inFlightSaveRef.current = null;
        }
      }

      // 非空标题：转为正式笔记并更新元数据
      setTitleError(null);
      if (inFlightSaveRef.current !== null) return false;
      inFlightSaveRef.current = {
        title: currentTitle,
        tags: currentTags,
        body: currentBody,
      };
      setSaveStatus('saving');
      let converted = false;
      try {
        const fDraft = false;
        const input: UpdateNoteInput = {
          id: currentNoteIdRef.current,
          draft: fDraft,
          title: currentTitle,
          tags: currentTags,
          body: currentBody,
        };
        const updated = await VaultService.UpdateNote(input);
        if (updated) {
          setInitialNote(updated);
          setIsNaming(false);
          lastSavedStateRef.current = {
            title: currentTitle,
            tags: currentTags,
            body: currentBody,
          };
          setConflictError(null);
          setSaveStatus('saved');
          setSaveError(null);
          onNoteConvertedRef.current?.(updated.id, updated);
          onNoteUpdatedRef.current(updated);
          converted = true;
          // 草稿转为正式笔记属于元数据变更，刷新全局 Vault
          onVaultDataChangedRef.current?.();
        }
        return converted;
      } catch (err: any) {
        console.error('ConvertNote failed:', err);
        setSaveStatus('failed');
        setSaveError(err?.message || String(err));
        setTitleError(err?.message || String(err));
        return false;
      } finally {
        inFlightSaveRef.current = null;
      }
    }

    // 普通草稿保存：标题无要求
    if (currentIsDraft && !isNaming) {
      if (!isDirtyRef.current(currentTitle, currentTags, currentBody)) {
        setSaveStatus('saved');
        setSaveError(null);
        return true;
      }

      if (inFlightSaveRef.current !== null) return false;
      inFlightSaveRef.current = {
        title: '',
        tags: [],
        body: currentBody,
      };
      setSaveStatus('saving');
      let savedDraft = false;

      try {
        const input: UpdateNoteInput = {
          id: currentNoteIdRef.current,
          draft: true,
          title: '',
          tags: [],
          body: currentBody,
        };
        const updated = await VaultService.UpdateNote(input);
        if (updated) {
          setInitialNote(updated);
          lastSavedStateRef.current = {
            title: '',
            tags: [],
            body: currentBody,
          };
          setConflictError(null);
          setSaveStatus('saved');
          setSaveError(null);
          onNoteUpdatedRef.current(updated);
          savedDraft = true;
        }
        return savedDraft;
      } catch (err: any) {
        console.error('UpdateNote draft failed:', err);
        const errMsg = err?.message || String(err);
        const isConflict = errMsg.includes('conflict') || errMsg.includes('写入冲突');
        if (isConflict) {
          setSaveStatus('conflict');
          setConflictError('外部文件已更新（本地有未保存修改）');
          if (debounceTimerRef.current) {
            window.clearTimeout(debounceTimerRef.current);
            debounceTimerRef.current = null;
          }
        } else {
          setSaveStatus('failed');
          setSaveError(errMsg);
        }
        return false;
      } finally {
        inFlightSaveRef.current = null;
        if (savedDraft && vditorRef.current) {
          const bodyNow = vditorRef.current.getValue();
          if (isDirtyRef.current('', [], bodyNow) && saveStatusRef.current !== 'conflict') {
            triggerDebouncedSaveRef.current();
          }
        }
      }
    }

    // 正式笔记更新分支
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

    if (inFlightSaveRef.current !== null) {
      return false;
    }

    const prevTags = lastSavedStateRef.current?.tags ?? [];
    const tagsChanged = !sameTags(prevTags, currentTags);

    inFlightSaveRef.current = {
      title: currentTitle,
      tags: currentTags,
      body: currentBody,
    };
    setSaveStatus('saving');
    let saved = false;

    try {
      const fDraft = false;
      const input: UpdateNoteInput = {
        id: currentNoteIdRef.current,
        draft: fDraft,
        title: currentTitle,
        tags: currentTags,
        body: currentBody,
        force: force,
      };

      const updated = await VaultService.UpdateNote(input);
      if (updated) {
        setInitialNote(updated);
        lastSavedStateRef.current = {
          title: currentTitle,
          tags: currentTags,
          body: currentBody,
        };
        setConflictError(null);
        setSaveStatus('saved');
        setSaveError(null);
        onNoteUpdatedRef.current(updated);
        saved = true;
        // 仅在标签等必要元数据变更时刷新全局 Vault，普通正文保存不刷新
        if (tagsChanged) {
          onVaultDataChangedRef.current?.();
        }
      }
      return saved;
    } catch (err: any) {
      console.error('UpdateNote failed:', err);
      const errMsg = err?.message || String(err);
      const isConflict = errMsg.includes('conflict') || errMsg.includes('写入冲突');

      if (isConflict) {
        setSaveStatus('conflict');
        setConflictError('外部文件已更新（本地有未保存修改）');
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
      inFlightSaveRef.current = null;
      if (saved && (vditorRef.current || isAudioTranscriptNote(initialNoteRef.current))) {
        const bodyNow = vditorRef.current ? vditorRef.current.getValue() : (initialNoteRef.current?.body ?? '');
        const titleNow = editTitleRef.current;
        const tagsNow = editTagsRef.current;
        if (isDirtyRef.current(titleNow, tagsNow, bodyNow) && saveStatusRef.current !== 'conflict') {
          triggerDebouncedSaveRef.current();
        }
      }
    }
  }, [isDraftType, isNaming]);

  doSaveRef.current = doSave;

  // Debounced auto-save (0.5s)
  const triggerDebouncedSave = useCallback(() => {
    if (isDeletedRef.current || saveStatusRef.current === 'conflict') return;
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
      if (!isNewDraftRef.current && !initialNoteRef.current?.draft) {
        setTitleError('笔记标题不能为空');
      }
    } else {
      setTitleError(null);
      setSaveError(null);
      setSaveStatus('unsaved');
    }
    triggerDebouncedSave();
  };

  const handleAddTag = (rawTag: string): boolean => {
    const res = validateTag(rawTag);
    if (!res.ok) return false;
    const clean = res.tag!;
    if (hasTag(editTagsRef.current, clean)) return true;
    const nextTags = dedupeTags([...editTagsRef.current, clean]);
    setEditTags(nextTags);
    editTagsRef.current = nextTags;
    setSaveError(null);
    setSaveStatus('unsaved');
    triggerDebouncedSave();
    return true;
  };

  const handleRemoveTag = (tagToRemove: string) => {
    const nextTags = editTagsRef.current.filter((t) => t.toLowerCase() !== tagToRemove.toLowerCase());
    setEditTags(nextTags);
    editTagsRef.current = nextTags;
    setSaveError(null);
    setSaveStatus('unsaved');
    triggerDebouncedSave();
  };

  // Click "转为笔记": enters naming state and focuses title input immediately
  const handleStartNaming = () => {
    setIsNaming(true);
    requestAnimationFrame(() => {
      titleInputRef.current?.focus();
    });
  };

  // Note switches remount via editorKey; the first save must keep this editor mounted.
  useEffect(() => {
    if (isNewDraftRef.current) {
      setInitialNote({
        id: '',
        type: EntityType.EntityTypeNote,
        draft: isDraftType,
        title: '',
        tags: [],
        body: '',
        created_at: '',
        updated_at: '',
      });
      setEditTitle('');
      editTitleRef.current = '';
      setEditTags([]);
      editTagsRef.current = [];
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
        const noteTags = n.tags ?? [];
        setEditTags(noteTags);
        editTagsRef.current = noteTags;
        lastSavedStateRef.current = {
          title: n.title,
          tags: noteTags,
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
    }

    return () => {
      active = false;
      if (unlistenStatus) unlistenStatus();
    };
  }, [noteId, initialNote]);

  // Load backlinks
  useEffect(() => {
    let mounted = true;
    if (!currentNoteIdRef.current || isNewDraftRef.current) {
      setBacklinks([]);
      return;
    }
    VaultService.GetNoteBacklinks(currentNoteIdRef.current)
      .then((sources) => {
        if (mounted) setBacklinks(sources || []);
      })
      .catch(() => {
        if (mounted) setBacklinks([]);
      });
    return () => {
      mounted = false;
    };
  }, [noteId]);

  // Subscribe to vault:changed: if hitting current note, handle silent reload or conflict; if hitting files, refresh image tags
  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', (ev: any) => {
      if (isNewDraftRef.current) return;
      if (!matchesVaultEventType(ev, ['note', 'file'])) return;
      const data = ev?.data as { op?: string; path?: string; entity_id?: string; type?: string } | undefined;
      if (data?.entity_id === currentNoteIdRef.current) {
        const bodyNow = vditorRef.current ? vditorRef.current.getValue() : (initialNoteRef.current?.body ?? '');
        const titleNow = editTitleRef.current;
        const tagsNow = editTagsRef.current;
        const dirty = isDirtyRef.current(titleNow, tagsNow, bodyNow);

        VaultService.GetNote(currentNoteIdRef.current)
          .then((updated) => {
            if (!updated || updated.id !== currentNoteIdRef.current) return;

            const isAudioTranscriptNow = isAudioTranscriptNote(initialNoteRef.current);
            const target = inFlightSaveRef.current || lastSavedStateRef.current;
            const diskTitle = updated.title.trim();
            const diskBody = updated.body ?? '';
            const diskTags = updated.tags ?? [];

            const isDiskIdenticalToLocal =
              target !== null &&
              diskTitle === target.title.trim() &&
              (isAudioTranscriptNow ? true : normalizeBody(diskBody) === normalizeBody(target.body)) &&
              diskTags.length === target.tags.length &&
              diskTags.every((t, i) => t.toLowerCase() === target.tags[i]?.toLowerCase());

            // If disk content is identical to what we saved or are in-flight saving, ignore internal write event
            if (isDiskIdenticalToLocal) {
              return;
            }

            // Real external change occurred on disk!
            const curBody = vditorRef.current ? vditorRef.current.getValue() : (initialNoteRef.current?.body ?? '');
            const curTitle = editTitleRef.current;
            const curTags = editTagsRef.current;

            if (dirty || isDirtyRef.current(curTitle, curTags, curBody)) {
              // Local has unsaved edits AND disk changed externally -> real conflict
              if (debounceTimerRef.current) {
                window.clearTimeout(debounceTimerRef.current);
                debounceTimerRef.current = null;
              }
              setSaveStatus('conflict');
              setConflictError('外部文件已更新（本地有未保存修改）');
              return;
            }

            if (!dirty) {
              // Clean state: silently update in place without banner or error
              setInitialNote(updated);
              initialNoteRef.current = updated;
              lastSavedStateRef.current = {
                title: updated.title,
                tags: diskTags,
                body: diskBody,
              };
              if (diskTitle !== curTitle.trim()) {
                setEditTitle(updated.title);
                editTitleRef.current = updated.title;
              }
              const tagsDiffer =
                diskTags.length !== curTags.length ||
                diskTags.some((t, i) => t.toLowerCase() !== curTags[i]?.toLowerCase());
              if (tagsDiffer) {
                setEditTags(diskTags);
                editTagsRef.current = diskTags;
              }
              if (vditorRef.current && !isAudioTranscriptNow) {
                if (diskBody !== vditorRef.current.getValue()) {
                  vditorRef.current.setValue(diskBody);
                }
                lastSavedStateRef.current.body = vditorRef.current.getValue();
              }
              setSaveStatus('saved');
              setConflictError(null);
            }
          })
          .catch((err) => {
            console.warn('Failed to silently reload clean note:', err);
          });
        return;
      }
      if (data?.type === 'file' || data?.entity_id?.startsWith('files/')) {
        const container = vditorContainerRef.current;
        if (!container) return;
        const rawFileName = data.entity_id ? data.entity_id.split('/').pop() : '';
        if (!rawFileName) return;
        let fileName = rawFileName;
        try {
          fileName = decodeURIComponent(rawFileName);
        } catch {
          // keep raw
        }
        const imgs = container.querySelectorAll('img');
        const ts = Date.now();
        imgs.forEach((img) => {
          const currentSrc = img.getAttribute('src');
          if (!currentSrc) return;
          try {
            const urlObj = new URL(currentSrc, window.location.href);
            const pathParts = urlObj.pathname.split('/');
            const srcName = decodeURIComponent(pathParts[pathParts.length - 1] || '');
            if (srcName === fileName) {
              urlObj.searchParams.set('t', String(ts));
              img.setAttribute('src', urlObj.toString());
            }
          } catch {
            // ignore
          }
        });
      }
    });
    return () => {
      unsubscribe();
    };
  }, []);

  // Keyboard shortcut Cmd+S / Ctrl+S to save immediately
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        if (isDeletedRef.current || saveStatusRef.current === 'conflict') return;
        if (debounceTimerRef.current) {
          window.clearTimeout(debounceTimerRef.current);
          debounceTimerRef.current = null;
        }
        void doSaveRef.current();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  // Window beforeunload flush
  useEffect(() => {
    const handleBeforeUnload = () => {
      if (isDeletedRef.current || saveStatusRef.current === 'conflict') return;
      if (debounceTimerRef.current) {
        window.clearTimeout(debounceTimerRef.current);
        debounceTimerRef.current = null;
        void doSaveRef.current();
      }
    };
    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, []);

  // Unmount cleanup best-effort flush & timer cancel
  useEffect(() => {
    return () => {
      isUnmountedRef.current = true;
      if (isDeletedRef.current || saveStatusRef.current === 'conflict') return;
      if (debounceTimerRef.current) {
        window.clearTimeout(debounceTimerRef.current);
        debounceTimerRef.current = null;
      }
      void doSaveRef.current();
    };
  }, []);

  // Retranscribe audio
  const handleRetranscribe = async () => {
    try {
      const cfg = await VaultService.GetASRConfigStatus();
      if (!cfg.configured) {
        onOpenSettings?.('transcription');
        return;
      }
      await VaultService.StartAudioTranscription(currentNoteIdRef.current || noteId);
      const st = await VaultService.GetASRTaskStatus(currentNoteIdRef.current || noteId);
      setAsrStatus(st);
    } catch (err: any) {
      console.error('Retranscribe failed:', err);
    }
  };

  const handleConfirmReplace = async () => {
    setReplaceError(null);
    try {
      const updated = await VaultService.ConfirmReplaceTranscript(currentNoteIdRef.current || noteId);
      if (updated) {
        setInitialNote(updated);
        lastSavedStateRef.current = {
          title: updated.title,
          tags: updated.tags || [],
          body: updated.body || '',
        };
        setShowReplaceConfirm(false);
        onNoteUpdatedRef.current(updated);
        onVaultDataChanged?.();
      }
    } catch (err: any) {
      console.error('ConfirmReplaceTranscript failed:', err);
      setReplaceError(err?.message || String(err));
    }
  };

  const handleDiscardCandidate = async () => {
    try {
      await VaultService.DiscardCandidateTranscript(currentNoteIdRef.current || noteId);
      setShowReplaceConfirm(false);
      setReplaceError(null);
    } catch (err: any) {
      console.error('DiscardCandidateTranscript failed:', err);
    }
  };

  // Mount Vditor editor when note is loaded (only for normal editable notes)
  useEffect(() => {
    const currentNote = initialNoteRef.current || initialNote;
    if (loadingNote || !currentNote || !vditorContainerRef.current || vditorRef.current || isAudioTranscriptNote(currentNote)) return;

    const isDark = document.documentElement.classList.contains('dark');

    const vditor = new Vditor(vditorContainerRef.current, {
      cdn: '/vditor',
      mode: 'ir',
      undoDelay: 100,
      value: currentNote.body ?? '',
      height: '100%',
      placeholder: '',
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
      toolbarConfig: {
        hide: true,
      },
      link: { isOpen: true, click: (a: Element) => linkClickRef.current(a as HTMLElement) },
      input: () => {
        triggerDebouncedSaveRef.current();
        syncPickerRef.current();
      },
      after: () => {
        // shortcut: Vditor 4 has no emoji-hint switch; use the official option when available.
        vditor.vditor.options.hint!.extend = [];
        // 如果是新建草稿，直接聚焦编辑器正文
        if (isNewDraftRef.current && isDraftType) {
          vditor.focus();
        }
        if (lastSavedStateRef.current) {
          lastSavedStateRef.current.body = vditor.getValue();
        }
      },
    });

    vditorRef.current = vditor;

    // Dark mode observer
    const observer = new MutationObserver(() => {
      const dark = document.documentElement.classList.contains('dark');
      vditor.setTheme(
        dark ? 'dark' : 'classic',
        dark ? 'dark' : 'light',
        dark ? 'github-dark' : 'github'
      );
    });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });

    return () => {
      observer.disconnect();
      try {
        vditor.destroy();
      } catch {}
      vditorRef.current = null;
    };
  }, [loadingNote]);

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

  useEffect(() => {
    const onSelectionChange = () => syncPickerRef.current();
    document.addEventListener('selectionchange', onSelectionChange);
    return () => document.removeEventListener('selectionchange', onSelectionChange);
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

  // Central Draft Checking Registration
  useEffect(() => {
    if (!onDraftCheck) return;
    const unregister = onDraftCheck(() => {
      if (isDeletedRef.current) return false;
      const currentTitle = editTitleRef.current;
      const currentTags = editTagsRef.current;
      const currentBody = vditorRef.current ? vditorRef.current.getValue() : (initialNoteRef.current?.body ?? '');
      return isDirtyRef.current(currentTitle, currentTags, currentBody);
    });
    return unregister;
  }, [onDraftCheck]);

  // Leave guard
  useEffect(() => {
    if (!leaveGuardRef) return;
    leaveGuardRef.current = async () => {
      if (saveStatusRef.current === 'conflict') {
        return askUserConfirm(() => setShowLeaveConflictConfirm(true));
      }
      const currentBody = vditorRef.current ? vditorRef.current.getValue() : (initialNoteRef.current?.body ?? '');
      if (isDirtyRef.current(editTitleRef.current, editTagsRef.current, currentBody)) {
        const ok = await doSaveRef.current();
        if (!ok && isDirtyRef.current(editTitleRef.current, editTagsRef.current, currentBody)) {
          // If empty new draft, ok to discard
          if (isNewDraftRef.current && isDraftType && !currentBody.trim()) {
            return true;
          }
          return askUserConfirm(() => setShowSaveFailedConfirm(true));
        }
      }
      return true;
    };
    return () => {
      if (leaveGuardRef) leaveGuardRef.current = null;
    };
  }, [leaveGuardRef, isDraftType]);

  const leaveThen = async (action: () => void) => {
    if (leaveGuardRef?.current) {
      pendingGoRef.current = action;
      const canProceed = await leaveGuardRef.current();
      if (!canProceed) return;
      pendingGoRef.current = null;
    }
    action();
  };

  const handleCopyDraft = async () => {
    const body = vditorRef.current ? vditorRef.current.getValue() : (initialNote?.body || '');
    const draftContent = isDraftNote && !isNaming
      ? body
      : formatDraftText(editTitle, editTags, body);
    try {
      const ok = await copyToClipboard(draftContent);
      if (ok) {
        setCopiedDraft(true);
        setTimeout(() => setCopiedDraft(false), 2500);
        showToast('草稿已复制到剪贴板');
      } else {
        showToast('复制草稿失败');
      }
    } catch (err) {
      console.error('Failed to copy draft to clipboard:', err);
      showToast('复制草稿失败');
    }
  };

  // Reload handler
  const handleConfirmReload = async () => {
    setShowReloadConfirm(false);
    if (isNewDraftRef.current) {
      setEditTitle('');
      editTitleRef.current = '';
      setEditTags([]);
      editTagsRef.current = [];
      if (vditorRef.current) vditorRef.current.setValue('');
      setConflictError(null);
      setSaveStatus('saved');
      return;
    }
    try {
      const bodyNow = isAudioTranscriptNote(initialNoteRef.current)
        ? (initialNoteRef.current?.body ?? '')
        : (vditorRef.current ? vditorRef.current.getValue() : '');
      if (isDirtyRef.current(editTitleRef.current, editTagsRef.current, bodyNow)) {
        const draftText = formatDraftText(editTitleRef.current, editTagsRef.current, bodyNow);
        await copyToClipboard(draftText);
      }

      const diskNote = await VaultService.GetNote(currentNoteIdRef.current);
      if (!diskNote) return;

      setInitialNote(diskNote);
      setEditTitle(diskNote.title);
      editTitleRef.current = diskNote.title;
      const noteTags = diskNote.tags ?? [];
      setEditTags(noteTags);
      editTagsRef.current = noteTags;
      setTitleError(null);

      const body = diskNote.body ?? '';
      if (vditorRef.current && !isAudioTranscriptNote(diskNote)) {
        vditorRef.current.setValue(body);
      }

      lastSavedStateRef.current = {
        title: diskNote.title,
        tags: diskNote.tags ?? [],
        body: vditorRef.current && !isAudioTranscriptNote(diskNote) ? vditorRef.current.getValue() : body,
      };

      setConflictError(null);
      setSaveStatus('saved');
      onNoteUpdatedRef.current(diskNote);
      showToast('已载入外部版本（原未保存草稿已备份至剪贴板）');
    } catch (err: any) {
      console.error('Failed to reload note:', err);
      setConflictError(`重新加载失败: ${err?.message || err}`);
    }
  };

  const handleResolveConflictKeepMine = async () => {
    try {
      const saved = await doSave(true);
      if (saved) {
        setConflictError(null);
        setSaveStatus('saved');
        showToast('已用本地草稿覆盖外部版本');
      }
    } catch (err: any) {
      console.error('Failed to overwrite note:', err);
      showToast(err?.message || '覆盖失败');
    }
  };
  const handleConfirmDelete = async () => {
    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = null;
    }
    if (isNewDraftRef.current) {
      isDeletedRef.current = true;
      setShowDeleteConfirm(false);
      onDeleteCurrentNote?.(noteId);
      return;
    }
    setIsDeleting(true);
    setDeleteError(null);
    try {
      await VaultService.DeleteNote(currentNoteIdRef.current || noteId);
      isDeletedRef.current = true;
      setShowDeleteConfirm(false);
      onDeleteCurrentNote?.(currentNoteIdRef.current || noteId);
    } catch (err: any) {
      console.error('DeleteNote failed:', err);
      setDeleteError(`删除失败: ${err?.message || err}`);
    } finally {
      setIsDeleting(false);
    }
  };

  const handleCopyAbsolutePath = async () => {
    setMoreMenuOpen(false);
    const targetId = currentNoteIdRef.current || noteId;
    if (!targetId || isNewDraftRef.current) {
      showToast('草稿尚未保存，暂无文件路径');
      return;
    }
    try {
      const path = await VaultService.GetNotePath(targetId);
      if (!path) {
        showToast('获取笔记路径失败');
        return;
      }
      const ok = await copyToClipboard(path);
      if (ok) {
        showToast('已复制绝对路径');
      } else {
        showToast('复制到剪贴板失败');
      }
    } catch (err: any) {
      console.error('Failed to copy note path:', err);
      showToast(err?.message || '复制路径失败');
    }
  };

  const handleOpenInFinder = async () => {
    setMoreMenuOpen(false);
    const targetId = currentNoteIdRef.current || noteId;
    if (!targetId || isNewDraftRef.current) {
      showToast('草稿尚未保存，暂无文件路径');
      return;
    }
    try {
      await VaultService.RevealNoteInFinder(targetId);
    } catch (err: any) {
      console.error('Failed to reveal note in Finder:', err);
      showToast(err?.message || '在 Finder 中打开失败');
    }
  };

  if (loadingNote) {
    return (
      <div className="flex-1 flex items-center justify-center py-24 text-xs text-stone-400">
        <Loader2 className="w-5 h-5 animate-spin mr-2 text-interaction-600" />
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
      </div>
    );
  }

  const renderSaveStatus = () => {
    if (saveStatus !== 'failed') return null;
    return (
      <span className="text-rose-600 dark:text-rose-400 font-medium flex items-center space-x-1.5" title={saveError || '保存失败'}>
        <AlertCircle className="w-3.5 h-3.5 text-rose-600 shrink-0" />
        <span>保存失败</span>
      </span>
    );
  };

  const renderMoreMenu = () => (
    <div className="relative" ref={moreMenuRef}>
      <button
        type="button"
        onClick={() => setMoreMenuOpen((v) => !v)}
        className="p-1 rounded-md text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800/60 transition cursor-pointer"
        title="更多操作"
      >
        <MoreHorizontal className="w-4 h-4" />
      </button>
      {moreMenuOpen && (
        <div className="absolute right-0 top-full mt-1 w-40 rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-900 shadow-lg py-1 z-30">
          <button
            type="button"
            onClick={handleCopyAbsolutePath}
            disabled={isNewDraftRef.current}
            className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed whitespace-nowrap"
            title={isNewDraftRef.current ? '草稿尚未保存，暂无文件路径' : undefined}
          >
            <Copy className="w-3.5 h-3.5 text-stone-400 shrink-0" />
            <span>复制绝对路径</span>
          </button>
          <button
            type="button"
            onClick={handleOpenInFinder}
            disabled={isNewDraftRef.current}
            className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed whitespace-nowrap"
            title={isNewDraftRef.current ? '草稿尚未保存，暂无文件路径' : undefined}
          >
            <FolderOpen className="w-3.5 h-3.5 text-stone-400 shrink-0" />
            <span>在 Finder 中打开</span>
          </button>
          <div className="my-1 border-t border-stone-100 dark:border-stone-800" />
          <button
            type="button"
            onClick={() => {
              setMoreMenuOpen(false);
              setShowDeleteConfirm(true);
            }}
            className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 transition text-left cursor-pointer whitespace-nowrap"
          >
            <Trash2 className="w-3.5 h-3.5 shrink-0" />
            <span>{isDraftNote ? '删除草稿' : '删除笔记'}</span>
          </button>
        </div>
      )}
    </div>
  );

  return (
    <div className={`relative flex-1 min-w-0 min-h-0 flex flex-col h-full p-6 overflow-hidden ${
      !isDraftNote || isNaming ? 'space-y-2.5' : ''
    }`}>
      {/* Draft Mode Actions: Floating in top corners so draft text starts flush at the top */}
      {isDraftNote && !isNaming && (
        <>
          {(listCollapsed || returnToTask) && (
            <div className="absolute top-6 left-6 z-10 no-drag-region flex items-center gap-2">
              {listCollapsed && (
                <button
                  type="button"
                  onClick={onToggleListCollapse}
                  className="p-1 -ml-1 rounded-md text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 transition cursor-pointer shrink-0"
                  title="展开笔记列表"
                >
                  <PanelLeftOpen className="w-4 h-4" />
                </button>
              )}

              {returnToTask && (
                <button
                  type="button"
                  onClick={() => void leaveThen(returnToTask.go)}
                  className="flex items-center space-x-1.5 px-2 py-1 rounded-md text-xs font-medium text-stone-500 hover:text-stone-800 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 transition shrink-0"
                  title={`${returnToTask.label}（将自动保存未提交改动）`}
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  <span>{returnToTask.label}</span>
                </button>
              )}
            </div>
          )}

          <div className="absolute top-6 right-6 z-10 no-drag-region flex items-center space-x-2 text-xs">
            {renderSaveStatus()}
            <button
              type="button"
              onClick={handleStartNaming}
              className="flex items-center space-x-1 px-2.5 py-1 rounded-md border border-stone-200/80 dark:border-stone-700/80 bg-white/90 dark:bg-stone-800/90 backdrop-blur-xs text-stone-700 dark:text-stone-200 hover:border-interaction-500/70 hover:text-interaction-700 dark:hover:text-interaction-400 text-xs font-medium transition cursor-pointer shadow-2xs"
              title="原地输入标题并转为正式笔记"
            >
              <span>转为笔记</span>
            </button>
            {renderMoreMenu()}
          </div>
        </>
      )}

      {/* Formal Note Mode Header: Title & Actions on line 1 */}
      {(!isDraftNote || isNaming) && (
        <div className="flex items-center justify-between gap-3 shrink-0 drag-region min-h-[28px]">
          <div className="no-drag-region flex items-center gap-2 flex-1 min-w-0">
            {listCollapsed && (
              <button
                type="button"
                onClick={onToggleListCollapse}
                className="p-1 -ml-1 rounded-md text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 transition cursor-pointer shrink-0"
                title="展开笔记列表"
              >
                <PanelLeftOpen className="w-4 h-4" />
              </button>
            )}

            {returnToTask && (
              <button
                type="button"
                onClick={() => void leaveThen(returnToTask.go)}
                className="flex items-center space-x-1.5 px-2 py-1 rounded-md text-xs font-medium text-stone-500 hover:text-stone-800 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 transition shrink-0"
                title={`${returnToTask.label}（将自动保存未提交改动）`}
              >
                <ArrowLeft className="w-3.5 h-3.5" />
                <span>{returnToTask.label}</span>
              </button>
            )}

            <input
              ref={titleInputRef}
              type="text"
              value={editTitle}
              onChange={(e) => handleTitleChange(e.target.value)}
              onKeyDown={(e) => {
                if (e.nativeEvent.isComposing || e.keyCode === 229) return;
                if (e.key === 'Enter') {
                  e.preventDefault();
                  vditorRef.current?.focus();
                }
              }}
              placeholder={isNaming ? '笔记标题…' : '无标题笔记'}
              className="w-full text-2xl font-semibold bg-transparent text-stone-900 dark:text-stone-100 placeholder:text-muted-foreground focus:outline-hidden border-none p-0 leading-tight tracking-tight"
            />
          </div>

          <div className="no-drag-region flex items-center space-x-2 text-xs shrink-0 min-h-[28px]">
            {renderSaveStatus()}
            {renderMoreMenu()}
          </div>
        </div>
      )}

      {/* Conflict Action Bar: 外部变动且本地有未保存内容时的选择条 */}
      {(saveStatus === 'conflict' || conflictError) && (
        <div className="px-3.5 py-2 rounded-lg border border-amber-200 dark:border-amber-900/60 bg-amber-50/90 dark:bg-amber-950/40 text-xs flex items-center justify-between gap-3 shadow-xs shrink-0 animate-in fade-in duration-150">
          <div className="flex items-center space-x-2 min-w-0">
            <AlertCircle className="w-4 h-4 text-amber-600 dark:text-amber-500 shrink-0" />
            <span className="text-amber-900 dark:text-amber-200 font-medium truncate">
              {conflictError || '外部文件已更新（本地有未保存修改）'}
            </span>
          </div>
          <div className="flex items-center space-x-1.5 shrink-0">
            <button
              type="button"
              onClick={handleCopyDraft}
              className="px-2.5 py-1 rounded-md text-stone-600 dark:text-stone-300 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-amber-100/70 dark:hover:bg-amber-900/50 transition cursor-pointer font-medium"
              title="将未写盘草稿复制到剪贴板"
            >
              {copiedDraft ? '已复制' : '复制草稿'}
            </button>
            <button
              type="button"
              onClick={() => setShowReloadConfirm(true)}
              className="px-2.5 py-1 rounded-md border border-amber-300/80 dark:border-amber-800 hover:bg-amber-100 dark:hover:bg-amber-900/60 text-amber-900 dark:text-amber-200 transition cursor-pointer font-medium"
            >
              载入外部版本
            </button>
            <button
              type="button"
              onClick={handleResolveConflictKeepMine}
              className="px-2.5 py-1 rounded-md bg-stone-900 dark:bg-stone-100 hover:bg-stone-800 dark:hover:bg-white text-white dark:text-stone-900 transition cursor-pointer font-medium shadow-2xs"
            >
              用本地草稿覆盖
            </button>
          </div>
        </div>
      )}

      {/* Document Sub-Header: Tags & Creator (Only for formal notes or when naming draft) */}
      {(!isDraftNote || isNaming) && (
        <div className="space-y-2 shrink-0">
          {titleError && (
            <div className="text-[11px] text-rose-600 dark:text-rose-400 font-medium">
              {titleError}
            </div>
          )}

          {initialNote && !isDraftNote && (
            <div className="flex items-center gap-1 text-[11px] text-muted-foreground">
              {initialNote.created_by === 'agent'
                ? <Bot aria-hidden="true" className="w-3 h-3" />
                : <UserRound aria-hidden="true" className="w-3 h-3" />}
              {formatStatusAction('creation', initialNote.created_by)}
            </div>
          )}

          {/* Tag Chips + Add Popover */}
          <TagChipEditor
            tags={editTags}
            suggestedTags={tagNames}
            onAddTag={handleAddTag}
            onRemoveTag={handleRemoveTag}
          />
        </div>
      )}

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
          className={`vditor-editor-wrapper flex-1 min-h-0 overflow-hidden border-none outline-hidden bg-transparent ${
            isDraftNote && !isNaming && (listCollapsed || returnToTask) ? 'pt-7' : ''
          }`}
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

      {/* Backlinks drawer */}
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
                      className="text-interaction-700 dark:text-interaction-400 hover:underline"
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
      <ConfirmDialog
        open={showReloadConfirm}
        variant="warning"
        title="载入外部版本"
        description="确定载入外部文件的最新内容吗？本地未保存的修改将被覆盖（我们会自动将当前草稿备份到剪贴板）。"
        confirmText="载入并覆盖本地"
        cancelText="取消"
        onCancel={() => setShowReloadConfirm(false)}
        onConfirm={handleConfirmReload}
      />

      {/* Confirmation Modal for Leaving During Conflict */}
      <ConfirmDialog
        open={showLeaveConflictConfirm}
        variant="destructive"
        title="存在未解决冲突"
        description="当前笔记存在外部文件修改冲突。直接离开将放弃本地未保存的内容。确认离开吗？"
        confirmText="放弃修改并离开"
        cancelText="继续编辑"
        onCancel={() => {
          setShowLeaveConflictConfirm(false);
          pendingGoRef.current = null;
          const resolve = leavePromptResolverRef.current;
            leavePromptResolverRef.current = null;
            resolve?.(false);
        }}
        onConfirm={() => {
          setShowLeaveConflictConfirm(false);
          setConflictError(null);
          setSaveStatus('saved');
          const go = pendingGoRef.current;
          pendingGoRef.current = null;
          const resolve = leavePromptResolverRef.current;
          leavePromptResolverRef.current = null;
          go?.();
          resolve?.(true);
        }}
      />

      {/* Confirmation Modal for Save Failure on Exit */}
      <ConfirmDialog
        open={showSaveFailedConfirm}
        variant="destructive"
        title="保存未成功"
        description="当前内容未能成功保存到磁盘。直接离开将丢弃未保存的修改，是否确定离开？"
        confirmText="丢弃并离开"
        cancelText="留在页面"
        onCancel={() => {
          setShowSaveFailedConfirm(false);
          pendingGoRef.current = null;
          const resolve = leavePromptResolverRef.current;
            leavePromptResolverRef.current = null;
            resolve?.(false);
        }}
        onConfirm={() => {
          setShowSaveFailedConfirm(false);
          if (debounceTimerRef.current) {
            window.clearTimeout(debounceTimerRef.current);
            debounceTimerRef.current = null;
          }
          const go = pendingGoRef.current;
          pendingGoRef.current = null;
          const resolve = leavePromptResolverRef.current;
          leavePromptResolverRef.current = null;
          go?.();
          resolve?.(true);
        }}
      />

      {/* Confirmation Modal for Replacing Transcript */}
      <ConfirmDialog
        open={showReplaceConfirm}
        variant="default"
        title="发现新转写结果"
        description={
          <div className="space-y-1">
            <span>当前音频已生成新的逐字稿内容。您可以选择替换原逐字稿，或者保留原稿（保留原稿将放弃新生成的逐字稿）。</span>
            {replaceError && (
              <p className="text-xs text-rose-600 dark:text-rose-400 font-medium pt-1">
                {replaceError}
              </p>
            )}
          </div>
        }
        confirmText="替换逐字稿"
        cancelText="保留原稿"
        onCancel={handleDiscardCandidate}
        onConfirm={handleConfirmReplace}
      />

      {/* Confirmation Modal for Deleting Note */}
      <ConfirmDialog
        open={showDeleteConfirm}
        variant="destructive"
        title={isDraftNote ? '确认删除草稿？' : '确认删除笔记？'}
        description={
          <div className="space-y-1">
            <span>
              {isDraftNote
                ? '此草稿文件将从 Vault 中永久删除，此操作不可撤销。'
                : `笔记「${editTitle || initialNote?.title || '未命名'}」的文件将从 Vault 中永久删除，此操作不可撤销。`}
            </span>
            {deleteError && (
              <p className="text-xs text-rose-600 dark:text-rose-400 font-medium pt-1">
                {deleteError}
              </p>
            )}
          </div>
        }
        confirmText={isDeleting ? '删除中...' : '确认删除'}
        cancelText="取消"
        onCancel={() => {
          setShowDeleteConfirm(false);
          setDeleteError(null);
        }}
        onConfirm={handleConfirmDelete}
      />

      {/* Non-blocking Toast Notification */}
      {toastMessage && createPortal(
        <div
          role="status"
          aria-live="polite"
          className="pata-fade fixed bottom-6 left-1/2 -translate-x-1/2 z-50 px-3.5 py-1.5 rounded-full bg-stone-900/90 dark:bg-stone-100/90 text-white dark:text-stone-900 text-xs font-medium shadow-lg backdrop-blur pointer-events-none transition-all duration-200 flex items-center space-x-1.5"
        >
          <Check className="w-3.5 h-3.5 text-emerald-400 dark:text-emerald-600 shrink-0" />
          <span>{toastMessage}</span>
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
  onDraftCheck,
  onOpenSettings,
  tagNames = [],
  onVaultDataChanged,
}: NotesViewProps) {
  const [notes, setNotes] = useState<Note[]>([]);
  const [loading, setLoading] = useState(false);
  const [listError, setListError] = useState<string | null>(null);

  const [selectedNoteId, setSelectedNoteId] = useState<string | null>(null);
  const [isNewDraft, setIsNewDraft] = useState(false);
  const [isDraftType, setIsDraftType] = useState(true);
  const [editorKey, setEditorKey] = useState<string>('');
  const notesLoadedRef = useRef(false);

  const [listWidth, setListWidth] = useState<number>(() =>
    loadPersistedNumber(WIDTH_STORAGE_KEY, DEFAULT_NOTES_LIST_WIDTH, MIN_NOTES_LIST_WIDTH, MAX_NOTES_LIST_WIDTH)
  );
  const [listCollapsed, setListCollapsed] = useState<boolean>(() =>
    loadPersistedBool(COLLAPSED_STORAGE_KEY, false)
  );
  const [isDraftsCollapsed, setIsDraftsCollapsed] = useState<boolean>(() =>
    loadPersistedBool(DRAFTS_COLLAPSED_KEY, false)
  );
  const [isNotesCollapsed, setIsNotesCollapsed] = useState<boolean>(() =>
    loadPersistedBool(FORMAL_COLLAPSED_KEY, false)
  );

  // Freeze list ordering during continuous auto-save
  const [frozenDraftIds, setFrozenDraftIds] = useState<string[]>([]);
  const [frozenFormalIds, setFrozenFormalIds] = useState<string[]>([]);
  const notesRef = useRef<Note[]>(notes);
  notesRef.current = notes;

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

  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; note: Note } | null>(null);
  const contextMenuRef = useRef<HTMLDivElement | null>(null);
  const [noteToDelete, setNoteToDelete] = useState<Note | null>(null);
  const [isDeletingFromList, setIsDeletingFromList] = useState(false);
  const [deleteListError, setDeleteListError] = useState<string | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const toastTimerRef = useRef<number | null>(null);

  const showToast = useCallback((msg: string) => {
    if (toastTimerRef.current) {
      window.clearTimeout(toastTimerRef.current);
    }
    setToastMessage(msg);
    toastTimerRef.current = window.setTimeout(() => {
      setToastMessage(null);
      toastTimerRef.current = null;
    }, 2000);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) {
        window.clearTimeout(toastTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!contextMenu) return;
    const handleClose = (e: Event) => {
      if (contextMenuRef.current && e.target instanceof Node && contextMenuRef.current.contains(e.target)) {
        return;
      }
      setContextMenu(null);
    };
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setContextMenu(null);
    };
    window.addEventListener('mousedown', handleClose);
    window.addEventListener('scroll', handleClose, true);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('mousedown', handleClose);
      window.removeEventListener('scroll', handleClose, true);
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [contextMenu]);

  // Sorting function: updated_at DESC, created_at DESC, id ASC
  const sortNotesComparator = useCallback((a: Note, b: Note) => {
    const aUp = a.updated_at ? new Date(a.updated_at).getTime() : 0;
    const bUp = b.updated_at ? new Date(b.updated_at).getTime() : 0;
    if (aUp !== bUp) return bUp - aUp;
    const aCr = a.created_at ? new Date(a.created_at).getTime() : 0;
    const bCr = b.created_at ? new Date(b.created_at).getTime() : 0;
    if (aCr !== bCr) return bCr - aCr;
    return a.id.localeCompare(b.id);
  }, []);

  const reorderIds = useCallback((allNotesList: Note[]) => {
    const drafts = allNotesList.filter((n) => n.draft);
    const formal = allNotesList.filter((n) => !n.draft);
    drafts.sort(sortNotesComparator);
    formal.sort(sortNotesComparator);
    setFrozenDraftIds(drafts.map((n) => n.id));
    setFrozenFormalIds(formal.map((n) => n.id));
  }, [sortNotesComparator]);

  const loadNotes = useCallback(async (andReorder: boolean = true) => {
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
      notesLoadedRef.current = true;
      setNotes(validNotes);
      if (andReorder) {
        reorderIds(validNotes);
      }
    } catch (err: any) {
      console.error('Failed to list notes:', err);
      setListError(err?.message || String(err));
    } finally {
      notesLoadedRef.current = true;
      setLoading(false);
    }
  }, [vaultStatus?.open, reorderIds]);

  useEffect(() => {
    loadNotes(true);
  }, [loadNotes]);

  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', (ev: any) => {
      if (matchesVaultEventType(ev, ['note'])) {
        loadNotes(true);
      }
    });
    return () => {
      unsubscribe();
    };
  }, [loadNotes]);

  useEffect(() => {
    onEditingChange?.(selectedNoteId !== null);
  }, [selectedNoteId, onEditingChange]);

  // Consume focusNoteId from parent navigation (Search, Task link, etc.)
  useEffect(() => {
    if (focusNoteId) {
      setSelectedNoteId(focusNoteId);
      setEditorKey(focusNoteId);
      setIsNewDraft(false);
      setIsDraftType(false);
      try {
        localStorage.setItem(LAST_NOTE_ID_KEY, focusNoteId);
      } catch {}

      // If notes have not loaded at least once, wait for loadNotes before resolving group and consuming focus
      if (!notesLoadedRef.current && notes.length === 0) {
        return;
      }

      const target = notes.find((n) => n.id === focusNoteId);
      if (target?.draft) {
        setIsDraftsCollapsed(false);
      } else if (target) {
        setIsNotesCollapsed(false);
      }
      if (notes.length > 0) {
        reorderIds(notes);
      }
      requestAnimationFrame(() => {
        const el = document.getElementById(`note-item-${focusNoteId}`);
        el?.scrollIntoView({ block: 'nearest' });
      });
      onClearFocusNote?.();
    }
  }, [focusNoteId, notes, onClearFocusNote, reorderIds]);

  // Restore last selected note ID on initial load if none focused
  useEffect(() => {
    if (!notes.length || selectedNoteId || focusNoteId) return;
    try {
      const lastId = localStorage.getItem(LAST_NOTE_ID_KEY);
      if (lastId && notes.some((n) => n.id === lastId)) {
        setSelectedNoteId(lastId);
        setEditorKey(lastId);
        setIsNewDraft(false);
        setIsDraftType(false);
        const target = notes.find((n) => n.id === lastId);
        if (target?.draft) {
          setIsDraftsCollapsed(false);
        } else {
          setIsNotesCollapsed(false);
        }
      }
    } catch {}
  }, [notes, selectedNoteId, focusNoteId]);

  useEffect(() => {
    try {
      localStorage.setItem(WIDTH_STORAGE_KEY, String(listWidth));
    } catch {}
  }, [listWidth]);

  useEffect(() => {
    try {
      localStorage.setItem(COLLAPSED_STORAGE_KEY, String(listCollapsed));
    } catch {}
  }, [listCollapsed]);

  useEffect(() => {
    try {
      localStorage.setItem(DRAFTS_COLLAPSED_KEY, String(isDraftsCollapsed));
    } catch {}
  }, [isDraftsCollapsed]);

  useEffect(() => {
    try {
      localStorage.setItem(FORMAL_COLLAPSED_KEY, String(isNotesCollapsed));
    } catch {}
  }, [isNotesCollapsed]);

  // 窗口过窄时自动折叠笔记列表（保证编辑器可用宽度；隐藏为 0 时不触发）
  const containerRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) {
        if (entry.contentRect.width > 0 && entry.contentRect.width < 560) {
          setListCollapsed(true);
        }
      }
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const isResizingRef = useRef(false);
  const handleDividerPointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    isResizingRef.current = true;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  };

  const handleDividerPointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!isResizingRef.current) return;
    const container = containerRef.current;
    if (!container) return;
    const rect = container.getBoundingClientRect();
    const newWidth = e.clientX - rect.left;
    const clamped = Math.max(MIN_NOTES_LIST_WIDTH, Math.min(MAX_NOTES_LIST_WIDTH, newWidth));
    setListWidth(clamped);
  };

  const handleDividerPointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    if (isResizingRef.current) {
      isResizingRef.current = false;
      try {
        e.currentTarget.releasePointerCapture(e.pointerId);
      } catch {}
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    }
  };

  const handleDividerKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      setListWidth((w) => Math.max(MIN_NOTES_LIST_WIDTH, w - 16));
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      setListWidth((w) => Math.min(MAX_NOTES_LIST_WIDTH, w + 16));
    } else if (e.key === 'Home') {
      e.preventDefault();
      setListWidth(MIN_NOTES_LIST_WIDTH);
    } else if (e.key === 'End') {
      e.preventDefault();
      setListWidth(MAX_NOTES_LIST_WIDTH);
    }
  };

  const handleSelectNote = async (id: string) => {
    if (id === selectedNoteId && !isNewDraft) return;
    if (leaveGuardRef?.current) {
      const canProceed = await leaveGuardRef.current();
      if (!canProceed) return;
    }
    reorderIds(notes);
    setSelectedNoteId(id);
    setEditorKey(id);
    setIsNewDraft(false);
    setIsDraftType(false);
    try {
      localStorage.setItem(LAST_NOTE_ID_KEY, id);
    } catch {}
  };

  const handleStartCreateDraft = async () => {
    if (leaveGuardRef?.current) {
      const canProceed = await leaveGuardRef.current();
      if (!canProceed) return;
    }
    reorderIds(notes);
    const draftKey = 'draft-' + Date.now();
    setEditorKey(draftKey);
    setSelectedNoteId('__new_draft__');
    setIsNewDraft(true);
    setIsDraftType(true);
    setIsDraftsCollapsed(false);
  };

  const handleStartCreateFormalNote = async () => {
    if (leaveGuardRef?.current) {
      const canProceed = await leaveGuardRef.current();
      if (!canProceed) return;
    }
    reorderIds(notes);
    const formalKey = 'formal-' + Date.now();
    setEditorKey(formalKey);
    setSelectedNoteId('__new_formal__');
    setIsNewDraft(true);
    setIsDraftType(false);
    setIsNotesCollapsed(false);
  };

  const handleStartCreateAudioNote = async () => {
    setCreateAudioNoteError(null);
    try {
      const cfg = await VaultService.GetASRConfigStatus();
      if (!cfg.configured) {
        setShowMissingKeyModal(true);
        return;
      }
      const audioPath = await VaultService.SelectAudioFile();
      if (!audioPath) return;

      setCreatingAudioNote(true);
      const created = await VaultService.CreateAudioNote(audioPath);
      if (created) {
        await loadNotes(true);
        setSelectedNoteId(created.id);
        setEditorKey(created.id);
        setIsNewDraft(false);
        setIsDraftType(false);
        setIsNotesCollapsed(false);
        try {
          localStorage.setItem(LAST_NOTE_ID_KEY, created.id);
        } catch {}
      }
    } catch (err: any) {
      console.error('CreateAudioNote failed:', err);
      setCreateAudioNoteError(err?.message || String(err));
    } finally {
      setCreatingAudioNote(false);
    }
  };

  const handleNoteCreated = useCallback((newId: string, isDraft: boolean, createdNote?: Note) => {
    setSelectedNoteId(newId);
    setIsNewDraft(false);
    setIsDraftType(false);
    // Keep editorKey as-is so React does not unmount NoteEditor while user is typing
    if (isDraft) {
      setFrozenDraftIds((prev) => [newId, ...prev.filter((x) => x !== newId)]);
      setIsDraftsCollapsed(false);
    } else {
      setFrozenFormalIds((prev) => [newId, ...prev.filter((x) => x !== newId)]);
      setIsNotesCollapsed(false);
    }
    try {
      localStorage.setItem(LAST_NOTE_ID_KEY, newId);
    } catch {}
    if (createdNote) {
      const noteForList: Note = {
        ...createdNote,
        body: getDraftExcerpt(createdNote.body),
      };
      setNotes((prev) => {
        const idx = prev.findIndex((n) => n.id === noteForList.id);
        if (idx >= 0) {
          const next = [...prev];
          next[idx] = noteForList;
          return next;
        }
        return [noteForList, ...prev];
      });
    }
  }, []);

  const handleNoteConverted = useCallback((convertedId: string, convertedNote?: Note) => {
    setFrozenDraftIds((prev) => prev.filter((id) => id !== convertedId));
    setFrozenFormalIds((prev) => [convertedId, ...prev.filter((id) => id !== convertedId)]);
    setIsNotesCollapsed(false);
    if (convertedNote) {
      const noteForList: Note = {
        ...convertedNote,
        body: getDraftExcerpt(convertedNote.body),
      };
      setNotes((prev) => {
        const idx = prev.findIndex((n) => n.id === noteForList.id);
        if (idx >= 0) {
          const next = [...prev];
          next[idx] = noteForList;
          return next;
        }
        return [noteForList, ...prev];
      });
    }
  }, []);

  const handleNoteUpdated = useCallback((updatedNote?: Note) => {
    if (updatedNote) {
      // 局部更新：无需重新拉取全量 ListNotes()，保留既有列表位置并更新内存实体
      const noteForList: Note = {
        ...updatedNote,
        body: getDraftExcerpt(updatedNote.body),
      };
      setNotes((prev) => {
        const idx = prev.findIndex((n) => n.id === noteForList.id);
        if (idx >= 0) {
          const next = [...prev];
          next[idx] = noteForList;
          return next;
        }
        return [noteForList, ...prev];
      });
    } else {
      loadNotes(false);
    }
  }, [loadNotes]);

  const handleDeleteCurrentNote = useCallback((deletedId: string) => {
    const target = notes.find((n) => n.id === deletedId);
    setSelectedNoteId(null);
    setEditorKey('');
    setIsNewDraft(false);
    setFrozenDraftIds((prev) => prev.filter((id) => id !== deletedId));
    setFrozenFormalIds((prev) => prev.filter((id) => id !== deletedId));
    setNotes((prev) => prev.filter((n) => n.id !== deletedId));
    try {
      localStorage.removeItem(LAST_NOTE_ID_KEY);
    } catch {}
    if (target?.tags && target.tags.length > 0) {
      onVaultDataChanged?.();
    }
  }, [notes, onVaultDataChanged]);

  const handleConfirmDeleteFromList = async () => {
    if (!noteToDelete) return;
    setIsDeletingFromList(true);
    setDeleteListError(null);
    try {
      await VaultService.DeleteNote(noteToDelete.id);
      if (selectedNoteId === noteToDelete.id) {
        setSelectedNoteId(null);
        setEditorKey('');
        setIsNewDraft(false);
        try {
          localStorage.removeItem(LAST_NOTE_ID_KEY);
        } catch {}
      }
      const deletedId = noteToDelete.id;
      const hadTags = Boolean(noteToDelete.tags && noteToDelete.tags.length > 0);
      setNoteToDelete(null);
      setFrozenDraftIds((prev) => prev.filter((id) => id !== deletedId));
      setFrozenFormalIds((prev) => prev.filter((id) => id !== deletedId));
      setNotes((prev) => prev.filter((n) => n.id !== deletedId));
      if (hadTags) {
        onVaultDataChanged?.();
      }
    } catch (err: any) {
      console.error('DeleteNote failed:', err);
      setDeleteListError(`删除失败: ${err?.message || err}`);
    } finally {
      setIsDeletingFromList(false);
    }
  };

  // Derive display list from frozen IDs
  const notesMap = new Map<string, Note>();
  for (const n of notes) {
    notesMap.set(n.id, n);
  }

  const displayedDrafts: Note[] = [];
  for (const id of frozenDraftIds) {
    const item = notesMap.get(id);
    if (item && item.draft) displayedDrafts.push(item);
  }
  // Include any draft not yet in frozen list (fallback)
  for (const n of notes) {
    if (n.draft && !frozenDraftIds.includes(n.id)) {
      displayedDrafts.push(n);
    }
  }

  const displayedFormalNotes: Note[] = [];
  for (const id of frozenFormalIds) {
    const item = notesMap.get(id);
    if (item && !item.draft) displayedFormalNotes.push(item);
  }
  // Include any formal note not yet in frozen list (fallback)
  for (const n of notes) {
    if (!n.draft && !frozenFormalIds.includes(n.id)) {
      displayedFormalNotes.push(n);
    }
  }

  if (!vaultStatus?.configured) {
    return (
      <div className="py-16 text-center space-y-4 max-w-md mx-auto">
        <FolderOpen className="w-12 h-12 text-interaction-600 mx-auto opacity-75" />
        <h2 className="text-base font-semibold text-stone-800 dark:text-stone-200">尚未配置 Vault 目录</h2>
        <p className="text-xs text-stone-500 leading-relaxed">
          Pata 以本地纯文本 Markdown 作为唯一数据真相源（Local First）。请先选择一个本地目录。
        </p>
        <button
          onClick={onSelectVault}
          disabled={vaultBusy}
          className="mx-auto flex items-center space-x-1.5 px-4 py-2 rounded-md bg-[var(--pata-accent-solid)] hover:bg-[var(--pata-accent-solid-hover)] text-[var(--pata-accent-on-solid)] text-xs font-medium transition disabled:opacity-50 shadow-xs cursor-pointer"
        >
          <FolderOpen className="w-3.5 h-3.5" />
          <span>选择 Vault 目录</span>
        </button>
      </div>
    );
  }

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
          className="px-3.5 py-1.5 rounded-md bg-[var(--pata-accent-solid)] hover:bg-[var(--pata-accent-solid-hover)] text-[var(--pata-accent-on-solid)] font-medium transition disabled:opacity-50 cursor-pointer"
        >
          重新选择目录
        </button>
      </div>
    );
  }

  return (
    <div ref={containerRef} className="h-full min-h-0 flex overflow-hidden">
      {/* Left Column: NotesList */}
      {!listCollapsed && (
        <aside
          style={{ width: listWidth }}
          className="shrink-0 h-full min-h-0 flex flex-col bg-stone-100/40 dark:bg-stone-900/40 select-none overflow-hidden"
          aria-label="笔记列表"
        >
          {/* Top Action Bar */}
          <div className="p-2.5 border-b border-stone-200/70 dark:border-stone-800/70 flex items-center justify-between gap-2 shrink-0">
            <div className="flex items-center space-x-2 min-w-0">
              <h2 className="text-xs font-semibold text-stone-800 dark:text-stone-200 truncate">
                全部笔记
              </h2>
              <span className="text-[11px] font-mono text-muted-foreground">
                {notes.length}
              </span>
              {loading && <Loader2 className="w-3 h-3 text-stone-400 animate-spin shrink-0" />}
            </div>

            <div className="flex items-center space-x-1 shrink-0">
              {/* Split Button: New Draft (default) / Dropdown */}
              <div className="relative inline-flex items-stretch rounded-md shadow-2xs" ref={createMenuRef}>
                <button
                  type="button"
                  onClick={handleStartCreateDraft}
                  className="flex items-center space-x-1 px-2.5 py-1 rounded-l-md bg-[var(--pata-accent-solid)] hover:bg-[var(--pata-accent-solid-hover)] text-[var(--pata-accent-on-solid)] text-xs font-medium transition cursor-pointer"
                  title="新建草稿"
                >
                  <Plus className="w-3.5 h-3.5" />
                  <span>新建草稿</span>
                </button>
                <button
                  type="button"
                  onClick={() => setCreateMenuOpen((v) => !v)}
                  className="flex items-center justify-center px-1 py-1 rounded-r-md bg-[var(--pata-accent-solid)] hover:bg-[var(--pata-accent-solid-hover)] border-l border-white/20 text-[var(--pata-accent-on-solid)] text-xs transition cursor-pointer"
                  title="更多新建选项"
                >
                  <ChevronDown className="w-3.5 h-3.5" />
                </button>
                {createMenuOpen && (
                  <div className="absolute right-0 top-full mt-1 w-44 rounded-lg border border-[var(--pata-border)] bg-white dark:bg-stone-900 shadow-lg py-1 z-30">
                    <button
                      type="button"
                      onClick={() => {
                        setCreateMenuOpen(false);
                        handleStartCreateDraft();
                      }}
                      className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer"
                    >
                      <FileText className="w-3.5 h-3.5 text-stone-400" />
                      <span>新建草稿</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setCreateMenuOpen(false);
                        handleStartCreateFormalNote();
                      }}
                      className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer"
                    >
                      <FileText className="w-3.5 h-3.5 text-interaction-600 dark:text-interaction-400" />
                      <span>新建笔记</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setCreateMenuOpen(false);
                        handleStartCreateAudioNote();
                      }}
                      className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer"
                    >
                      <Volume2 className="w-3.5 h-3.5 text-interaction-600 dark:text-interaction-400" />
                      <span>从音频创建逐字稿</span>
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* List Error Banner */}
          {listError && (
            <div className="m-2 p-2 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center space-x-1.5">
              <AlertCircle className="w-3.5 h-3.5 text-rose-600 shrink-0" />
              <span className="truncate">加载列表失败: {listError}</span>
            </div>
          )}

          {/* Audio Note Creation Error */}
          {createAudioNoteError && (
            <div className="m-2 p-2 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 text-xs flex items-center justify-between space-x-1">
              <span className="truncate">{createAudioNoteError}</span>
              <button
                type="button"
                onClick={() => setCreateAudioNoteError(null)}
                className="text-muted-foreground hover:text-stone-600 text-[11px]"
              >
                关闭
              </button>
            </div>
          )}

          {/* Scrollable Groups Container */}
          <div className="flex-1 min-h-0 overflow-y-auto p-2 space-y-3">
            {/* Group 1: 草稿 */}
            <div className="space-y-1">
              <div
                className="w-full flex items-center justify-between px-1.5 py-1 text-xs font-semibold text-muted-foreground hover:text-stone-800 dark:hover:text-stone-200 cursor-pointer rounded"
                onClick={() => setIsDraftsCollapsed((v) => !v)}
              >
                <div className="flex items-center space-x-1.5 min-w-0">
                  {isDraftsCollapsed ? (
                    <ChevronRight className="w-3 h-3 text-stone-400 shrink-0" />
                  ) : (
                    <ChevronDown className="w-3 h-3 text-stone-400 shrink-0" />
                  )}
                  <span>草稿</span>
                  <span className="text-[11px] font-mono px-1.5 py-0.2 rounded-full bg-stone-200/60 dark:bg-stone-800 text-muted-foreground">
                    {displayedDrafts.length}
                  </span>
                </div>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    handleStartCreateDraft();
                  }}
                  className="p-1 rounded text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 transition cursor-pointer"
                  title="新建草稿"
                >
                  <Plus className="w-3.5 h-3.5" />
                </button>
              </div>

              {!isDraftsCollapsed && (
                <div className="space-y-0.5 pl-1">
                  {displayedDrafts.length === 0 ? (
                    <div className="px-3 py-2 text-xs text-muted-foreground italic">
                      暂无草稿
                    </div>
                  ) : (
                    displayedDrafts.map((n) => {
                      const isSelected = selectedNoteId === n.id;
                      const excerpt = getDraftExcerpt(n.body);
                      return (
                        <div
                          key={n.id}
                          id={`note-item-${n.id}`}
                          data-selected={isSelected}
                          onClick={() => handleSelectNote(n.id)}
                          onContextMenu={(e) => {
                            e.preventDefault();
                            setContextMenu({
                              x: e.clientX,
                              y: e.clientY,
                              note: n,
                            });
                          }}
                          className={`group px-2.5 py-1.5 rounded-lg text-[13px] cursor-pointer select-none transition ${
                            isSelected
                              ? 'bg-stone-200/80 dark:bg-stone-800 text-stone-900 dark:text-stone-100 font-medium'
                              : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/50 dark:hover:bg-stone-800/40'
                          }`}
                        >
                          {excerpt ? (
                            <p className="line-clamp-2 leading-relaxed break-words font-sans">
                              {excerpt}
                            </p>
                          ) : (
                            <p className="italic text-muted-foreground">
                              (空草稿)
                            </p>
                          )}
                        </div>
                      );
                    })
                  )}
                </div>
              )}
            </div>

            {/* Group 2: 笔记 */}
            <div className="space-y-1">
              <div
                className="w-full flex items-center justify-between px-1.5 py-1 text-xs font-semibold text-muted-foreground hover:text-stone-800 dark:hover:text-stone-200 cursor-pointer rounded"
                onClick={() => setIsNotesCollapsed((v) => !v)}
              >
                <div className="flex items-center space-x-1.5 min-w-0">
                  {isNotesCollapsed ? (
                    <ChevronRight className="w-3 h-3 text-stone-400 shrink-0" />
                  ) : (
                    <ChevronDown className="w-3 h-3 text-stone-400 shrink-0" />
                  )}
                  <span>笔记</span>
                  <span className="text-[11px] font-mono px-1.5 py-0.2 rounded-full bg-stone-200/60 dark:bg-stone-800 text-muted-foreground">
                    {displayedFormalNotes.length}
                  </span>
                </div>
              </div>

              {!isNotesCollapsed && (
                <div className="space-y-0.5 pl-1">
                  {displayedFormalNotes.length === 0 ? (
                    <div className="px-3 py-2 text-xs text-muted-foreground italic">
                      暂无笔记
                    </div>
                  ) : (
                    displayedFormalNotes.map((n) => {
                      const isSelected = selectedNoteId === n.id;
                      return (
                        <div
                          key={n.id}
                          id={`note-item-${n.id}`}
                          data-selected={isSelected}
                          onClick={() => handleSelectNote(n.id)}
                          onContextMenu={(e) => {
                            e.preventDefault();
                            setContextMenu({
                              x: e.clientX,
                              y: e.clientY,
                              note: n,
                            });
                          }}
                          className={`group px-2.5 py-1.5 rounded-lg text-[13px] cursor-pointer select-none transition flex items-center space-x-1.5 ${
                            isSelected
                              ? 'bg-stone-200/80 dark:bg-stone-800 text-stone-900 dark:text-stone-100 font-medium'
                              : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/50 dark:hover:bg-stone-800/40'
                          }`}
                        >
                          {isAudioTranscriptNote(n) && (
                            <Volume2 className="w-3.5 h-3.5 text-interaction-600 dark:text-interaction-400 shrink-0" />
                          )}
                          <span className="truncate">{n.title || '未命名笔记'}</span>
                        </div>
                      );
                    })
                  )}
                </div>
              )}
            </div>
          </div>
        </aside>
      )}

      {/* Resizer Divider between left list and right editor */}
      {!listCollapsed && (
        <div
          role="separator"
          aria-label="调整笔记列表宽度"
          aria-orientation="vertical"
          aria-valuemin={MIN_NOTES_LIST_WIDTH}
          aria-valuemax={MAX_NOTES_LIST_WIDTH}
          aria-valuenow={listWidth}
          tabIndex={0}
          onKeyDown={handleDividerKeyDown}
          onPointerDown={handleDividerPointerDown}
          onPointerMove={handleDividerPointerMove}
          onPointerUp={handleDividerPointerUp}
          onPointerCancel={handleDividerPointerUp}
          className="relative z-10 w-px shrink-0 bg-stone-200/70 dark:bg-stone-800/70 hover:bg-stone-400 dark:hover:bg-stone-600 cursor-col-resize touch-none no-drag-region focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--pata-accent-focus)] before:absolute before:inset-y-0 before:-left-1.5 before:w-3 before:cursor-col-resize before:touch-none"
          title="拖拽调整笔记列表宽度"
        />
      )}

      {/* Right Column: NoteEditor or Empty State */}
      <div className="flex-1 min-w-0 min-h-0 flex flex-col overflow-hidden bg-stone-50 dark:bg-stone-900">
        {selectedNoteId ? (
          <NoteEditor
            key={editorKey}
            noteId={selectedNoteId}
            isNew={isNewDraft}
            isDraftType={isDraftType}
            listCollapsed={listCollapsed}
            onToggleListCollapse={() => setListCollapsed(false)}
            returnToTask={returnToTask}
            onOpenNote={handleSelectNote}
            onOpenTask={onOpenTask}
            onNoteUpdated={handleNoteUpdated}
            onNoteCreated={handleNoteCreated}
            onNoteConverted={handleNoteConverted}
            onDeleteCurrentNote={handleDeleteCurrentNote}
            leaveGuardRef={leaveGuardRef}
            onDraftCheck={onDraftCheck}
            onOpenSettings={onOpenSettings}
            tagNames={tagNames}
            onVaultDataChanged={onVaultDataChanged}
          />
        ) : (
          <div className="flex-1 flex flex-col items-center justify-center p-8 text-center text-stone-400 select-none">
            <FileText className="w-10 h-10 mb-3 text-stone-300 dark:text-stone-700" />
            <p className="text-sm font-medium text-stone-600 dark:text-stone-400">选择笔记开始阅读或编辑</p>
            <p className="text-xs text-muted-foreground mt-1 mb-4">或者直接创建新草稿随手记录</p>
            <Button
              variant="outline"
              size="sm"
              onClick={handleStartCreateDraft}
              className="text-xs cursor-pointer"
            >
              <Plus className="w-3.5 h-3.5 mr-1" />
              新建草稿
            </Button>
          </div>
        )}
      </div>

      {/* Missing Key Modal for Audio */}
      <ConfirmDialog
        open={showMissingKeyModal}
        variant="warning"
        title="需配置语音转写 API Key"
        description="音频逐字稿生成依赖阿里云百炼 DashScope 语音服务。请先在「设置 - 语音转写」中配置 API Key。"
        confirmText="前往设置"
        cancelText="取消"
        onCancel={() => setShowMissingKeyModal(false)}
        onConfirm={() => {
          setShowMissingKeyModal(false);
          onOpenSettings?.('transcription');
        }}
      />

      {/* Creating Audio Note Loading Overlay */}
      {creatingAudioNote && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-xs p-4">
          <div className="rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 px-6 py-4 shadow-xl flex items-center space-x-3 text-xs font-medium text-stone-700 dark:text-stone-200">
            <Loader2 className="w-4 h-4 animate-spin text-interaction-600" />
            <span>正在导入音频并创建逐字稿笔记...</span>
          </div>
        </div>,
        document.body
      )}

      {/* Context Menu for List Item */}
      {contextMenu && createPortal(
        <div
          ref={contextMenuRef}
          className="pata-fade fixed z-50 rounded-lg border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900 shadow-xl py-1 min-w-[140px]"
          style={{
            left: `${Math.min(contextMenu.x, window.innerWidth - 150)}px`,
            top: `${Math.min(contextMenu.y, window.innerHeight - 110)}px`,
          }}
          onMouseDown={(e) => e.stopPropagation()}
          onClick={(e) => e.stopPropagation()}
        >
          <button
            type="button"
            onClick={async (e) => {
              e.stopPropagation();
              const note = contextMenu.note;
              setContextMenu(null);
              try {
                const path = await VaultService.GetNotePath(note.id);
                if (path) {
                  const ok = await copyToClipboard(path);
                  if (ok) {
                    showToast('已复制绝对路径');
                  } else {
                    showToast('复制到剪贴板失败');
                  }
                } else {
                  showToast('获取笔记路径失败');
                }
              } catch (err: any) {
                console.error('Failed to copy note path:', err);
                showToast(err?.message || '复制路径失败');
              }
            }}
            className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer whitespace-nowrap"
          >
            <Copy className="w-3.5 h-3.5 text-stone-400 shrink-0" />
            <span>复制绝对路径</span>
          </button>
          <button
            type="button"
            onClick={async (e) => {
              e.stopPropagation();
              const note = contextMenu.note;
              setContextMenu(null);
              try {
                await VaultService.RevealNoteInFinder(note.id);
              } catch (err: any) {
                console.error('Failed to reveal note in Finder:', err);
                showToast(err?.message || '在 Finder 中打开失败');
              }
            }}
            className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 transition text-left cursor-pointer whitespace-nowrap"
          >
            <FolderOpen className="w-3.5 h-3.5 text-stone-400 shrink-0" />
            <span>在 Finder 中打开</span>
          </button>
          <div className="my-1 border-t border-stone-100 dark:border-stone-800" />
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              const note = contextMenu.note;
              setContextMenu(null);
              setNoteToDelete(note);
            }}
            className="w-full flex items-center space-x-2 px-3 py-1.5 text-xs text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 transition text-left cursor-pointer whitespace-nowrap"
          >
            <Trash2 className="w-3.5 h-3.5 shrink-0" />
            <span>{contextMenu.note.draft ? '删除草稿' : '删除笔记'}</span>
          </button>
        </div>,
        document.body
      )}

      {/* Confirmation Modal for Deleting from List */}
      <ConfirmDialog
        open={Boolean(noteToDelete)}
        variant="destructive"
        title={noteToDelete?.draft ? '确认删除草稿？' : '确认删除笔记？'}
        description={
          <div className="space-y-1">
            <span>
              {noteToDelete?.draft
                ? '此草稿文件将从 Vault 中永久删除，此操作不可撤销。'
                : `笔记「${noteToDelete?.title || '未命名'}」的文件将从 Vault 中永久删除，此操作不可撤销。`}
            </span>
            {deleteListError && (
              <p className="text-xs text-rose-600 dark:text-rose-400 font-medium pt-1">
                {deleteListError}
              </p>
            )}
          </div>
        }
        confirmText={isDeletingFromList ? '删除中...' : '确认删除'}
        cancelText="取消"
        onCancel={() => {
          setNoteToDelete(null);
          setDeleteListError(null);
        }}
        onConfirm={handleConfirmDeleteFromList}
      />

      {/* Non-blocking Toast Notification */}
      {toastMessage && createPortal(
        <div
          role="status"
          aria-live="polite"
          className="pata-fade fixed bottom-6 left-1/2 -translate-x-1/2 z-50 px-3.5 py-1.5 rounded-full bg-stone-900/90 dark:bg-stone-100/90 text-white dark:text-stone-900 text-xs font-medium shadow-lg backdrop-blur pointer-events-none transition-all duration-200 flex items-center space-x-1.5"
        >
          <Check className="w-3.5 h-3.5 text-emerald-400 dark:text-emerald-600 shrink-0" />
          <span>{toastMessage}</span>
        </div>,
        document.body
      )}
    </div>
  );
}
