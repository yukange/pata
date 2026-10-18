import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  formatTime,
  parseTime,
  parseTranscript,
  findSentenceAtTime,
} from './audioTranscript.ts';

test('formatTime & parseTime: millisecond precision', () => {
  assert.equal(formatTime(0), '00:00:00.000');
  assert.equal(formatTime(123), '00:00:00.123');
  assert.equal(formatTime(1000), '00:00:01.000');
  assert.equal(formatTime(65230), '00:01:05.230');
  assert.equal(formatTime(3661005), '01:01:01.005');

  assert.equal(parseTime('00:00:00.000'), 0);
  assert.equal(parseTime('00:01:05.230'), 65230);
  assert.equal(parseTime('01:01:01.005'), 3661005);
  assert.equal(parseTime('invalid'), null);
  assert.equal(parseTime('00:99:00.000'), null);
  assert.equal(parseTime('00:00:60.000'), null);
});

test('parseTranscript: parses markdown blocks with timestamps and speakers', () => {
  const md = `[00:01:05.230](#t=00:01:05.230) 说话人 1

我们先讨论一下这次技术架构的调整。

[00:01:18.760](#t=00:01:18.760) 说话人 2

我觉得可以先把现有的方案简化一下。`;

  const blocks = parseTranscript(md);
  assert.equal(blocks.length, 2);

  assert.equal(blocks[0].timestampStr, '00:01:05.230');
  assert.equal(blocks[0].timestampMs, 65230);
  assert.equal(blocks[0].speaker, '说话人 1');
  assert.equal(blocks[0].text, '我们先讨论一下这次技术架构的调整。');

  assert.equal(blocks[1].timestampStr, '00:01:18.760');
  assert.equal(blocks[1].timestampMs, 78760);
  assert.equal(blocks[1].speaker, '说话人 2');
  assert.equal(blocks[1].text, '我觉得可以先把现有的方案简化一下。');
});

test('findSentenceAtTime: binary search for closest sentence <= time', () => {
  const blocks = [
    { id: '1', timestampStr: '00:00:00.000', timestampMs: 0, speaker: 'S1', text: 'Intro' },
    { id: '2', timestampStr: '00:00:10.000', timestampMs: 10000, speaker: 'S2', text: 'Second' },
    { id: '3', timestampStr: '00:00:30.000', timestampMs: 30000, speaker: 'S1', text: 'Third' },
  ];

  assert.equal(findSentenceAtTime(blocks, 0), 0);
  assert.equal(findSentenceAtTime(blocks, 5000), 0);
  assert.equal(findSentenceAtTime(blocks, 10000), 1);
  assert.equal(findSentenceAtTime(blocks, 25000), 1);
  assert.equal(findSentenceAtTime(blocks, 30000), 2);
  assert.equal(findSentenceAtTime(blocks, 45000), 2);
});

test('parseTranscript: retains preamble text before first timestamp block without fabricating timestamps', () => {
  const md = `# 晨会记录
这是前言说明内容。

[00:00:05.100](#t=00:00:05.100) 说话人 1

会议正式开始。`;

  const blocks = parseTranscript(md);
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].text, '# 晨会记录\n这是前言说明内容。');
  assert.equal(blocks[0].timestampMs, undefined);
  assert.equal(blocks[0].timestampStr, undefined);
  assert.equal(blocks[1].text, '会议正式开始。');
  assert.equal(blocks[1].timestampMs, 5100);
  assert.equal(blocks[1].timestampStr, '00:00:05.100');
});

test('parseTranscript: fallback for unformatted markdown has no fabricated timestamps', () => {
  const md = '普通纯文本会议记录，未包含任何时间戳结构。';
  const blocks = parseTranscript(md);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].text, md);
  assert.equal(blocks[0].timestampMs, undefined);
  assert.equal(blocks[0].timestampStr, undefined);
  assert.equal(findSentenceAtTime(blocks, 5000), -1);
});

test('parseTranscript: rejects invalid timestamp ranges and mismatched anchors', () => {
  const md = `[00:99:00.000](#t=garbage) 说话人 1
这是分钟超限且锚点不符的内容。

[00:01:00.000](#t=00:02:00.000) 说话人 2
这是锚点不匹配的内容。

[00:01:05.230](#t=00:01:05.230) 说话人 1
这是合法的时间戳。`;

  const blocks = parseTranscript(md);
  assert.equal(blocks.length, 2);
  assert.ok(blocks[0].text.includes('[00:99:00.000](#t=garbage)'));
  assert.ok(blocks[0].text.includes('[00:01:00.000](#t=00:02:00.000)'));
  assert.equal(blocks[0].timestampMs, undefined);
  assert.equal(blocks[0].timestampStr, undefined);

  assert.equal(blocks[1].timestampStr, '00:01:05.230');
  assert.equal(blocks[1].timestampMs, 65230);
  assert.equal(blocks[1].text, '这是合法的时间戳。');
});

test('findSentenceAtTime: handles non-chronological blocks from external edits', () => {
  const blocks = [
    { id: '1', timestampStr: '00:00:10.000', timestampMs: 10000, speaker: 'S1', text: '10s block' },
    { id: '2', timestampStr: '00:00:05.000', timestampMs: 5000, speaker: 'S2', text: '5s block' },
    { id: '3', timestampStr: '00:00:15.000', timestampMs: 15000, speaker: 'S1', text: '15s block' },
    { id: '4', timestampStr: '00:00:08.000', timestampMs: 8000, speaker: 'S2', text: '8s block' },
  ];

  // Seeking to 6s should pick the 5s block (index 1), not fail at the first 10s block
  assert.equal(findSentenceAtTime(blocks, 6000), 1);
  // Seeking to 9s should pick the 8s block (index 3)
  assert.equal(findSentenceAtTime(blocks, 9000), 3);
  // Seeking to 11s should pick the 10s block (index 0)
  assert.equal(findSentenceAtTime(blocks, 11000), 0);
  // Seeking to 20s should pick the 15s block (index 2)
  assert.equal(findSentenceAtTime(blocks, 20000), 2);
  // Seeking before any block (e.g. 2s) should return the first timed block (index 0)
  assert.equal(findSentenceAtTime(blocks, 2000), 0);
});



