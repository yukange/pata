import { useState, useEffect, useCallback, useRef } from 'react';
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
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { VaultStatus, VaultHealth } from '../bindings/pata/models';
import { TagOverviewItem } from '../bindings/pata/internal/storage/markdown/models';
import { TasksView } from './TasksView';
import { TodayView } from './TodayView';
import { NotesView } from './NotesView';
import { TagView } from './TagView';
import { SettingsView } from './SettingsView';
import { SearchOverlay } from './SearchOverlay';
import { PataLogo } from './components/PataLogo';
import { registerTitlebarLogo, playLogoLaunch } from './logoAnimation';

export default function App() {
  const titlebarLogoRef = useRef<SVGSVGElement | null>(null);
  const [activeNav, setActiveNav] = useState<'today' | 'tasks' | 'notes' | 'tag'>('today');
  const [selectedTag, setSelectedTag] = useState<string | null>(null);
  const [sidebarCollapsed] = useState(false); // 侧栏恒展开，收起功能按走查反馈移除
  const [sidebarWidth, setSidebarWidth] = useState(240);
  const [, setIsResizing] = useState(false); // 手柄无高亮，仅保留状态位供拖拽逻辑判断扩展

  // Settings & Theme state
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [settingsSection, setSettingsSection] = useState<'appearance' | 'storage' | 'transcription' | null>(null);
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

  // Vault state (single vault, D18)
  const [vaultStatus, setVaultStatus] = useState<VaultStatus | null>(null);
  const [vaultBusy, setVaultBusy] = useState(false);
  const [rescanError, setRescanError] = useState<string | null>(null);
  const [focusTaskId, setFocusTaskId] = useState<string | null>(null);
  const [focusNoteId, setFocusNoteId] = useState<string | null>(null);

  // Global tags state
  const [tags, setTags] = useState<TagOverviewItem[]>([]);
  const [tagsLoading, setTagsLoading] = useState(false);

  // Vault health state
  const [health, setHealth] = useState<VaultHealth | null>(null);
  const [showHealthModal, setShowHealthModal] = useState(false);
  const healthTriggerRef = useRef<HTMLElement | null>(null);
  const healthModalRef = useRef<HTMLDivElement>(null);

  // Manage focus movement and restoration for health modal
  useEffect(() => {
    if (showHealthModal) {
      healthTriggerRef.current = document.activeElement as HTMLElement | null;
      const timer = setTimeout(() => {
        healthModalRef.current?.focus();
      }, 50);
      return () => clearTimeout(timer);
    } else {
      if (healthTriggerRef.current && typeof healthTriggerRef.current.focus === 'function') {
        healthTriggerRef.current.focus();
        healthTriggerRef.current = null;
      }
    }
  }, [showHealthModal]);

  // Titlebar logo initialization: play launch animation once on initial app ready
  useEffect(() => {
    const unregister = registerTitlebarLogo(titlebarLogoRef.current);
    playLogoLaunch();
    return () => {
      unregister();
    };
  }, []);

  // Global search overlay state
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [isEditingNote, setIsEditingNote] = useState(false);

  useEffect(() => {
    if (activeNav !== 'notes') {
      setIsEditingNote(false);
    }
  }, [activeNav]);

  // 当前页面登记的离开前确认（任务详情有未保存草稿时返回 false 表示取消离开）
  const leaveGuardRef = useRef<(() => Promise<boolean>) | null>(null);
  const guarded = async (go: () => void) => {
    if (leaveGuardRef.current && !(await leaveGuardRef.current())) {
      setIsSettingsOpen(false);
      return;
    }
    go();
  };
  const goNav = (nav: 'today' | 'tasks' | 'notes') => {
    void guarded(() => {
      setIsSettingsOpen(false);
      if (nav !== activeNav) setActiveNav(nav);
    });
  };

  const handleOpenSettings = (section?: 'appearance' | 'storage' | 'transcription') => {
    void guarded(() => {
      setSettingsSection(section || null);
      setIsSettingsOpen(true);
    });
  };

  const handleOpenTask = (taskID: string) => {
    const go = () => {
      setIsSettingsOpen(false);
      setActiveNav('tasks');
      setFocusTaskId(taskID);
    };
    // 已在 Tasks 且不在设置时由其详情面板自行确认草稿，避免重复提示
    if (activeNav === 'tasks' && !isSettingsOpen) go();
    else void guarded(go);
  };

  // 从任务详情打开笔记时记录来源，笔记页「返回」回到该任务
  const [noteOrigin, setNoteOrigin] = useState<{ nav: 'today' | 'tasks' | 'tag'; taskId: string } | null>(null);
  const [todayTaskId, setTodayTaskId] = useState<string | null>(null);
  const [todayDate, setTodayDate] = useState<string | null>(null);
  const [tagTaskId, setTagTaskId] = useState<string | null>(null);

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
  const returnToOrigin = () => {
    if (!noteOrigin) return;
    setIsSettingsOpen(false);
    setActiveNav(noteOrigin.nav);
    if (noteOrigin.nav === 'tasks') setFocusTaskId(noteOrigin.taskId);
    else if (noteOrigin.nav === 'today') setTodayTaskId(noteOrigin.taskId);
    else if (noteOrigin.nav === 'tag') setTagTaskId(noteOrigin.taskId);
    setNoteOrigin(null);
  };

  const handleSelectTag = (tag: string) => {
    void guarded(() => {
      setIsSettingsOpen(false);
      setSelectedTag(tag);
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
    setVaultBusy(true);
    try {
      const prevPath = vaultStatus?.path;
      const st = await VaultService.SelectVaultDirectory();
      await refreshVault();
      if (st?.configured && st.path !== prevPath) {
        setFocusTaskId(null);
        setFocusNoteId(null);
        setNoteOrigin(null);
        setTodayTaskId(null);
        setTodayDate(null);
        setTagTaskId(null);
        setSelectedTag(null);
        setIsEditingNote(false);
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

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    setIsResizing(true);
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'col-resize';
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!e.currentTarget.hasPointerCapture(e.pointerId)) return;
    const newWidth = Math.min(Math.max(e.clientX, 200), 360);
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

  return (
    <div className="relative flex h-screen w-screen overflow-hidden bg-stone-100/60 dark:bg-transparent text-stone-900 dark:text-stone-100 font-sans">
      {/* 4px top edge guard: prevents native window resize from triggering wails:drag */}
      <div className="absolute top-0 left-0 right-0 h-1 no-drag-region z-30 pointer-events-auto" />

      {/* Left column: lights+logo strip above sidebar, unified background */}
      <div
        style={{ width: `${sidebarWidth}px` }}
        className="relative shrink-0 flex flex-col bg-stone-100/80 dark:bg-stone-950/80 backdrop-blur select-none"
      >
        <div className="h-[52px] shrink-0 drag-region flex items-center pl-[84px] gap-2 select-none">
          <PataLogo ref={titlebarLogoRef} className="w-6 h-6 shrink-0" />
          <span className="text-sm font-medium text-stone-600 dark:text-stone-300">Pata</span>
        </div>

      {/* Sidebar */}
      <aside
        className="relative flex flex-col flex-1 min-h-0"
      >
        {/* Resize Handle (expanded only) */}
        {!sidebarCollapsed && (
          <div
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
            onLostPointerCapture={handleLostPointerCapture}
            className="absolute top-0 right-0 w-1 h-full cursor-col-resize no-drag-region z-20 touch-none"
            title="拖拽调整侧边栏宽度"
          />
        )}

        {/* Primary Navigation */}
        <div className="flex-1 overflow-y-auto px-2 py-2 space-y-0.5">
          {/* Quick Search */}
          <button
            onClick={() => setIsSearchOpen(true)}
            className="w-full flex items-center justify-between px-2.5 py-1.5 mb-2 rounded-md text-xs text-stone-500 dark:text-stone-400 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 border border-stone-200/80 dark:border-stone-800/80 bg-stone-50/70 dark:bg-stone-900/50 transition-colors shadow-2xs cursor-pointer group"
            title="全局搜索 (⌘K / ⌘P)"
          >
            <div className="flex items-center space-x-2 truncate">
              <Search className="w-3.5 h-3.5 shrink-0 opacity-70 group-hover:opacity-100" />
              {!sidebarCollapsed && <span>搜索</span>}
            </div>
            {!sidebarCollapsed && (
              <kbd className="text-[10px] font-mono opacity-60 bg-stone-200/80 dark:bg-stone-800 px-1 py-0.2 rounded shrink-0">
                ⌘K
              </kbd>
            )}
          </button>

          <button
            onClick={() => goNav('today')}
            className={`w-full flex items-center space-x-2.5 px-2.5 py-2 rounded-md text-xs font-medium transition-colors ${
              activeNav === 'today'
                ? 'bg-emerald-700 text-white shadow-xs'
                : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
            }`}
            title="Today"
          >
            <Calendar className="w-4 h-4 shrink-0" />
            {!sidebarCollapsed && <span>Today</span>}
          </button>

          <button
            onClick={() => goNav('tasks')}
            className={`w-full flex items-center space-x-2.5 px-2.5 py-2 rounded-md text-xs font-medium transition-colors ${
              activeNav === 'tasks'
                ? 'bg-emerald-700 text-white shadow-xs'
                : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
            }`}
            title="Tasks"
          >
            <CheckSquare className="w-4 h-4 shrink-0" />
            {!sidebarCollapsed && <span>Tasks</span>}
          </button>

          <button
            onClick={() => goNav('notes')}
            className={`w-full flex items-center space-x-2.5 px-2.5 py-2 rounded-md text-xs font-medium transition-colors ${
              activeNav === 'notes'
                ? 'bg-emerald-700 text-white shadow-xs'
                : 'text-stone-700 dark:text-stone-300 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
            }`}
            title="Notes"
          >
            <FileText className="w-4 h-4 shrink-0" />
            {!sidebarCollapsed && <span>Notes</span>}
          </button>

          {/* Tags section */}
          {!sidebarCollapsed && (
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
                ) : tagsLoading && tags.length === 0 ? (
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
                          ? 'bg-emerald-100/70 dark:bg-emerald-950/60 text-emerald-900 dark:text-emerald-200 font-medium'
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
              </div>
            </div>
          )}
        </div>

        {/* Sidebar Footer: settings entry + persistent health warning if present */}
        {!sidebarCollapsed && (
          <div className="relative p-2 flex items-center justify-between no-drag-region border-t border-stone-200/60 dark:border-stone-800/60">
            <button
              onClick={() => {
                if (isSettingsOpen) {
                  setIsSettingsOpen(false);
                } else {
                  handleOpenSettings();
                }
              }}
              className={`flex items-center space-x-2 px-2.5 py-1.5 rounded-md text-xs font-medium transition cursor-pointer ${
                isSettingsOpen
                  ? 'bg-emerald-700 text-white shadow-xs'
                  : 'text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60'
              }`}
              title="设置 (⌘,)"
            >
              <Settings className="w-4 h-4 shrink-0" />
              <span>设置</span>
            </button>

            {(hasHealthIssues || rescanError || (vaultStatus?.configured && !vaultStatus?.open)) && (
              <button
                onClick={() => {
                  healthTriggerRef.current = document.activeElement as HTMLElement | null;
                  setShowHealthModal(true);
                }}
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
        )}
      </aside>
      </div>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden rounded-2xl border border-stone-200/70 dark:border-stone-800/70 shadow-xs bg-stone-50 dark:bg-stone-900 mt-2 mr-2 mb-2">

        {/* Business Views Container (hidden when settings is open, preserving editor DOM/scroll/cursor) */}
        <div
          key={vaultStatus?.path ?? 'unconfigured'}
          className={`flex-1 min-h-0 flex flex-col ${isSettingsOpen ? 'hidden' : ''}`}
        >
          <div
            className={
              activeNav === 'today' || activeNav === 'tasks' || activeNav === 'tag' || (activeNav === 'notes' && isEditingNote)
                ? 'flex-1 min-h-0 overflow-hidden' // 三栏或编辑页：内部自适应高度
                : 'flex-1 overflow-y-auto p-6'
            }
          >
            {activeNav === 'today' && (
              <TodayView
                key={vaultStatus?.path ?? 'today'}
                vaultStatus={vaultStatus}
                onSelectVault={handleSelectVault}
                vaultBusy={vaultBusy}
                onOpenNote={handleOpenNote}
                initialTaskId={todayTaskId}
                onInitialTaskConsumed={() => setTodayTaskId(null)}
                initialDate={todayDate}
                onInitialDateConsumed={() => setTodayDate(null)}
                tagNames={tagNames}
                onVaultDataChanged={refreshVault}
                leaveGuardRef={leaveGuardRef}
              />
            )}

            {activeNav === 'tasks' && (
              <TasksView
                key={vaultStatus?.path ?? 'tasks'}
                vaultStatus={vaultStatus}
                onSelectVault={handleSelectVault}
                vaultBusy={vaultBusy}
                focusTaskId={focusTaskId}
                onClearFocusTask={() => setFocusTaskId(null)}
                onOpenNote={handleOpenNote}
                tagNames={tagNames}
                onVaultDataChanged={refreshVault}
                leaveGuardRef={leaveGuardRef}
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
                onEditingChange={setIsEditingNote}
                leaveGuardRef={leaveGuardRef}
                onOpenSettings={handleOpenSettings}
              />
            )}

            {activeNav === 'tag' && (
              <TagView
                key={vaultStatus?.path ?? 'tag'}
                selectedTag={selectedTag}
                onOpenNote={handleOpenNote}
                initialTaskId={tagTaskId}
                onInitialTaskConsumed={() => setTagTaskId(null)}
                tagNames={tagNames}
                onVaultDataChanged={refreshVault}
                leaveGuardRef={leaveGuardRef}
              />
            )}
          </div>
        </div>

        {/* Settings View */}
        {isSettingsOpen && (
          <div className="flex-1 min-h-0 overflow-hidden">
            <SettingsView
              themeMode={themeMode}
              onThemeChange={handleThemeChange}
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
      {showHealthModal && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Vault 健康与降级状态"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-stone-900/40 dark:bg-black/60 backdrop-blur-xs select-none"
          onClick={() => setShowHealthModal(false)}
          onKeyDown={(e) => {
            if (e.key === 'Escape') setShowHealthModal(false);
          }}
        >
          <div
            ref={healthModalRef}
            tabIndex={-1}
            className="w-full max-w-lg bg-stone-50 dark:bg-stone-900 border border-stone-200 dark:border-stone-800 rounded-xl shadow-2xl overflow-hidden flex flex-col max-h-[80vh] text-stone-900 dark:text-stone-100 outline-none"
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => {
              if (e.key === 'Escape') {
                e.stopPropagation();
                setShowHealthModal(false);
              } else if (e.key === 'Tab') {
                const focusable = healthModalRef.current?.querySelectorAll<HTMLElement>(
                  'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
                );
                if (focusable && focusable.length > 0) {
                  const first = focusable[0];
                  const last = focusable[focusable.length - 1];
                  if (e.shiftKey) {
                    if (document.activeElement === first || document.activeElement === healthModalRef.current) {
                      e.preventDefault();
                      last.focus();
                    }
                  } else {
                    if (document.activeElement === last) {
                      e.preventDefault();
                      first.focus();
                    }
                  }
                }
              }
            }}
          >
            <div className="flex items-center justify-between px-4 py-3 border-b border-stone-200 dark:border-stone-800">
              <div className="flex items-center space-x-2">
                <AlertTriangle className="w-4 h-4 text-amber-600 dark:text-amber-400" />
                <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                  Vault 降级状态与异常诊断
                </h2>
              </div>
              <button
                onClick={() => setShowHealthModal(false)}
                className="p-1 rounded text-stone-400 hover:text-stone-600 dark:hover:text-stone-300"
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
              <button
                onClick={() => {
                  setShowHealthModal(false);
                  handleOpenSettings('storage');
                }}
                className="px-3 py-1.5 rounded-md border border-stone-300 dark:border-stone-700 hover:bg-stone-200/60 dark:hover:bg-stone-800 text-stone-700 dark:text-stone-300 text-xs font-medium transition cursor-pointer"
              >
                前往存储设置
              </button>

              <button
                onClick={() => setShowHealthModal(false)}
                className="px-3 py-1.5 rounded-md bg-stone-200 dark:bg-stone-800 hover:bg-stone-300 dark:hover:bg-stone-700 text-stone-800 dark:text-stone-200 text-xs font-medium transition cursor-pointer"
              >
                关闭
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
