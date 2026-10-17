import { useState, useEffect, useRef } from 'react';
import {
  Play,
  Pause,
  RotateCcw,
  MoreHorizontal,
  FolderOpen,
  AlertCircle,
  Loader2,
  Volume2,
} from 'lucide-react';
import * as VaultService from '../bindings/pata/vaultservice';
import { ASRTaskStatus, ASRTaskState } from '../bindings/pata/internal/asr/models';
import { formatTime } from './audioTranscript';

interface AudioPlayerProps {
  noteId: string;
  audioFile?: string;
  taskStatus: ASRTaskStatus | null;
  onSeekCommitted: (timeMs: number) => void;
  onRetranscribe: () => void;
  audioRef: React.RefObject<HTMLAudioElement | null>;
  isTranscribing: boolean;
  hasTranscriptBody: boolean;
}

export function AudioPlayer({
  noteId,
  audioFile,
  taskStatus,
  onSeekCommitted,
  onRetranscribe,
  audioRef,
  isTranscribing,
  hasTranscriptBody,
}: AudioPlayerProps) {
  const [audioSrc, setAudioSrc] = useState<string>('');
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [currentTimeMs, setCurrentTimeMs] = useState<number>(0);
  const [durationMs, setDurationMs] = useState<number>(0);
  const [isDragging, setIsDragging] = useState<boolean>(false);
  const [previewMs, setPreviewMs] = useState<number | null>(null);
  const [audioLoadError, setAudioLoadError] = useState<string | null>(null);
  const [showMenu, setShowMenu] = useState<boolean>(false);
  const menuRef = useRef<HTMLDivElement | null>(null);

  // Load audio source when audioFile changes
  useEffect(() => {
    let cancelled = false;
    if (!audioFile) {
      setAudioSrc('');
      return;
    }

    setAudioLoadError(null);
    VaultService.GetAudioURL(audioFile)
      .then((url) => {
        if (!cancelled) {
          setAudioSrc(url);
        }
      })
      .catch((err) => {
        // Fallback to GetAudioData
        VaultService.GetAudioData(audioFile)
          .then((dataUri) => {
            if (!cancelled) setAudioSrc(dataUri);
          })
          .catch((dataErr) => {
            if (!cancelled) {
              setAudioLoadError(err?.message || dataErr?.message || '无法加载关联音频文件');
            }
          });
      });

    return () => {
      cancelled = true;
    };
  }, [audioFile, noteId]);

  // Close dropdown on outside click
  useEffect(() => {
    const handleOutsideClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setShowMenu(false);
      }
    };
    if (showMenu) {
      document.addEventListener('mousedown', handleOutsideClick);
      return () => document.removeEventListener('mousedown', handleOutsideClick);
    }
  }, [showMenu]);

  const togglePlay = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) {
      audio.play().catch((err) => {
        setAudioLoadError('播放失败: ' + (err?.message || String(err)));
      });
    } else {
      audio.pause();
    }
  };

  const handleTimeUpdate = () => {
    const audio = audioRef.current;
    if (!audio || isDragging) return;
    setCurrentTimeMs(Math.round(audio.currentTime * 1000));
  };

  const handleLoadedMetadata = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (!isNaN(audio.duration) && isFinite(audio.duration)) {
      setDurationMs(Math.round(audio.duration * 1000));
    }
  };

  const handleSliderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseInt(e.target.value, 10);
    setPreviewMs(val);
  };

  const handleCommitSeek = (valMs: number) => {
    setIsDragging(false);
    setPreviewMs(null);
    setCurrentTimeMs(valMs);

    const audio = audioRef.current;
    if (audio) {
      audio.currentTime = valMs / 1000;
    }
    onSeekCommitted(valMs);
  };

  const fileName = audioFile ? audioFile.split('/').pop() : '未命名录音';

  const isFailed = taskStatus?.state === ASRTaskState.StateFailed;
  const isUploadingOrTranscribing =
    taskStatus?.state === ASRTaskState.StateUploading ||
    taskStatus?.state === ASRTaskState.StateTranscribing ||
    taskStatus?.state === ASRTaskState.StateWriting;

  return (
    <div className="rounded-xl border border-stone-200 dark:border-stone-800 bg-stone-50/80 dark:bg-stone-900/60 p-3.5 space-y-2.5 transition">
      {/* Hidden native audio element */}
      {audioSrc && (
        <audio
          ref={audioRef as any}
          src={audioSrc}
          preload="metadata"
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          onEnded={() => setIsPlaying(false)}
          onTimeUpdate={handleTimeUpdate}
          onLoadedMetadata={handleLoadedMetadata}
          onError={() => {
            // Audio error
            setAudioLoadError('音频文件丢失或格式无法播放');
          }}
        />
      )}

      {/* Top File & Status Header */}
      <div className="flex items-center justify-between gap-3 text-xs">
        <div className="flex items-center space-x-2 min-w-0">
          <Volume2 className="w-4 h-4 text-emerald-600 dark:text-emerald-400 shrink-0" />
          <span className="font-medium text-stone-800 dark:text-stone-200 truncate" title={fileName}>
            {fileName}
          </span>
          {audioLoadError && (
            <span className="inline-flex items-center space-x-1 text-[11px] text-rose-600 dark:text-rose-400 bg-rose-50 dark:bg-rose-950/40 px-1.5 py-0.5 rounded border border-rose-200 dark:border-rose-900">
              <AlertCircle className="w-3 h-3 shrink-0" />
              <span>{audioLoadError}</span>
            </span>
          )}
        </div>

        {/* Task progress badge or dropdown menu */}
        <div className="flex items-center space-x-2 shrink-0">
          {isUploadingOrTranscribing && (
            <div className="inline-flex items-center space-x-1 text-[11px] text-emerald-700 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/50 px-2 py-0.5 rounded-full border border-emerald-200 dark:border-emerald-900 animate-pulse">
              <Loader2 className="w-3 h-3 animate-spin shrink-0" />
              <span>{taskStatus?.stage_message || '处理中...'}</span>
            </div>
          )}

          {isFailed && (
            <div className="inline-flex items-center space-x-1.5 text-[11px] text-rose-700 dark:text-rose-300 bg-rose-50 dark:bg-rose-950/50 px-2 py-0.5 rounded-full border border-rose-200 dark:border-rose-900">
              <AlertCircle className="w-3 h-3 shrink-0 text-rose-600" />
              <span className="max-w-[200px] truncate" title={taskStatus?.error}>
                {taskStatus?.error || '转写失败'}
              </span>
              <button
                type="button"
                onClick={onRetranscribe}
                className="text-emerald-700 dark:text-emerald-400 font-semibold hover:underline ml-1 cursor-pointer"
              >
                重试
              </button>
            </div>
          )}

          {taskStatus?.state === ASRTaskState.StatePendingConfirmation && (
            <div className="inline-flex items-center space-x-1 text-[11px] text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/50 px-2 py-0.5 rounded-full border border-amber-200 dark:border-amber-900">
              <span>重新转写已就绪</span>
            </div>
          )}

          {/* More actions menu */}
          <div className="relative" ref={menuRef}>
            <button
              type="button"
              onClick={() => setShowMenu((prev) => !prev)}
              className="p-1 rounded text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800 transition cursor-pointer"
              title="播放器操作"
            >
              <MoreHorizontal className="w-4 h-4" />
            </button>

            {showMenu && (
              <div className="absolute right-0 mt-1 w-44 rounded-lg bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800 shadow-lg py-1 z-30 text-xs">
                <button
                  type="button"
                  disabled={isTranscribing}
                  onClick={() => {
                    setShowMenu(false);
                    onRetranscribe();
                  }}
                  className={`w-full text-left px-3 py-1.5 flex items-center space-x-2 ${
                    isTranscribing
                      ? 'text-stone-400 cursor-not-allowed'
                      : 'text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 cursor-pointer'
                  }`}
                >
                  <RotateCcw className="w-3.5 h-3.5 shrink-0" />
                  <span>{hasTranscriptBody ? '重新转写' : '开始转写 / 重试'}</span>
                </button>

                {audioFile && (
                  <button
                    type="button"
                    onClick={() => {
                      setShowMenu(false);
                      VaultService.RevealInFinder(audioFile).catch((e) => {
                        console.error('RevealInFinder failed', e);
                      });
                    }}
                    className="w-full text-left px-3 py-1.5 flex items-center space-x-2 text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-stone-800 cursor-pointer"
                  >
                    <FolderOpen className="w-3.5 h-3.5 shrink-0" />
                    <span>在 Finder 中显示音频</span>
                  </button>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Warning message if audio > 2 hours */}
      {taskStatus?.warning && (
        <div className="text-[11px] text-amber-700 dark:text-amber-400 bg-amber-50/80 dark:bg-amber-950/40 p-2 rounded border border-amber-200 dark:border-amber-900 flex items-center space-x-1.5">
          <AlertCircle className="w-3.5 h-3.5 shrink-0" />
          <span>{taskStatus.warning}</span>
        </div>
      )}

      {/* Main Player Controls: Play Button, Progress Slider, Exact Time Display */}
      <div className="flex items-center space-x-3">
        <button
          type="button"
          onClick={togglePlay}
          disabled={!audioSrc || !!audioLoadError}
          className={`w-8 h-8 rounded-full flex items-center justify-center transition shadow-2xs shrink-0 cursor-pointer ${
            !audioSrc || audioLoadError
              ? 'bg-stone-200 dark:bg-stone-800 text-stone-400 cursor-not-allowed'
              : isPlaying
              ? 'bg-emerald-700 hover:bg-emerald-800 text-white'
              : 'bg-emerald-600 hover:bg-emerald-700 text-white'
          }`}
          title={isPlaying ? '暂停' : '播放'}
        >
          {isPlaying ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4 ml-0.5" />}
        </button>

        {/* Scrubbing slider */}
        <div className="flex-1 flex items-center">
          <input
            type="range"
            min={0}
            max={durationMs > 0 ? durationMs : 100}
            step={10}
            value={previewMs !== null ? previewMs : currentTimeMs}
            onPointerDown={(e) => {
              setIsDragging(true);
              e.currentTarget.setPointerCapture(e.pointerId);
            }}
            onChange={handleSliderChange}
            onPointerUp={(e) => {
              if (e.currentTarget.hasPointerCapture(e.pointerId)) {
                e.currentTarget.releasePointerCapture(e.pointerId);
              }
              handleCommitSeek(parseInt((e.target as HTMLInputElement).value, 10));
            }}
            onPointerCancel={(e) => {
              if (e.currentTarget.hasPointerCapture(e.pointerId)) {
                e.currentTarget.releasePointerCapture(e.pointerId);
              }
              setIsDragging(false);
              setPreviewMs(null);
            }}
            onKeyDown={(e) => {
              if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End'].includes(e.key)) {
                setIsDragging(true);
              }
            }}
            onKeyUp={(e) => {
              if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End'].includes(e.key)) {
                handleCommitSeek(parseInt((e.target as HTMLInputElement).value, 10));
              }
            }}
            onBlur={(e) => {
              if (previewMs !== null) {
                handleCommitSeek(parseInt((e.target as HTMLInputElement).value, 10));
              }
            }}
            disabled={!audioSrc || !!audioLoadError}
            className="w-full h-1.5 bg-stone-200 dark:bg-stone-800 rounded-lg appearance-none cursor-pointer accent-emerald-600 dark:accent-emerald-500 disabled:cursor-not-allowed"
          />
        </div>

        {/* Millisecond precision time: 00:01:23.456 / 00:45:00.000 */}
        <div className="font-mono text-[11px] text-stone-500 dark:text-stone-400 shrink-0 select-none">
          <span>{formatTime(previewMs !== null ? previewMs : currentTimeMs)}</span>
          <span className="mx-1 text-stone-300 dark:text-stone-600">/</span>
          <span>{formatTime(durationMs)}</span>
        </div>
      </div>
    </div>
  );
}
