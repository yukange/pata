import { useState, useEffect, useCallback, useRef } from 'react';
import { flushSync } from 'react-dom';
import { Events } from '@wailsio/runtime';
import {
  Calendar,
  CheckSquare,
  FileText,
  Hash,
  Search,
  AlertTriangle,
  X,
  Settings,
  Download,
  Clock,
  RefreshCw,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/internal/app/vaultservice';
import * as UpdaterService from '../bindings/pata/internal/app/updaterservice';
import { VaultStatus, VaultHealth, UpdateStatus } from '../bindings/pata/internal/app/models';
import { TagOverviewItem } from '../bindings/pata/internal/storage/markdown/models';
import { Dialog, DialogContent, DialogTitle } from './components/ui/dialog';
import { Button } from './components/ui/button';
import { TasksView } from './TasksView';
import { TodayView } from './TodayView';
import { NotesView } from './NotesView';
import { TagView } from './TagView';
import { SettingsView } from './SettingsView';
import { SearchOverlay } from './SearchOverlay';
import { PataLogo } from './components/PataLogo';
import { registerTitlebarLogo, playLogoLaunch, playLogoClick, playLogoHover } from './logoAnimation';
import { isVirtualAllTag } from './tagAll';
import { DetailSplit, useDetailOrigin } from './DetailSplit';
import { TaskDetailPanel, TaskDetailHandle } from './TaskDetailPanel';
import { useAccentColor } from './useAccentColor';

function SidebarToggleIcon({ collapsed }: { collapsed: boolean }) {
  return (
    <svg viewBox="0 0 16 16" className="w-4 h-4" aria-hidden="true">
      <rect
        x="2.5"
        y="3.5"
        width="4"
        height="9"
        rx="1"
        fill="currentColor"
        className={collapsed ? 'opacity-0' : 'opacity-30'}
      />
      <g fill="none" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round">
        <rect x="1.75" y="2.75" width="12.5" height="10.5" rx="2.25" />
        <path d="M6.75 2.75v10.5" />
      </g>
    </svg>
  );
}

export default function App() {
  const titlebarLogoRef = useRef<SVGSVGElement | null>(null);
  const [activeNav, setActiveNav] = useState<'today' | 'tasks' | 'notes' | 'tag'>('today');
  const [selectedTag, setSelectedTag] = useState<string | null>(null);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(() => {
    try {
      const stored = localStorage.getItem('pata_sidebar_collapsed');
      if (stored !== null) return stored === 'true';
      return true; // 默认收起，无论窗口大小
    } catch {
      return true;
    }
  });
  const [sidebarWidth, setSidebarWidth] = useState(240);
  const [, setIsResizing] = useState(false); // 手柄无高亮，仅保留状态位供拖拽逻辑判断扩展

  useEffect(() => {
    try { localStorage.setItem('pata_sidebar_collapsed', String(sidebarCollapsed)); }
    catch { /* 本地偏好不可用时仍可在当前会话切换。 */ }
  }, [sidebarCollapsed]);

  // Settings & Theme state
  const accent = useAccentColor();
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [settingsSection, setSettingsSection] = useState<'appearance' | 'storage' | 'transcription' | 'updater' | null>(null);
  const [themeMode, setThemeMode] = useState<'system' | 'light' | 'dark'>(() => {
    try {
      const cached = localStorage.getItem('pata_theme');
      if (cached === 'light' || cached === 'dark' || cached === 'system') {
        return cached;
      }
    } catch {
      // ignore
    }
    return 'system';
  });

  // Updater & Toast state
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus | null>(null);
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
    }, 3200);
  }, []);

  // Central Draft Checking Registry
  const draftCheckersRef = useRef<Map<string, () => boolean>>(new Map());
  const registerDraftChecker = useCallback((id: string, checker: () => boolean) => {
    draftCheckersRef.current.set(id, checker);
    return () => {
      draftCheckersRef.current.delete(id);
    };
  }, []);

  const checkAllDrafts = useCallback((): boolean => {
    if (detailRef.current?.hasDraft?.()) {
      return true;
    }
    for (const checker of draftCheckersRef.current.values()) {
      if (checker()) {
        return true;
      }
    }
    return false;
  }, []);

  // Vault state (single vault, D18)
  const [vaultStatus, setVaultStatus] = useState<VaultStatus | null>(null);
  const [vaultBusy, setVaultBusy] = useState(false);
  const [rescanError, setRescanError] = useState<string | null>(null);
  const [detailSelection, setDetailSelection] = useState<{ taskId: string; planContext?: { date: string; isToday: boolean } } | null>(null);
  const [detailRevision, setDetailRevision] = useState(0);
  const detailRef = useRef<TaskDetailHandle>(null);
  const detailOrigin = useDetailOrigin();
  const [focusNoteId, setFocusNoteId] = useState<string | null>(null);

  // Global tags state
  const [tags, setTags] = useState<TagOverviewItem[]>([]);
  const [tagsLoading, setTagsLoading] = useState(false);

  // Vault health state
  const [health, setHealth] = useState<VaultHealth | null>(null);
  const [showHealthModal, setShowHealthModal] = useState(false);

  // 侧栏切换会替换 SVG；重新绑定当前 Logo，启动动画仍只播放一次。
  useEffect(() => {
    const unregister = registerTitlebarLogo(titlebarLogoRef.current);
    const launchFrame = requestAnimationFrame(playLogoLaunch);
    return () => {
      cancelAnimationFrame(launchFrame);
      unregister();
    };
  }, [sidebarCollapsed]);

  // Global search overlay state
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  // 只保护页面内的草稿；右侧 Inspector 的草稿由它自己保护。
  const leaveGuardRef = useRef<(() => Promise<boolean>) | null>(null);
  const guarded = useCallback(async (go: () => void) => {
    if (leaveGuardRef.current && !(await leaveGuardRef.current())) {
      setIsSettingsOpen(false);
      return;
    }
    go();
  }, []);

  const goNav = (nav: 'today' | 'tasks' | 'notes') => {
    void guarded(() => {
      setIsSettingsOpen(false);
      if (nav !== activeNav) setActiveNav(nav);
    });
  };

  const handleOpenSettings = useCallback((section?: 'appearance' | 'storage' | 'transcription' | 'updater') => {
    void guarded(() => {
      setSettingsSection(section || null);
      setIsSettingsOpen(true);
    });
  }, [guarded]);

  const isSettingsOpenRef = useRef(isSettingsOpen);
  isSettingsOpenRef.current = isSettingsOpen;
  const handleOpenSettingsRef = useRef(handleOpenSettings);
  handleOpenSettingsRef.current = handleOpenSettings;

  // 一个应用级 Inspector，跨工作区页面保持任务选择和草稿。
  const handleOpenTask = async (taskID: string, planContext?: { date: string; isToday: boolean }) => {
    if (detailSelection?.taskId !== taskID && detailRef.current && !(await detailRef.current.confirmLeave())) return false;
    if (!detailSelection) detailOrigin.capture();
    setIsSettingsOpen(false);
    setDetailSelection({ taskId: taskID, planContext });
    return true;
  };

  const closeInspector = () => {
    setDetailSelection(null);
    detailOrigin.restore();
  };

  const guardInspectedTask = async (id: string): Promise<boolean> =>
    detailSelection?.taskId !== id || ((await detailRef.current?.confirmLeave()) ?? true);

  const afterTaskWrite = async (id: string) => {
    if (detailSelection?.taskId === id) await detailRef.current?.reload();
  };

  const handleTodayDateSelected = useCallback((date: string) => {
    setDetailSelection((prev) =>
      prev?.planContext && prev.planContext.date !== date ? { ...prev, planContext: undefined } : prev
    );
  }, []);

  const [noteOrigin, setNoteOrigin] = useState<{ nav: 'today' | 'tasks' | 'tag'; taskId: string } | null>(null);
  const [todayDate, setTodayDate] = useState<string | null>(null);

  const handleOpenTodayDate = (date: string) => {
    void guarded(() => {
      setIsSettingsOpen(false);
      setSelectedTag(null);
      setTodayDate(date);
      setActiveNav('today');
    });
  };

  const handleOpenNote = (noteID: string, fromTaskId?: string) => {
    void guarded(() => {
      setIsSettingsOpen(false);
      setNoteOrigin(fromTaskId && (activeNav === 'today' || activeNav === 'tasks' || activeNav === 'tag') ? { nav: activeNav, taskId: fromTaskId } : null);
      setActiveNav('notes');
      setFocusNoteId(noteID);
    });
  };
  const returnToOrigin = async () => {
    if (!noteOrigin) return;
    // 回到来源时优先沿用仍然打开的同一任务（保留 Today 的计划上下文）。
    if (detailSelection?.taskId !== noteOrigin.taskId && !(await handleOpenTask(noteOrigin.taskId))) return;
    setIsSettingsOpen(false);
    setActiveNav(noteOrigin.nav);
    setNoteOrigin(null);
  };

  const handleSelectTag = (tag: string) => {
    void guarded(() => {
      setIsSettingsOpen(false);
      setSelectedTag(tag);
      setActiveNav('tag');
    });
  };

  const handleSelectAllTags = () => {
    void guarded(() => {
      setIsSettingsOpen(false);
      setSelectedTag(null);
      setActiveNav('tag');
    });
  };

  const loadTags = useCallback(async () => {
    try {
      setTagsLoading(true);
      const items = await VaultService.GetTagOverview();
      setTags((items || []).filter((it): it is TagOverviewItem => it !== null));
    } catch (err) {
      console.error('Failed to load tag overview:', err);
    } finally {
      setTagsLoading(false);
    }
  }, []);

  const refreshVault = useCallback(async () => {
    try {
      const st = await VaultService.GetVaultStatus();
      setVaultStatus(st);
      if (st && st.open) {
        await loadTags();
        try {
          const h = await VaultService.GetVaultHealth();
          setHealth(h);
        } catch (err) {
          console.error('Failed to get vault health:', err);
          setHealth(null);
        }
      } else {
        setTags([]);
        setHealth(null);
      }
    } catch (err) {
      console.error('Failed to refresh vault status:', err);
    }
  }, [loadTags]);

  const handleInspectorChanged = () => {
    setDetailRevision((revision) => revision + 1);
    void refreshVault();
  };

  const removeTaskFromDayPlan = async (taskId: string, date: string): Promise<boolean> => {
    try {
      const plan = await VaultService.GetDayPlan(date);
      const existing = (plan?.task_ids ?? []).filter((id): id is string => typeof id === 'string');
      await VaultService.SaveDayPlan(date, existing.filter((id) => id !== taskId));
      handleInspectorChanged();
      return true;
    } catch (err) {
      console.error('Failed to remove task from day plan:', err);
      return false;
    }
  };

  const vaultPathForInspectorRef = useRef<string | null>(null);
  useEffect(() => {
    const path = vaultStatus?.path ?? null;
    if (vaultPathForInspectorRef.current !== null && vaultPathForInspectorRef.current !== path) {
      setDetailSelection(null);
    }
    vaultPathForInspectorRef.current = path;
  }, [vaultStatus?.path]);

  // Fetch vault status on load
  useEffect(() => {
    refreshVault();
  }, [refreshVault]);

  // Subscribe to vault:changed application events
  useEffect(() => {
    const unsubscribe = Events.On('vault:changed', () => {
      refreshVault();
    });

    return () => {
      unsubscribe();
    };
  }, [refreshVault]);

  // Global keyboard shortcuts for search (⌘K / ⌘P) and settings (⌘,)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // ⌘, to toggle settings works globally
      if ((e.metaKey || e.ctrlKey) && e.key === ',') {
        e.preventDefault();
        if (isSettingsOpen) {
          setIsSettingsOpen(false);
        } else {
          handleOpenSettings();
        }
        return;
      }

      const target = e.target as HTMLElement | null;
      if (target?.isContentEditable || target?.closest?.('.vditor')) {
        return;
      }

      if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'p' || e.key === 'K' || e.key === 'P')) {
        e.preventDefault();
        setIsSearchOpen((prev) => !prev);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [isSettingsOpen]);

  // Load updater status on startup and subscribe to updater/menu events
  useEffect(() => {
    void UpdaterService.GetUpdateStatus()
      .then((st) => setUpdateStatus(st))
      .catch((err) => console.error('Failed to get update status:', err));

    const unsubState = Events.On('pata:updater:state-changed', (e: any) => {
      const data = e?.data ?? e;
      if (data) setUpdateStatus(data as UpdateStatus);
    });

    const unsubManualFeedback = Events.On('pata:updater:manual-feedback', (e: any) => {
      const msg = typeof e?.data === 'string' ? e.data : (typeof e === 'string' ? e : '');
      if (msg) showToast(msg);
    });

    const unsubReady = Events.On('pata:updater:ready-to-apply', async () => {
      const hasDrafts = checkAllDrafts();
      if (!hasDrafts) {
        try {
          await UpdaterService.ApplyUpdateAndRestart();
        } catch (err: any) {
          showToast(err?.message || '重启更新失败');
        }
      } else {
        await UpdaterService.SetWaitingInstall();
      }
    });

    const unsubMenuSettings = Events.On('menu:open-settings', () => {
      if (!isSettingsOpenRef.current) {
        handleOpenSettingsRef.current();
      }
    });

    const unsubMenuCheckUpdates = Events.On('menu:check-updates', () => {
      showToast('正在检查更新…');
    });

    return () => {
      unsubState();
      unsubManualFeedback();
      unsubReady();
      unsubMenuSettings();
      unsubMenuCheckUpdates();
    };
  }, [checkAllDrafts, showToast]);

  const handleStartDownload = async () => {
    try {
      await UpdaterService.StartDownload();
    } catch (err: any) {
      showToast(err?.message || '下载更新失败');
    }
  };

  const handleWaitingInstallClick = async () => {
    const hasDrafts = checkAllDrafts();
    if (hasDrafts) {
      showToast('请先保存当前编辑');
    } else {
      try {
        await UpdaterService.ApplyUpdateAndRestart();
      } catch (err: any) {
        showToast(err?.message || '重启更新失败');
      }
    }
  };

  const handleRetryUpdate = async () => {
    try {
      if (!updateStatus?.available_version) {
        // If no version was identified yet (e.g. check stage failed), retry checking
        await UpdaterService.CheckForUpdate(true);
      } else {
        await UpdaterService.StartDownload();
      }
    } catch (err: any) {
      showToast(err?.message || '重试更新失败');
    }
  };

  const handleTodayDraftCheck = useCallback(
    (checker: () => boolean) => registerDraftChecker('today', checker),
    [registerDraftChecker]
  );

  const handleNotesDraftCheck = useCallback(
    (checker: () => boolean) => registerDraftChecker('notes', checker),
    [registerDraftChecker]
  );

  const renderUpdateButton = (collapsed: boolean = false) => {
    if (!updateStatus) return null;
    const { state, progress_percent, available_version, error_message } = updateStatus;

    if (state === 'available') {
      return (
        <button
          type="button"
          onClick={handleStartDownload}
          aria-label={`发现新版本 v${available_version}，点击开始下载`}
          className={`flex items-center ${collapsed ? 'w-full justify-center' : 'space-x-1'} px-2 py-1.5 rounded-md text-xs font-medium text-interaction-700 dark:text-interaction-400 bg-interaction-50 dark:bg-interaction-950/50 hover:bg-interaction-100 dark:hover:bg-interaction-900/60 border border-interaction-300 dark:border-interaction-800 transition cursor-pointer shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)]`}
          title={`发现新版本 v${available_version}，点击开始下载`}
        >
          <Download className="w-3.5 h-3.5 shrink-0" />
          <span className={collapsed ? 'sr-only' : undefined}>更新</span>
        </button>
      );
    }

    if (state === 'downloading') {
      return (
        <button
          type="button"
          disabled
          aria-label={progress_percent >= 0 ? `正在下载更新: ${progress_percent}%` : '正在下载更新...'}
          className={`flex items-center ${collapsed ? 'w-full justify-center' : 'space-x-1'} px-2 py-1.5 rounded-md text-xs font-medium text-stone-700 dark:text-stone-300 bg-stone-100 dark:bg-stone-800 border border-stone-300 dark:border-stone-700 shrink-0 cursor-default`}
          title={progress_percent >= 0 ? `正在下载更新: ${progress_percent}%` : '正在下载更新...'}
        >
          <Download className="w-3.5 h-3.5 shrink-0 animate-bounce" />
          <span className={collapsed ? 'text-[10px] font-mono ml-1' : undefined}>
            {progress_percent >= 0 ? `${progress_percent}%` : (collapsed ? '…' : '下载中')}
          </span>
        </button>
      );
    }

    if (state === 'staging') {
      return (
        <button
          type="button"
          disabled
          aria-label="校验与暂存中..."
          className={`flex items-center ${collapsed ? 'w-full justify-center' : 'space-x-1'} px-2 py-1.5 rounded-md text-xs font-medium text-stone-700 dark:text-stone-300 bg-stone-100 dark:bg-stone-800 border border-stone-300 dark:border-stone-700 shrink-0 cursor-default`}
          title="校验与暂存中..."
        >
          <RefreshCw className="w-3.5 h-3.5 shrink-0 animate-spin" />
          <span className={collapsed ? 'text-[10px] font-mono ml-1' : undefined}>100%</span>
        </button>
      );
    }

    if (state === 'waiting_install') {
      return (
        <button
          type="button"
          onClick={handleWaitingInstallClick}
          aria-label="更新已就绪，保存当前编辑后点击重启安装"
          className={`flex items-center ${collapsed ? 'w-full justify-center' : 'space-x-1'} px-2 py-1.5 rounded-md text-xs font-medium text-amber-800 dark:text-amber-300 bg-amber-50 dark:bg-amber-950/60 hover:bg-amber-100 dark:hover:bg-amber-900/60 border border-amber-300 dark:border-amber-800 transition cursor-pointer shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)]`}
          title="更新已就绪，保存当前编辑后点击重启安装"
        >
          <Clock className="w-3.5 h-3.5 shrink-0" />
          <span className={collapsed ? 'sr-only' : undefined}>等待安装</span>
        </button>
      );
    }

    if (state === 'restarting') {
      return (
        <button
          type="button"
          disabled
          aria-label="正在更新"
          className={`flex items-center ${collapsed ? 'w-full justify-center' : 'space-x-1'} px-2 py-1.5 rounded-md text-xs font-medium text-stone-600 dark:text-stone-400 bg-stone-100 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 shrink-0 cursor-default`}
        >
          <RefreshCw className="w-3.5 h-3.5 shrink-0 animate-spin" />
          <span className={collapsed ? 'sr-only' : undefined}>正在更新</span>
        </button>
      );
    }

    if (state === 'error') {
      return (
        <button
          type="button"
          onClick={handleRetryUpdate}
          aria-label={error_message ? `更新失败: ${error_message}，点击重试` : '更新失败，点击重试'}
          className={`flex items-center ${collapsed ? 'w-full justify-center' : 'space-x-1'} px-2 py-1.5 rounded-md text-xs font-medium text-rose-700 dark:text-rose-400 bg-rose-50 dark:bg-rose-950/60 hover:bg-rose-100 dark:hover:bg-rose-900/60 border border-rose-300 dark:border-rose-800 transition cursor-pointer shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)]`}
          title={error_message ? `更新失败: ${error_message}，点击重试` : '更新失败，点击重试'}
        >
          <RefreshCw className="w-3.5 h-3.5 shrink-0" />
          <span className={collapsed ? 'sr-only' : undefined}>重试更新</span>
        </button>
      );
    }

    return null;
  };

  // Load persisted theme preference from Go backend
  useEffect(() => {
    const initTheme = async () => {
      try {
        const pref = await VaultService.GetThemePreference();
        if (pref === 'light' || pref === 'dark' || pref === 'system') {
          setThemeMode(pref);
          localStorage.setItem('pata_theme', pref);
        }
      } catch (err) {
        console.error('Failed to get theme preference from backend:', err);
      }
    };
    initTheme();
  }, []);

  const handleThemeChange = (mode: 'system' | 'light' | 'dark') => {
    setThemeMode(mode);
    try {
      localStorage.setItem('pata_theme', mode);
    } catch {
      // ignore
    }
    void VaultService.SetThemePreference(mode).catch((err) => {
      console.error('Failed to persist theme preference:', err);
    });
  };

  const handleSelectVault = async () => {
    // 切换 Vault 将卸载当前详情，先保护未保存的任务草稿。
    if (detailRef.current && !(await detailRef.current.confirmLeave())) return;
    setVaultBusy(true);
    try {
      const prevPath = vaultStatus?.path;
      const st = await VaultService.SelectVaultDirectory();
      await refreshVault();
      if (st?.configured && st.path !== prevPath) {
        setDetailSelection(null);
        setFocusNoteId(null);
        setNoteOrigin(null);
        setTodayDate(null);
        setSelectedTag(null);
      }
    } catch (err: any) {
      console.error('Select vault failed:', err);
    } finally {
      setVaultBusy(false);
    }
  };

  const handleRescan = async () => {
    setVaultBusy(true);
    setRescanError(null);
    try {
      await VaultService.RescanVault();
      await refreshVault();
    } catch (err: any) {
      console.error('Rescan failed:', err);
      setRescanError(err?.message || String(err));
    } finally {
      setVaultBusy(false);
    }
  };

  // Theme application
  useEffect(() => {
    const root = document.documentElement;
    if (themeMode === 'dark') {
      root.classList.add('dark');
    } else if (themeMode === 'light') {
      root.classList.remove('dark');
    } else {
      // system: dynamically listen to system dark mode preference
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      const applySystemTheme = () => {
        if (mediaQuery.matches) {
          root.classList.add('dark');
        } else {
          root.classList.remove('dark');
        }
      };
      applySystemTheme();
      mediaQuery.addEventListener('change', applySystemTheme);
      return () => {
        mediaQuery.removeEventListener('change', applySystemTheme);
      };
    }
  }, [themeMode]);

  // View Transitions 驱动侧栏展开/收起过渡切换
  const morphToggleSidebar = useCallback((target?: boolean) => {
    const getNext = (prev: boolean) => (typeof target === 'boolean' ? target : !prev);

    if (
      typeof document === 'undefined' ||
      !('startViewTransition' in document) ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches
    ) {
      setSidebarCollapsed((prev) => {
        const next = getNext(prev);
        try { localStorage.setItem('pata_sidebar_collapsed', String(next)); } catch {}
        return next;
      });
      return;
    }

    const root = document.documentElement;
    root.classList.add('nav-morph');
    const transition = (document as any).startViewTransition(() => {
      flushSync(() => {
        setSidebarCollapsed((prev) => {
          const next = getNext(prev);
          try { localStorage.setItem('pata_sidebar_collapsed', String(next)); } catch {}
          return next;
        });
      });
    });

    const timer = setTimeout(() => {
      try {
        transition.skipTransition();
      } catch {
        // ignore
      }
    }, 1500);

    transition.finished.finally(() => {
      clearTimeout(timer);
      root.classList.remove('nav-morph');
    });
  }, []);

  // 监听 macOS 原生侧栏切换快捷键 ⌃⌘S (以及非 Mac 下的 Ctrl+Shift+S)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const isMac = /^Mac/i.test(navigator.platform);
      const match = isMac
        ? e.metaKey && e.ctrlKey && !e.shiftKey && e.code === 'KeyS'
        : e.ctrlKey && e.shiftKey && !e.metaKey && e.code === 'KeyS';
      if (match && !e.altKey && !e.repeat) {
        e.preventDefault();
        morphToggleSidebar();
      }
    };
    window.addEventListener('keydown', handleKeyDown, true);
    return () => window.removeEventListener('keydown', handleKeyDown, true);
  }, [morphToggleSidebar]);

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    setIsResizing(true);
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'col-resize';
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!e.currentTarget.hasPointerCapture(e.pointerId)) return;
    if (e.clientX < 140) {
      // 拖拽过度向左折叠 (Drag to fold)，保留当前宽度以便下次展开
      setSidebarCollapsed(true);
      morphToggleSidebar(true);
      setIsResizing(false);
      try {
        e.currentTarget.releasePointerCapture(e.pointerId);
      } catch {
        // ignore
      }
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
      return;
    }
    const newWidth = Math.min(Math.max(e.clientX, 180), 380);
    setSidebarWidth(newWidth);
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) {
      try {
        e.currentTarget.releasePointerCapture(e.pointerId);
      } catch {
        // ignore if already released by browser
      }
    }
    setIsResizing(false);
    document.body.style.userSelect = '';
    document.body.style.cursor = '';
  };

  const handleLostPointerCapture = () => {
    setIsResizing(false);
    document.body.style.userSelect = '';
    document.body.style.cursor = '';
  };

  const tagNames = tags.map((t) => t.tag);
  const parseErrorCount = health?.parse_errors?.length ?? 0;
  const danglingRefCount = health?.dangling_refs?.length ?? 0;
  const hasHealthIssues = parseErrorCount > 0 || danglingRefCount > 0;

  const detailPanel = detailSelection ? (
    <TaskDetailPanel
      key={detailSelection.taskId}
      ref={detailRef}
      taskId={detailSelection.taskId}
      closeLabel="关闭详情"
      tagNames={tagNames}
      onClose={closeInspector}
      onChanged={handleInspectorChanged}
      onDeleted={closeInspector}
      onOpenNote={handleOpenNote}
      planDateContext={activeNav === 'today' && detailSelection.planContext
        ? { ...detailSelection.planContext, onRemoveFromPlan: removeTaskFromDayPlan }
        : undefined}
    />
  ) : null;

  return (
    <div className="relative flex flex-col h-screen w-screen overflow-hidden bg-stone-100/60 dark:bg-transparent text-stone-900 dark:text-stone-100 font-sans">
      {/* 4px top edge guard: prevents native window resize from triggering wails:drag */}
      <div className="absolute top-0 left-0 right-0 h-1 no-drag-region z-30 pointer-events-auto" />

      {/* Top window drag strip above main workspace when sidebar is expanded */}
      {!sidebarCollapsed && (
        <div
          style={{ left: `${sidebarWidth}px` }}
          className="absolute top-1 right-0 h-7 drag-region z-10 pointer-events-auto"
        />
      )}

      {/* When sidebar is collapsed: Top Header Strip across the whole window */}
      {sidebarCollapsed && (
        <header className="h-[52px] shrink-0 flex items-center justify-between pl-[84px] pr-4 select-none drag-region z-20">
          {/* Left: Traffic lights clearance (84px pl) -> Logo -> Sidebar toggle button on the right of Logo */}
          <div className="flex items-center gap-2 shrink-0">
            <div id="pata-brand" className="flex items-center gap-2">
              <button
                type="button"
                onClick={playLogoClick}
                onMouseEnter={playLogoHover}
                aria-label="播放 Pata Logo 动画"
                className="pata-logo-button no-drag-region shrink-0 rounded-md cursor-default"
              >
                <PataLogo ref={titlebarLogoRef} className="w-6 h-6" aria-hidden="true" />
              </button>
              <span className="text-sm font-medium text-stone-600 dark:text-stone-300">Pata</span>
            </div>
            <button
              id="pata-toggle"
              type="button"
              onClick={() => {
                setSidebarCollapsed(false);
                morphToggleSidebar(false);
              }}
              aria-label="展开侧栏 (⌃⌘S)"
              title="展开侧栏 (⌃⌘S)"
              aria-expanded={false}
              aria-controls="sidebar-navigation"
              className="h-7 w-7 flex items-center justify-center rounded-md text-stone-500 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 cursor-pointer no-drag-region transition-colors"
            >
              <SidebarToggleIcon collapsed={true} />
            </button>
          </div>

          {/* Center: Segmented Navigation Tabs (Today | Tasks | Notes) */}
          <nav
            aria-label="主导航"
            className="no-drag-region flex items-center gap-1 text-xs"
          >
            <button
              id="pata-nav-today"
              onClick={() => goNav('today')}
              aria-label="Today"
              className={`h-7 flex items-center space-x-1.5 px-2.5 rounded-md font-medium transition cursor-pointer ${
                activeNav === 'today'
                  ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
              }`}
            >
              <Calendar className="w-3.5 h-3.5" />
              <span>Today</span>
            </button>
            <button
              id="pata-nav-tasks"
              onClick={() => goNav('tasks')}
              aria-label="Tasks"
              className={`h-7 flex items-center space-x-1.5 px-2.5 rounded-md font-medium transition cursor-pointer ${
                activeNav === 'tasks'
                  ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
              }`}
            >
              <CheckSquare className="w-3.5 h-3.5" />
              <span>Tasks</span>
            </button>
            <button
              id="pata-nav-notes"
              onClick={() => goNav('notes')}
              aria-label="Notes"
              className={`h-7 flex items-center space-x-1.5 px-2.5 rounded-md font-medium transition cursor-pointer ${
                activeNav === 'notes'
                  ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
              }`}
            >
              <FileText className="w-3.5 h-3.5" />
              <span>Notes</span>
            </button>
          </nav>

          {/* Right: Search, Settings, Updates, Health */}
          <div className="no-drag-region flex items-center gap-1.5 shrink-0">
            <button
              id="pata-search"
              onClick={() => setIsSearchOpen(true)}
              aria-label="全局搜索"
              title="全局搜索 (⌘K / ⌘P)"
              className="w-44 h-7 flex items-center justify-between px-2.5 rounded-md text-xs text-stone-500 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 border border-stone-200/80 dark:border-stone-800/80 bg-stone-50/70 dark:bg-stone-900/50 transition-colors shadow-2xs cursor-pointer group"
            >
              <div className="flex items-center space-x-1.5 truncate">
                <Search className="w-3.5 h-3.5 shrink-0 opacity-70 group-hover:opacity-100" />
                <span>搜索</span>
              </div>
              <kbd className="text-[9px] font-mono opacity-60 bg-stone-200/80 dark:bg-stone-800 px-1 py-0.2 rounded shrink-0">
                ⌘K
              </kbd>
            </button>

            <button
              id="pata-settings"
              onClick={() => {
                if (isSettingsOpen) {
                  setIsSettingsOpen(false);
                } else {
                  handleOpenSettings();
                }
              }}
              aria-label="设置"
              title="设置 (⌘,)"
              className={`h-7 w-7 flex items-center justify-center rounded-md text-xs font-medium transition cursor-pointer ${
                isSettingsOpen
                  ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
              }`}
            >
              <Settings className="w-4 h-4 shrink-0" />
            </button>

            {renderUpdateButton(false)}

            {(hasHealthIssues || rescanError || (vaultStatus?.configured && !vaultStatus?.open)) && (
              <button
                onClick={() => {
                  setShowHealthModal(true);
                }}
                aria-label="Vault 状态与健康异常诊断"
                className={`flex items-center px-1.5 py-1 rounded text-xs font-medium border transition cursor-pointer shrink-0 ${
                  rescanError || !vaultStatus?.open
                    ? 'bg-rose-100 dark:bg-rose-950/70 text-rose-800 dark:text-rose-200 border-rose-300 dark:border-rose-800/80 hover:bg-rose-200/80'
                    : 'bg-amber-100 dark:bg-amber-950/70 text-amber-900 dark:text-amber-200 border-amber-300 dark:border-amber-800/80 hover:bg-amber-200/80'
                }`}
                title="Vault 状态与健康异常诊断"
              >
                <AlertTriangle className={`w-3.5 h-3.5 shrink-0 ${rescanError || !vaultStatus?.open ? 'text-rose-600 dark:text-rose-400' : 'text-amber-600 dark:text-amber-400'}`} />
              </button>
            )}
          </div>
        </header>
      )}

      {/* Main Row: Sidebar (when expanded) + Main Content Area */}
      <div className="flex-1 flex min-h-0 overflow-hidden">
        {!sidebarCollapsed && (
          <div
            id="pata-sidebar"
            style={{ width: `${sidebarWidth}px` }}
            className="relative shrink-0 flex flex-col bg-stone-100/80 dark:bg-stone-950/80 backdrop-blur select-none"
          >
            <div className="h-[52px] shrink-0 drag-region flex items-center pl-[84px] pr-3 select-none overflow-hidden">
              <div id="pata-brand" className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={playLogoClick}
                  onMouseEnter={playLogoHover}
                  aria-label="播放 Pata Logo 动画"
                  className="pata-logo-button no-drag-region shrink-0 rounded-md cursor-default"
                >
                  <PataLogo ref={titlebarLogoRef} className="w-6 h-6" aria-hidden="true" />
                </button>
                <span className="text-sm font-medium text-stone-600 dark:text-stone-300">Pata</span>
              </div>
              <button
                id="pata-toggle"
                type="button"
                onClick={() => {
                  setSidebarCollapsed(true);
                  morphToggleSidebar(true);
                }}
                aria-label="收起侧栏 (⌃⌘S)"
                title="收起侧栏 (⌃⌘S)"
                aria-expanded={true}
                aria-controls="sidebar-navigation"
                className="ml-2 h-7 w-7 flex items-center justify-center rounded-md text-stone-500 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 cursor-pointer no-drag-region transition-colors"
              >
                <SidebarToggleIcon collapsed={false} />
              </button>
            </div>

            {/* Sidebar */}
            <aside
              id="sidebar-navigation"
              className="relative flex flex-col flex-1 min-h-0"
            >
              {/* Resize Handle */}
              <div
                onPointerDown={handlePointerDown}
                onPointerMove={handlePointerMove}
                onPointerUp={handlePointerUp}
                onPointerCancel={handlePointerUp}
                onLostPointerCapture={handleLostPointerCapture}
                className="absolute top-0 right-0 w-1 h-full cursor-col-resize no-drag-region z-20 touch-none"
                title="拖拽调整侧边栏宽度"
              />

              {/* Primary Navigation */}
              <div className="flex-1 overflow-y-auto px-2 pb-2 space-y-0.5 pt-2">
                <div className="flex gap-1 mb-2">
                  {/* Quick Search */}
                  <button
                    id="pata-search"
                    onClick={() => setIsSearchOpen(true)}
                    aria-label="全局搜索"
                    className="min-w-0 h-8 flex items-center px-2.5 py-1.5 rounded-md text-xs text-stone-500 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 border border-stone-200/80 dark:border-stone-800/80 bg-stone-50/70 dark:bg-stone-900/50 transition-colors shadow-2xs cursor-pointer group flex-1 justify-between"
                    title="全局搜索 (⌘K / ⌘P)"
                  >
                    <div className="flex items-center space-x-2 truncate">
                      <Search className="w-3.5 h-3.5 shrink-0 opacity-70 group-hover:opacity-100" />
                      <span>搜索</span>
                    </div>
                    <kbd className="text-[10px] font-mono opacity-60 bg-stone-200/80 dark:bg-stone-800 px-1 py-0.2 rounded shrink-0">
                      ⌘K
                    </kbd>
                  </button>
                </div>

                <button
                  id="pata-nav-today"
                  onClick={() => goNav('today')}
                  aria-label="Today"
                  className={`w-full flex items-center space-x-2.5 px-2.5 py-2 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    activeNav === 'today'
                      ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                      : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
                  }`}
                  title="Today"
                >
                  <Calendar className="w-4 h-4 shrink-0" />
                  <span>Today</span>
                </button>

                <button
                  id="pata-nav-tasks"
                  onClick={() => goNav('tasks')}
                  aria-label="Tasks"
                  className={`w-full flex items-center space-x-2.5 px-2.5 py-2 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    activeNav === 'tasks'
                      ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                      : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
                  }`}
                  title="Tasks"
                >
                  <CheckSquare className="w-4 h-4 shrink-0" />
                  <span>Tasks</span>
                </button>

                <button
                  id="pata-nav-notes"
                  onClick={() => goNav('notes')}
                  aria-label="Notes"
                  className={`w-full flex items-center space-x-2.5 px-2.5 py-2 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    activeNav === 'notes'
                      ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                      : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
                  }`}
                  title="Notes"
                >
                  <FileText className="w-4 h-4 shrink-0" />
                  <span>Notes</span>
                </button>

                {/* Tags section */}
                <div className="pt-3">
                  <div className="text-[10px] uppercase font-semibold text-stone-400 px-2 mb-1 flex items-center justify-between">
                    <span>全局标签</span>
                    {vaultStatus?.open && (
                      <span className="text-[9px] text-stone-400 font-mono">{tags.length}</span>
                    )}
                  </div>
                  <div className="space-y-0.5 px-1">
                    {!vaultStatus?.open ? (
                      <div className="px-2 py-1.5 text-xs text-stone-400 italic">Vault 尚未打开</div>
                    ) : (
                      <>
                        <button
                          onClick={handleSelectAllTags}
                          className={`w-full flex items-center justify-between px-2 py-1.5 rounded-md text-xs transition-colors min-h-[32px] text-left cursor-pointer ${
                            activeNav === 'tag' && isVirtualAllTag(selectedTag)
                              ? 'bg-stone-200/90 dark:bg-stone-800 text-stone-900 dark:text-stone-100 font-semibold ring-1 ring-[var(--pata-border)]'
                              : 'text-stone-600 dark:text-stone-400 hover:bg-stone-200/50 dark:hover:bg-stone-800/50'
                          }`}
                          title="全部"
                        >
                          <div className="flex items-center space-x-1.5 truncate mr-2">
                            <Hash className="w-3.5 h-3.5 shrink-0 opacity-60" />
                            <span className="truncate">全部</span>
                          </div>
                        </button>

                        {tagsLoading && tags.length === 0 ? (
                          <div className="px-2 py-1.5 text-xs text-stone-400">加载标签...</div>
                        ) : tags.length === 0 ? (
                          <div className="px-2 py-1.5 text-xs text-stone-400 italic">暂无标签</div>
                        ) : (
                          tags.map((item) => (
                            <button
                              key={item.tag}
                              onClick={() => handleSelectTag(item.tag)}
                              className={`w-full flex items-center justify-between px-2 py-1.5 rounded-md text-xs transition-colors min-h-[32px] text-left cursor-pointer ${
                                activeNav === 'tag' && selectedTag === item.tag
                                  ? 'bg-stone-200/90 dark:bg-stone-800 text-stone-900 dark:text-stone-100 font-semibold ring-1 ring-[var(--pata-border)]'
                                  : 'text-stone-600 dark:text-stone-400 hover:bg-stone-200/50 dark:hover:bg-stone-800/50'
                              }`}
                              title={`#${item.tag} (共 ${item.total} 项)`}
                            >
                              <div className="flex items-center space-x-1.5 truncate mr-2">
                                <Hash className="w-3.5 h-3.5 shrink-0 opacity-60" />
                                <span className="truncate">{item.tag}</span>
                              </div>
                              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded-full bg-stone-200/70 dark:bg-stone-800 text-stone-500 dark:text-stone-400 shrink-0">
                                {item.total}
                              </span>
                            </button>
                          ))
                        )}
                      </>
                    )}
                  </div>
                </div>
              </div>

              {/* Sidebar Footer: settings entry + persistent health warning if present */}
              <div className="relative p-2 flex items-center no-drag-region border-t border-stone-200/60 dark:border-stone-800/60 gap-1.5 justify-between">
                <div className="flex items-center gap-1.5 min-w-0">
                  <button
                    id="pata-settings"
                    onClick={() => {
                      if (isSettingsOpen) {
                        setIsSettingsOpen(false);
                      } else {
                        handleOpenSettings();
                      }
                    }}
                    aria-label="设置"
                    className={`flex items-center space-x-2 px-2.5 py-1.5 rounded-md text-xs font-medium transition cursor-pointer ${
                      isSettingsOpen
                        ? 'bg-[var(--pata-accent)] text-[var(--pata-accent-foreground)] shadow-xs'
                        : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
                    }`}
                    title="设置 (⌘,)"
                  >
                    <Settings className="w-4 h-4 shrink-0" />
                    <span>设置</span>
                  </button>

                  {renderUpdateButton(false)}
                </div>

                {(hasHealthIssues || rescanError || (vaultStatus?.configured && !vaultStatus?.open)) && (
                  <button
                    onClick={() => {
                      setShowHealthModal(true);
                    }}
                    aria-label="Vault 状态与健康异常诊断"
                    className={`flex items-center space-x-1 px-1.5 py-1 rounded text-xs font-medium border transition cursor-pointer shrink-0 ${
                      rescanError || !vaultStatus?.open
                        ? 'bg-rose-100 dark:bg-rose-950/70 text-rose-800 dark:text-rose-200 border-rose-300 dark:border-rose-800/80 hover:bg-rose-200/80'
                        : 'bg-amber-100 dark:bg-amber-950/70 text-amber-900 dark:text-amber-200 border-amber-300 dark:border-amber-800/80 hover:bg-amber-200/80'
                    }`}
                    title="Vault 状态与健康异常诊断"
                  >
                    <AlertTriangle className={`w-3.5 h-3.5 shrink-0 ${rescanError || !vaultStatus?.open ? 'text-rose-600 dark:text-rose-400' : 'text-amber-600 dark:text-amber-400'}`} />
                    <span>
                      {rescanError || !vaultStatus?.open
                        ? '异常'
                        : parseErrorCount + danglingRefCount}
                    </span>
                  </button>
                )}
              </div>
            </aside>
          </div>
        )}

        {/* Main Content Area */}
        <main className={`flex-1 flex flex-col min-w-0 overflow-hidden rounded-2xl border border-stone-200/70 dark:border-stone-800/70 shadow-xs bg-stone-50 dark:bg-stone-900 ${
          sidebarCollapsed ? 'mx-2 mb-2' : 'mr-2 my-2'
        }`}>

        {/* Business Views Container (hidden when settings is open, preserving editor DOM/scroll/cursor) */}
        <div
          key={vaultStatus?.path ?? 'unconfigured'}
          className={`flex-1 min-h-0 flex flex-col ${isSettingsOpen ? 'hidden' : ''}`}
        >
          <DetailSplit panel={detailPanel} hidden={activeNav === 'notes'}>
          <div
            className={
              activeNav === 'today' || activeNav === 'tasks' || activeNav === 'tag' || activeNav === 'notes'
                ? 'h-full min-h-0 overflow-hidden'
                : 'h-full overflow-y-auto p-6'
            }
          >
            {activeNav === 'today' && (
              <TodayView
                key={vaultStatus?.path ?? 'today'}
                vaultStatus={vaultStatus}
                onSelectVault={handleSelectVault}
                vaultBusy={vaultBusy}
                onOpenNote={handleOpenNote}
                selectedTaskId={detailSelection?.taskId ?? null}
                onOpenTask={handleOpenTask}
                onGuardTask={guardInspectedTask}
                onTaskWritten={afterTaskWrite}
                onDateSelected={handleTodayDateSelected}
                detailRevision={detailRevision}
                initialDate={todayDate}
                onInitialDateConsumed={() => setTodayDate(null)}
                tagNames={tagNames}
                onVaultDataChanged={refreshVault}
                leaveGuardRef={leaveGuardRef}
                onDraftCheck={handleTodayDraftCheck}
              />
            )}

            {activeNav === 'tasks' && (
              <TasksView
                key={vaultStatus?.path ?? 'tasks'}
                vaultStatus={vaultStatus}
                onSelectVault={handleSelectVault}
                vaultBusy={vaultBusy}
                selectedTaskId={detailSelection?.taskId ?? null}
                onOpenTask={handleOpenTask}
                onGuardTask={guardInspectedTask}
                onTaskWritten={afterTaskWrite}
                detailRevision={detailRevision}
                tagNames={tagNames}
                onVaultDataChanged={refreshVault}
              />
            )}

            {activeNav === 'notes' && (
              <NotesView
                key={vaultStatus?.path ?? 'notes'}
                vaultStatus={vaultStatus}
                onSelectVault={handleSelectVault}
                onRescanVault={handleRescan}
                vaultBusy={vaultBusy}
                focusNoteId={focusNoteId}
                onClearFocusNote={() => setFocusNoteId(null)}
                returnToTask={noteOrigin ? { label: '返回任务', go: returnToOrigin } : null}
                onOpenTask={handleOpenTask}
                leaveGuardRef={leaveGuardRef}
                onDraftCheck={handleNotesDraftCheck}
                onOpenSettings={handleOpenSettings}
                tagNames={tagNames}
                onVaultDataChanged={refreshVault}
              />
            )}

            {activeNav === 'tag' && (
              <TagView
                key={vaultStatus?.path ?? 'tag'}
                selectedTag={selectedTag}
                onOpenNote={handleOpenNote}
                selectedTaskId={detailSelection?.taskId ?? null}
                onOpenTask={handleOpenTask}
                detailRevision={detailRevision}
              />
            )}
          </div>
          </DetailSplit>
        </div>

        {/* Settings View */}
        {isSettingsOpen && (
          <div className="flex-1 min-h-0 overflow-hidden">
            <SettingsView
              themeMode={themeMode}
              onThemeChange={handleThemeChange}
              accent={accent}
              vaultStatus={vaultStatus}
              onSelectVault={handleSelectVault}
              onRescanVault={handleRescan}
              vaultBusy={vaultBusy}
              rescanError={rescanError}
              health={health}
              onOpenHealthModal={() => setShowHealthModal(true)}
              onBack={() => setIsSettingsOpen(false)}
              initialSection={settingsSection}
            />
          </div>
        )}
      </main>
      </div>

      {/* Global Quick Search Overlay */}
      <SearchOverlay
        isOpen={isSearchOpen}
        onClose={() => setIsSearchOpen(false)}
        onOpenTask={handleOpenTask}
        onOpenNote={handleOpenNote}
        onOpenTodayDate={handleOpenTodayDate}
        vaultOpen={vaultStatus?.open}
      />

      {/* Vault Health Detail Modal */}
      <Dialog open={showHealthModal} onOpenChange={setShowHealthModal}>
        <DialogContent maxWidth="lg" padded={false} className="overflow-hidden max-h-[80vh] flex flex-col">
          <div className="flex items-center justify-between px-4 py-3 border-b border-stone-200 dark:border-stone-800">
            <div className="flex items-center space-x-2">
              <AlertTriangle className="w-4 h-4 text-amber-600 dark:text-amber-400" />
              <DialogTitle className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                Vault 降级状态与异常诊断
              </DialogTitle>
            </div>
            <button
              onClick={() => setShowHealthModal(false)}
              className="p-1 rounded-md text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--pata-focus-ring)] cursor-pointer"
              title="关闭"
            >
              <X className="w-4 h-4" />
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-4 space-y-4 text-xs">
            {(!vaultStatus?.open && vaultStatus?.configured) && (
              <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-xs text-rose-700 dark:text-rose-300 space-y-1">
                <div className="font-semibold flex items-center space-x-1.5">
                  <AlertTriangle className="w-3.5 h-3.5 shrink-0 text-rose-600 dark:text-rose-400" />
                  <span>Vault 目录无法打开</span>
                </div>
                <div className="font-mono text-[11px] break-all">{vaultStatus.path}</div>
                <div>{vaultStatus.error || '无法打开当前工作区，请检查权限或在设置中重新选择目录。'}</div>
              </div>
            )}

            {rescanError && (
              <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-xs text-rose-700 dark:text-rose-300 space-y-1">
                <div className="font-semibold flex items-center space-x-1.5">
                  <AlertTriangle className="w-3.5 h-3.5 shrink-0 text-rose-600 dark:text-rose-400" />
                  <span>重新扫描失败</span>
                </div>
                <div className="break-all">{rescanError}</div>
              </div>
            )}

            {parseErrorCount > 0 && (
              <div className="space-y-2">
                <div className="font-semibold text-amber-800 dark:text-amber-300 flex items-center justify-between">
                  <span>文件未识别 (解析失败，已隔离保护)</span>
                  <span className="font-mono text-[11px] bg-amber-100 dark:bg-amber-950 px-1.5 py-0.5 rounded">
                    {parseErrorCount}
                  </span>
                </div>
                <div className="space-y-1.5">
                  {health?.parse_errors?.map((pe, idx) => (
                    <div
                      key={idx}
                      className="p-2.5 rounded-lg border border-amber-200/80 dark:border-amber-900/50 bg-amber-50/60 dark:bg-amber-950/30"
                    >
                      <div className="font-mono text-[11px] text-stone-800 dark:text-stone-200 break-all">
                        {pe.path}
                      </div>
                      <div className="text-stone-600 dark:text-stone-400 mt-1">
                        {pe.reason}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {danglingRefCount > 0 && (
              <div className="space-y-2">
                <div className="font-semibold text-amber-800 dark:text-amber-300 flex items-center justify-between">
                  <span>引用悬空 (关联目标缺失，动态降级)</span>
                  <span className="font-mono text-[11px] bg-amber-100 dark:bg-amber-950 px-1.5 py-0.5 rounded">
                    {danglingRefCount}
                  </span>
                </div>
                <div className="space-y-1.5">
                  {health?.dangling_refs?.map((dr, idx) => (
                    <div
                      key={idx}
                      className="p-2.5 rounded-lg border border-stone-200 dark:border-stone-800 bg-stone-100/50 dark:bg-stone-800/40"
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-stone-800 dark:text-stone-200">
                          [{dr.source_type}:{dr.source_id}] 关联缺失的 {dr.target_type} ({dr.target_id})
                        </span>
                      </div>
                      <div className="font-mono text-[10px] text-stone-400 mt-0.5 break-all">
                        来源文件: {dr.source_path}
                      </div>
                      <div className="text-stone-600 dark:text-stone-400 mt-1">
                        {dr.reason}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="p-2.5 rounded-lg bg-stone-100 dark:bg-stone-800/60 text-stone-500 dark:text-stone-400 text-[11px] leading-relaxed">
              ℹ️ 依据 Pata Local First 规范，异常或未识别文件会被独立隔离保护，不会被程序静默覆盖或删除。在外部编辑器纠正 Frontmatter 或恢复关联后，系统将自动自愈并恢复索引。
            </div>
          </div>

          <div className="px-4 py-2.5 border-t border-stone-200 dark:border-stone-800 flex items-center justify-between bg-stone-100/60 dark:bg-stone-950/60">
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setShowHealthModal(false);
                handleOpenSettings('storage');
              }}
            >
              前往存储设置
            </Button>

            <Button
              variant="secondary"
              size="sm"
              onClick={() => setShowHealthModal(false)}
            >
              关闭
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Non-blocking Toast Notification */}
      {toastMessage && (
        <div
          role="status"
          aria-live="polite"
          className="absolute bottom-5 left-1/2 -translate-x-1/2 z-50 px-3.5 py-1.5 rounded-full bg-stone-900/90 dark:bg-stone-100/90 text-white dark:text-stone-900 text-xs font-medium shadow-lg backdrop-blur pointer-events-none transition-all duration-200"
        >
          {toastMessage}
        </div>
      )}
    </div>
  );
}
