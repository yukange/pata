export interface TranscriptBlock {
  id: string;
  timestampStr: string;
  timestampMs: number;
  speaker: string;
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

export function parseTime(ts: string): number {
  if (!ts) return 0;
  const match = ts.trim().match(/^(\d{2}):(\d{2}):(\d{2})\.(\d{3})$/);
  if (!match) return 0;
  const h = parseInt(match[1], 10);
  const m = parseInt(match[2], 10);
  const s = parseInt(match[3], 10);
  const ms = parseInt(match[4], 10);
  return h * 3600000 + m * 60000 + s * 1000 + ms;
}

const TIMESTAMP_HEADER_REGEX = /^\[(\d{2}:\d{2}:\d{2}\.\d{3})\](?:\(#t=[^)]+\))?(?:\s+(.*?))?$/;

/**
 * Parses a Stage 11 Markdown transcript into sentence blocks.
 * If the markdown has no recognized timestamp blocks, it treats the markdown as a fallback single block.
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
        id: `tb-${blocks.length}-${currentBlock.timestampMs}`,
        timestampStr: currentBlock.timestampStr || '00:00:00.000',
        timestampMs: currentBlock.timestampMs || 0,
        speaker: currentBlock.speaker || '发言',
        text: textLines.join('\n').trim(),
      });
      currentBlock = null;
      textLines = [];
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const headerMatch = line.match(TIMESTAMP_HEADER_REGEX);
    if (headerMatch) {
      flush();
      const tsStr = headerMatch[1];
      const speaker = (headerMatch[2] || '').trim();
      currentBlock = {
        timestampStr: tsStr,
        timestampMs: parseTime(tsStr),
        speaker: speaker || '发言',
      };
      textLines = [];
    } else if (currentBlock) {
      textLines.push(lines[i]);
    } else {
      // Non-transcript preamble or unformatted markdown
      textLines.push(lines[i]);
    }
  }

  flush();

  // If no blocks were parsed using headers but text exists, wrap as a single fallback block
  if (blocks.length === 0 && body.trim()) {
    blocks.push({
      id: 'tb-fallback',
      timestampStr: '00:00:00.000',
      timestampMs: 0,
      speaker: '',
      text: body.trim(),
    });
  }

  return blocks;
}

/**
 * Finds the index of the sentence that is closest to and not later than the given time (ms).
 * If all sentences start after timeMs, returns index 0.
 * If no blocks, returns -1.
 */
export function findSentenceAtTime(blocks: TranscriptBlock[], timeMs: number): number {
  if (!blocks || blocks.length === 0) return -1;
  if (timeMs <= blocks[0].timestampMs) return 0;
  if (timeMs >= blocks[blocks.length - 1].timestampMs) return blocks.length - 1;

  let low = 0;
  let high = blocks.length - 1;
  let ans = 0;

  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (blocks[mid].timestampMs <= timeMs) {
      ans = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return ans;
}
