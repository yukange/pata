export interface TranscriptBlock {
  id: string;
  timestampStr?: string;
  timestampMs?: number;
  speaker?: string;
  text: string;
}

export function formatTime(ms: number): string {
  if (isNaN(ms) || ms < 0) ms = 0;
  const totalSeconds = Math.floor(ms / 1000);
  const millis = Math.floor(ms % 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  const pad = (n: number, z = 2) => n.toString().padStart(z, '0');
  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}.${pad(millis, 3)}`;
}

export function parseTime(ts: string): number | null {
  if (!ts) return null;
  const match = ts.trim().match(/^(\d{2}):(\d{2}):(\d{2})\.(\d{3})$/);
  if (!match) return null;
  const h = parseInt(match[1], 10);
  const m = parseInt(match[2], 10);
  const s = parseInt(match[3], 10);
  const ms = parseInt(match[4], 10);
  if (m >= 60 || s >= 60) return null;
  return h * 3600000 + m * 60000 + s * 1000 + ms;
}

const TIMESTAMP_HEADER_REGEX = /^\[(\d{2}:\d{2}:\d{2}\.\d{3})\](?:\(#t=([^)]*)\))?(?:\s+(.*?))?$/;

/**
 * Parses a Stage 11 Markdown transcript into sentence blocks.
 * If the markdown has no recognized timestamp blocks, it treats the markdown as ordinary fallback text without fabricated timestamps.
 */
export function parseTranscript(body: string): TranscriptBlock[] {
  if (!body || !body.trim()) {
    return [];
  }

  const lines = body.split('\n');
  const blocks: TranscriptBlock[] = [];

  let currentBlock: Partial<TranscriptBlock> | null = null;
  let textLines: string[] = [];

  const flush = () => {
    if (currentBlock) {
      blocks.push({
        id: `tb-${blocks.length}-${currentBlock.timestampMs ?? 0}`,
        timestampStr: currentBlock.timestampStr,
        timestampMs: currentBlock.timestampMs,
        speaker: currentBlock.speaker || '发言',
        text: textLines.join('\n').trim(),
      });
      currentBlock = null;
      textLines = [];
    } else if (textLines.join('\n').trim()) {
      blocks.push({
        id: `tb-preamble-${blocks.length}`,
        text: textLines.join('\n').trim(),
      });
      textLines = [];
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const headerMatch = line.match(TIMESTAMP_HEADER_REGEX);
    if (headerMatch) {
      const tsStr = headerMatch[1];
      const anchor = headerMatch[2];
      const speaker = (headerMatch[3] || '').trim();
      const parsedMs = parseTime(tsStr);

      if (parsedMs !== null && (anchor === undefined || anchor === tsStr)) {
        flush();
        currentBlock = {
          timestampStr: tsStr,
          timestampMs: parsedMs,
          speaker: speaker || '发言',
        };
        continue;
      }
    }

    if (currentBlock) {
      textLines.push(lines[i]);
    } else {
      // Non-transcript preamble or unformatted markdown
      textLines.push(lines[i]);
    }
  }

  flush();

  // If no blocks were parsed using headers but text exists, wrap as a single fallback block without timestamps
  if (blocks.length === 0 && body.trim()) {
    blocks.push({
      id: 'tb-fallback',
      text: body.trim(),
    });
  }

  return blocks;
}

/**
 * Finds the index of the sentence that is closest to and not later than the given time (ms).
 * If all timed sentences start after timeMs, returns index of the first timed sentence.
 * If no timed blocks, returns -1.
 */
export function findSentenceAtTime(blocks: TranscriptBlock[], timeMs: number): number {
  if (!blocks || blocks.length === 0) return -1;

  let bestIdx = -1;
  let bestMs = -1;
  let firstTimedIdx = -1;

  for (let i = 0; i < blocks.length; i++) {
    const ms = blocks[i].timestampMs;
    if (ms === undefined) continue;
    if (firstTimedIdx === -1) {
      firstTimedIdx = i;
    }
    if (ms <= timeMs) {
      if (bestIdx === -1 || ms >= bestMs) {
        bestIdx = i;
        bestMs = ms;
      }
    }
  }

  if (bestIdx !== -1) return bestIdx;
  return firstTimedIdx;
}
