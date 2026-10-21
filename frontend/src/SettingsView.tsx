import { useState, useEffect, useCallback, useRef } from 'react';
import {
  ArrowLeft,
  Sun,
  Moon,
  Monitor,
  FolderOpen,
  RefreshCw,
  ExternalLink,
  Key,
  ShieldCheck,
  AlertTriangle,
  Check,
  Copy,
} from 'lucide-react';
import { Browser } from '@wailsio/runtime';
import * as VaultService from '../bindings/pata/vaultservice';
import { VaultStatus, VaultHealth, ASRConfigStatus } from '../bindings/pata/models';

interface SettingsViewProps {
  themeMode: 'system' | 'light' | 'dark';
  onThemeChange: (mode: 'system' | 'light' | 'dark') => void;
  vaultStatus: VaultStatus | null;
  onSelectVault: () => void;
  onRescanVault: () => void;
  vaultBusy: boolean;
  rescanError: string | null;
  health: VaultHealth | null;
  onOpenHealthModal: () => void;
  onBack: () => void;
  initialSection?: 'appearance' | 'storage' | 'transcription' | null;
}

export function SettingsView({
  themeMode,
  onThemeChange,
  vaultStatus,
  onSelectVault,
  onRescanVault,
  vaultBusy,
  rescanError,
  health,
  onOpenHealthModal,
  onBack,
  initialSection,
}: SettingsViewProps) {
  const [copiedPath, setCopiedPath] = useState(false);
  const [finderError, setFinderError] = useState<string | null>(null);

  // ASR API Key state
  const [asrStatus, setAsrStatus] = useState<ASRConfigStatus | null>(null);
  const [asrLoading, setAsrLoading] = useState(true);
  const [isReplacingKey, setIsReplacingKey] = useState(false);
  const [apiKeyInput, setApiKeyInput] = useState('');
  const [asrError, setAsrError] = useState<string | null>(null);
  const [asrSaving, setAsrSaving] = useState(false);
  const [saveSuccessMsg, setSaveSuccessMsg] = useState(false);

  // Section refs for deep-linking
  const appearanceRef = useRef<HTMLDivElement>(null);
  const storageRef = useRef<HTMLDivElement>(null);
  const transcriptionRef = useRef<HTMLDivElement>(null);

  // Load ASR configuration status
  const loadAsrStatus = useCallback(async () => {
    try {
      setAsrLoading(true);
      setAsrError(null);
      const st = await VaultService.GetASRConfigStatus();
      setAsrStatus(st);
    } catch (err: any) {
      console.error('Failed to load ASR config status:', err);
      setAsrError(err?.message || '读取转写配置状态失败');
    } finally {
      setAsrLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAsrStatus();
  }, [loadAsrStatus]);

  // Deep-link scroll to initialSection if provided
  useEffect(() => {
    if (!initialSection) return;
    const timer = setTimeout(() => {
      let target: HTMLDivElement | null = null;
      if (initialSection === 'appearance') target = appearanceRef.current;
      else if (initialSection === 'storage') target = storageRef.current;
      else if (initialSection === 'transcription') target = transcriptionRef.current;

      if (target) {
        const prefersReducedMotion =
          typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        target.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth', block: 'start' });
      }
    }, 100);
    return () => clearTimeout(timer);
  }, [initialSection]);

  // Escape key to back
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onBack();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onBack]);

  const handleCopyPath = async () => {
    if (!vaultStatus?.path) return;
    try {
      await navigator.clipboard.writeText(vaultStatus.path);
      setCopiedPath(true);
      setTimeout(() => setCopiedPath(false), 2000);
    } catch (err) {
      console.error('Failed to copy path:', err);
    }
  };

  const handleOpenInFinder = async () => {
    setFinderError(null);
    if (!vaultStatus?.configured || !vaultStatus?.path) {
      setFinderError('未设置 Vault 目录');
      return;
    }
    try {
      await VaultService.OpenVaultInFinder();
    } catch (err: any) {
      console.error('Failed to open vault in finder:', err);
      setFinderError(err?.message || '在 Finder 中打开失败');
    }
  };

  const handleSaveApiKey = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const key = apiKeyInput.trim();
    if (!key) {
      setAsrError('API Key 不能为空');
      return;
    }

    try {
      setAsrSaving(true);
      setAsrError(null);
      await VaultService.SetASRKey(key);
      setApiKeyInput('');
      setIsReplacingKey(false);
      setSaveSuccessMsg(true);
      setTimeout(() => setSaveSuccessMsg(false), 3000);
      await loadAsrStatus();
    } catch (err: any) {
      console.error('Failed to save ASR key:', err);
      setAsrError(err?.message || '保存 API Key 到 Keychain 失败');
    } finally {
      setAsrSaving(false);
    }
  };

  const handleOpenConsole = async (e: React.MouseEvent) => {
    e.preventDefault();
    try {
      await Browser.OpenURL('https://bailian.console.aliyun.com/?apiKey=1');
    } catch {
      window.open('https://bailian.console.aliyun.com/?apiKey=1', '_blank');
    }
  };

  const parseErrorCount = health?.parse_errors?.length ?? 0;
  const danglingRefCount = health?.dangling_refs?.length ?? 0;
  const totalHealthIssues = parseErrorCount + danglingRefCount;

  return (
    <div className="h-full flex flex-col bg-stone-50 dark:bg-stone-900 text-stone-900 dark:text-stone-100 select-none">
      {/* Header */}
      <div className="h-12 shrink-0 border-b border-stone-200/80 dark:border-stone-800/80 px-6 flex items-center justify-between bg-stone-100/50 dark:bg-stone-950/40">
        <div className="flex items-center space-x-3">
          <button
            onClick={onBack}
            className="flex items-center space-x-1.5 px-2 py-1 rounded-md text-xs font-medium text-stone-600 dark:text-stone-300 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/60 dark:hover:bg-stone-800/60 transition cursor-pointer"
            title="返回 (Esc)"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            <span>返回</span>
          </button>
          <span className="text-stone-300 dark:text-stone-700">|</span>
          <h1 className="text-sm font-semibold text-stone-900 dark:text-stone-100">应用设置</h1>
        </div>
      </div>

      {/* Content Area - Single page vertically stacked */}
      <div className="flex-1 overflow-y-auto p-6 max-w-3xl mx-auto w-full space-y-6">
        {/* Section 1: 外观 */}
        <section
          ref={appearanceRef}
          className="rounded-xl border border-stone-200/80 dark:border-stone-800/80 bg-white/70 dark:bg-stone-900/60 p-5 shadow-2xs space-y-4"
        >
          <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">外观</h2>

          <div>
            <label className="text-xs font-medium text-stone-700 dark:text-stone-300 block mb-2">
              主题模式
            </label>
            <div className="grid grid-cols-3 gap-3">
              <button
                type="button"
                onClick={() => onThemeChange('system')}
                className={`flex items-center justify-center space-x-2 px-3 py-2.5 rounded-lg border text-xs font-medium transition cursor-pointer ${
                  themeMode === 'system'
                    ? 'border-emerald-600 bg-emerald-50/80 text-emerald-900 dark:bg-emerald-950/50 dark:border-emerald-500 dark:text-emerald-200 shadow-2xs font-semibold'
                    : 'border-stone-200 dark:border-stone-800 hover:bg-stone-100 dark:hover:bg-stone-800 text-stone-600 dark:text-stone-400'
                }`}
              >
                <Monitor className="w-4 h-4 shrink-0" />
                <span>跟随系统</span>
              </button>

              <button
                type="button"
                onClick={() => onThemeChange('light')}
                className={`flex items-center justify-center space-x-2 px-3 py-2.5 rounded-lg border text-xs font-medium transition cursor-pointer ${
                  themeMode === 'light'
                    ? 'border-emerald-600 bg-emerald-50/80 text-emerald-900 dark:bg-emerald-950/50 dark:border-emerald-500 dark:text-emerald-200 shadow-2xs font-semibold'
                    : 'border-stone-200 dark:border-stone-800 hover:bg-stone-100 dark:hover:bg-stone-800 text-stone-600 dark:text-stone-400'
                }`}
              >
                <Sun className="w-4 h-4 shrink-0" />
                <span>浅色模式</span>
              </button>

              <button
                type="button"
                onClick={() => onThemeChange('dark')}
                className={`flex items-center justify-center space-x-2 px-3 py-2.5 rounded-lg border text-xs font-medium transition cursor-pointer ${
                  themeMode === 'dark'
                    ? 'border-emerald-600 bg-emerald-50/80 text-emerald-900 dark:bg-emerald-950/50 dark:border-emerald-500 dark:text-emerald-200 shadow-2xs font-semibold'
                    : 'border-stone-200 dark:border-stone-800 hover:bg-stone-100 dark:hover:bg-stone-800 text-stone-600 dark:text-stone-400'
                }`}
              >
                <Moon className="w-4 h-4 shrink-0" />
                <span>深色模式</span>
              </button>
            </div>
          </div>
        </section>

        {/* Section 2: 存储 */}
        <section
          ref={storageRef}
          className="rounded-xl border border-stone-200/80 dark:border-stone-800/80 bg-white/70 dark:bg-stone-900/60 p-5 shadow-2xs space-y-4"
        >
          <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">存储</h2>

          {/* Current Path */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <label className="text-xs font-medium text-stone-700 dark:text-stone-300">
                当前 Vault 目录
              </label>
              {vaultStatus?.configured && (
                <span className="flex items-center space-x-1 text-[11px]">
                  <span
                    className={`w-1.5 h-1.5 rounded-full ${
                      vaultStatus.open ? 'bg-emerald-500' : 'bg-rose-500'
                    }`}
                  />
                  <span className={vaultStatus.open ? 'text-stone-500 dark:text-stone-400' : 'text-rose-600 dark:text-rose-400 font-medium'}>
                    {vaultStatus.open ? '已连接' : '无法打开'}
                  </span>
                </span>
              )}
            </div>

            <div className="flex items-center space-x-2">
              <div className="flex-1 px-3 py-2 rounded-lg bg-stone-100 dark:bg-stone-950/60 border border-stone-200 dark:border-stone-800 font-mono text-xs text-stone-700 dark:text-stone-300 break-all select-text">
                {vaultStatus?.configured ? vaultStatus.path : '未配置 Vault 目录'}
              </div>
              {vaultStatus?.configured && (
                <button
                  type="button"
                  onClick={handleCopyPath}
                  className="p-2 rounded-lg border border-stone-200 dark:border-stone-800 hover:bg-stone-100 dark:hover:bg-stone-800 text-stone-500 dark:text-stone-400 transition cursor-pointer"
                  title="复制完整路径"
                >
                  {copiedPath ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
                </button>
              )}
            </div>
          </div>

          {/* Error / Warning display */}
          {(!vaultStatus?.open && vaultStatus?.configured) && (
            <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-xs text-rose-700 dark:text-rose-300 space-y-1">
              <div className="font-semibold flex items-center space-x-1.5">
                <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                <span>Vault 无法访问</span>
              </div>
              <div>{vaultStatus.error || '无法打开目标路径，请检查磁盘访问权限或重新选择目录。'}</div>
            </div>
          )}

          {rescanError && (
            <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-xs text-rose-700 dark:text-rose-300">
              <span className="font-semibold">重新扫描失败: </span>
              <span>{rescanError}</span>
            </div>
          )}

          {finderError && (
            <div className="p-3 rounded-lg border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-xs text-rose-700 dark:text-rose-300">
              <span>{finderError}</span>
            </div>
          )}

          {/* Health issue alert */}
          {totalHealthIssues > 0 && (
            <div className="p-3 rounded-lg border border-amber-200 dark:border-amber-900/60 bg-amber-50/80 dark:bg-amber-950/40 text-xs flex items-center justify-between text-amber-900 dark:text-amber-200">
              <div className="flex items-center space-x-2">
                <AlertTriangle className="w-4 h-4 text-amber-600 dark:text-amber-400 shrink-0" />
                <span>检测到 {totalHealthIssues} 项健康与解析诊断提示</span>
              </div>
              <button
                type="button"
                onClick={onOpenHealthModal}
                className="px-2.5 py-1 rounded bg-amber-200/80 dark:bg-amber-900/80 hover:bg-amber-300 text-amber-950 dark:text-amber-100 font-medium transition cursor-pointer"
              >
                查看详情
              </button>
            </div>
          )}

          {/* Action Buttons */}
          <div className="flex flex-wrap items-center gap-2.5 pt-1">
            <button
              type="button"
              onClick={onSelectVault}
              disabled={vaultBusy}
              className="flex items-center space-x-1.5 px-3 py-1.5 rounded-lg border border-stone-300 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-800 disabled:opacity-50 text-xs font-medium text-stone-800 dark:text-stone-200 transition cursor-pointer"
            >
              <FolderOpen className="w-3.5 h-3.5" />
              <span>{vaultStatus?.configured ? '更换目录' : '选择目录'}</span>
            </button>

            <button
              type="button"
              onClick={onRescanVault}
              disabled={vaultBusy || !vaultStatus?.open}
              className="flex items-center space-x-1.5 px-3 py-1.5 rounded-lg border border-stone-300 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-800 disabled:opacity-50 text-xs font-medium text-stone-800 dark:text-stone-200 transition cursor-pointer"
              title="从磁盘重新加载所有 Markdown 文件索引"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${vaultBusy ? 'animate-spin' : ''}`} />
              <span>重新扫描</span>
            </button>

            <button
              type="button"
              onClick={handleOpenInFinder}
              disabled={vaultBusy || !vaultStatus?.configured}
              className="flex items-center space-x-1.5 px-3 py-1.5 rounded-lg border border-stone-300 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-800 disabled:opacity-50 text-xs font-medium text-stone-800 dark:text-stone-200 transition cursor-pointer"
              title="在系统 Finder 中打开当前 Vault 目录"
            >
              <ExternalLink className="w-3.5 h-3.5" />
              <span>在 Finder 中打开</span>
            </button>
          </div>
        </section>

        {/* Section 3: 语音转写 */}
        <section
          ref={transcriptionRef}
          className="rounded-xl border border-stone-200/80 dark:border-stone-800/80 bg-white/70 dark:bg-stone-900/60 p-5 shadow-2xs space-y-4"
        >
          <h2 className="text-sm font-semibold text-stone-900 dark:text-stone-100">语音转写</h2>

          {/* Fixed provider / model / region, one line */}
          <p className="text-[11px] font-mono text-stone-400 dark:text-stone-500 truncate">
            {asrStatus?.provider || '阿里云百炼'} ·{' '}
            {asrStatus?.model || 'qwen-audio-3.1-asr-flash-filetrans'} ·{' '}
            {asrStatus?.region || '华北2（北京）'}
          </p>

          {/* API Key Configuration Block */}
          <div className="space-y-3 pt-1">
            <div className="flex items-center justify-between">
              <label className="text-xs font-medium text-stone-700 dark:text-stone-300">
                API Key 凭据
              </label>
              <button
                type="button"
                onClick={handleOpenConsole}
                className="text-xs text-emerald-700 dark:text-emerald-400 hover:underline flex items-center space-x-1 cursor-pointer"
              >
                <span>获取 API Key</span>
                <ExternalLink className="w-3 h-3" />
              </button>
            </div>

            {asrLoading ? (
              <div className="text-xs text-stone-400 py-2">加载 Keychain 配置状态...</div>
            ) : asrStatus?.configured && !isReplacingKey ? (
              /* Configured State */
              <div className="flex items-center justify-between p-3 rounded-lg border border-emerald-200 dark:border-emerald-900/60 bg-emerald-50/70 dark:bg-emerald-950/30">
                <div className="flex items-center space-x-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-600 dark:text-emerald-400 shrink-0" />
                  <span className="text-xs font-medium text-emerald-950 dark:text-emerald-200">
                    已配置 · 存于 macOS Keychain
                  </span>
                </div>

                <button
                  type="button"
                  onClick={() => {
                    setIsReplacingKey(true);
                    setApiKeyInput('');
                    setAsrError(null);
                  }}
                  className="px-3 py-1.5 rounded-lg border border-emerald-300 dark:border-emerald-800/80 bg-white/80 dark:bg-stone-900/80 hover:bg-emerald-100/50 dark:hover:bg-emerald-900/50 text-xs font-medium text-emerald-900 dark:text-emerald-200 transition cursor-pointer"
                >
                  更换 API Key
                </button>
              </div>
            ) : (
              /* Input / Replacement Form */
              <form onSubmit={handleSaveApiKey} className="space-y-2.5">
                <div className="flex items-center space-x-2">
                  <div className="relative flex-1">
                    <Key className="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-stone-400" />
                    <input
                      type="password"
                      value={apiKeyInput}
                      onChange={(e) => setApiKeyInput(e.target.value)}
                      placeholder="sk-..."
                      autoFocus
                      className="w-full pl-9 pr-3 py-2 rounded-lg bg-white dark:bg-stone-950 border border-stone-200 dark:border-stone-800 font-mono text-xs text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 transition"
                    />
                  </div>

                  <button
                    type="submit"
                    disabled={asrSaving || !apiKeyInput.trim()}
                    className="px-3.5 py-2 rounded-lg bg-emerald-700 hover:bg-emerald-800 disabled:opacity-50 text-white text-xs font-medium transition shadow-2xs shrink-0 cursor-pointer"
                  >
                    {asrSaving ? '保存中...' : '保存到 Keychain'}
                  </button>

                  {isReplacingKey && (
                    <button
                      type="button"
                      onClick={() => {
                        setIsReplacingKey(false);
                        setApiKeyInput('');
                        setAsrError(null);
                      }}
                      className="px-3 py-2 rounded-lg border border-stone-300 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-800 text-xs text-stone-600 dark:text-stone-300 transition cursor-pointer"
                    >
                      取消
                    </button>
                  )}
                </div>

                <div className="text-[11px] text-stone-400">
                  写入 macOS Keychain，不落任何文件与日志。
                </div>
              </form>
            )}

            {saveSuccessMsg && (
              <div className="p-2.5 rounded-lg bg-emerald-100/70 dark:bg-emerald-950/60 border border-emerald-300 dark:border-emerald-800 text-xs text-emerald-900 dark:text-emerald-200 flex items-center space-x-1.5">
                <Check className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400 shrink-0" />
                <span>已保存到 macOS Keychain</span>
              </div>
            )}

            {asrError && (
              <div className="p-2.5 rounded-lg bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-900 text-xs text-rose-700 dark:text-rose-300 flex items-center space-x-1.5">
                <AlertTriangle className="w-3.5 h-3.5 text-rose-600 dark:text-rose-400 shrink-0" />
                <span>{asrError}</span>
              </div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
