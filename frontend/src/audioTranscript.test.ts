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
  assert.equal(parseTime('invalid'), 0);
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
