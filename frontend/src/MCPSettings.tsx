import { useEffect, useRef, useState } from 'react';
import { Check, Copy, Plug } from 'lucide-react';
import { Clipboard } from '@wailsio/runtime';
import * as MCPService from '../bindings/pata/internal/app/mcpservice';
import type { MCPStatus } from '../bindings/pata/internal/app/models';
import { Button } from './components/ui/button';

export function MCPSettings() {
  const [status, setStatus] = useState<MCPStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState(false);
  const sequence = useRef(0);
  const changing = useRef(false);
  const copyTimer = useRef<number | undefined>(undefined);

  useEffect(() => {
    const refresh = async () => {
      if (changing.current) return;
      const request = ++sequence.current;
      try {
        const next = await MCPService.GetStatus();
        if (request === sequence.current) setStatus(next);
      } catch {
        if (request === sequence.current) setError('无法读取 MCP 状态，请重新打开设置');
      }
    };
    void refresh();
    const timer = window.setInterval(() => void refresh(), 3000);
    return () => {
      sequence.current++;
      window.clearInterval(timer);
      window.clearTimeout(copyTimer.current);
    };
  }, []);

  const toggle = async (stop = false) => {
    if (changing.current) return;
    changing.current = true;
    const request = ++sequence.current;
    setBusy(true);
    setError('');
    setCopied(false);
    try {
      const next = (stop || status?.running) ? await MCPService.Stop() : await MCPService.Start();
      if (request === sequence.current) setStatus(next);
    } catch (err) {
      if (request === sequence.current) setError(err instanceof Error ? err.message : String(err));
    } finally {
      changing.current = false;
      if (request === sequence.current) setBusy(false);
    }
  };

  const prompt = status?.running ? `帮我在当前客户端配置中新增名为 pata 的 MCP 服务，使用 Streamable HTTP 传输协议，连接地址为 ${status.endpoint}，仅增量修改并保留原有配置，最后通过列出工具验证接入是否成功。` : '';

  const copy = async () => {
    try {
      await Clipboard.SetText(prompt);
      setCopied(true);
      setError('');
      window.clearTimeout(copyTimer.current);
      copyTimer.current = window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setError('复制失败，请在指令预览中手动复制');
    }
  };

  return (
    <section
      aria-labelledby="mcp-heading"
      className="rounded-xl border border-stone-200/80 dark:border-stone-800/80 bg-white/70 dark:bg-stone-900/60 p-5 shadow-2xs space-y-3"
    >
      <div className="flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <Plug className="h-4 w-4 shrink-0 text-stone-600 dark:text-stone-300" />
          <div className="min-w-0">
            <h2 id="mcp-heading" className="text-sm font-semibold text-stone-900 dark:text-stone-100">MCP 服务</h2>
            <div role="status" className="mt-1 flex items-center gap-1.5 text-xs text-stone-500 dark:text-stone-400">
              {status?.running ? (
                <>
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" aria-hidden="true" />
                  运行中
                </>
              ) : status ? '未启动' : '读取状态…'}
            </div>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <Button variant="outline" size="sm" disabled={!status} loading={busy} onClick={() => void toggle()}>
            {status?.running ? '停止服务' : '启动服务'}
          </Button>
          {status?.enabled && !status.running && (
            <Button variant="outline" size="sm" loading={busy} onClick={() => void toggle(true)}>
              取消自动启动
            </Button>
          )}
        </div>
      </div>

      {status?.vaultChanged && (
        <p role="alert" className="text-xs text-amber-700 dark:text-amber-400">
          资料库已更换。请停止并重新启动服务，允许 Agent 访问当前资料库。
        </p>
      )}
      {(error || status?.error) && (
        <p role="alert" className="text-xs text-rose-600 dark:text-rose-400">{error || status?.error}</p>
      )}

      {status?.running && (
        <div className="flex items-center justify-between gap-3 border-t border-stone-200/80 pt-3 dark:border-stone-800/80">
          <div className="min-w-0">
            <div className="text-xs font-medium text-stone-800 dark:text-stone-200">Agent 接入</div>
            <p className="mt-1 text-xs text-stone-500 dark:text-stone-400">在支持 MCP 的客户端中使用</p>
          </div>
          <div className="group relative shrink-0">
            <Button
              variant="outline"
              size="sm"
              disabled={status.vaultChanged}
              onClick={() => void copy()}
              aria-describedby="mcp-agent-prompt-preview"
            >
              {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
              {copied ? '已复制' : '复制指令'}
            </Button>
            <div
              id="mcp-agent-prompt-preview"
              role="tooltip"
              className="absolute right-0 top-full z-30 hidden w-[min(28rem,calc(100vw-3rem))] pt-2 group-hover:block group-focus-within:block"
            >
              <div className="rounded-lg border border-stone-200 bg-white p-3 shadow-lg dark:border-stone-700 dark:bg-stone-900">
                <p className="mb-1.5 text-xs font-medium text-stone-800 dark:text-stone-200">Agent 接入指令</p>
                <p className="select-text break-words text-xs leading-relaxed text-stone-600 dark:text-stone-300">{prompt}</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
