import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

import { componentCallbacks } from '../scripts/componentCallbacks.ts';
import { filterCandidates, pickerKey } from './noteRefsCore.ts';

const callback = componentCallbacks(new URL('./NotesView.tsx', import.meta.url));
const isAudioTranscriptNote = callback('isAudioTranscriptNote');
const getNoteExcerpt = callback('getNoteExcerpt');
const getDraftExcerpt = callback('getDraftExcerpt');

test('isAudioTranscriptNote: correctly identifies transcript notes vs regular notes', () => {
  assert.equal(isAudioTranscriptNote(null), false);
  assert.equal(isAudioTranscriptNote({}), false);
  assert.equal(isAudioTranscriptNote({ audio_transcript: false }), false);
  assert.equal(isAudioTranscriptNote({ audio_transcript: true, audio_file: '' }), false);
  assert.equal(isAudioTranscriptNote({ audio_transcript: true, audio_file: '   ' }), false);
  assert.equal(isAudioTranscriptNote({ audio_transcript: true, audio_file: 'files/audio.m4a' }), true);
});

test('getNoteExcerpt: strips leading duplicate title heading and cleans markdown tokens', () => {
  const body1 = '# 系统架构\n这是核心架构设计的正文，包含**重点**与`代码`。';
  assert.equal(getNoteExcerpt('系统架构', body1), '这是核心架构设计的正文，包含重点与代码。');

  // When heading does not match title, keep it
  const body2 = '# 另一部分\n这是其他内容。';
  assert.equal(getNoteExcerpt('系统架构', body2), '另一部分 这是其他内容。');

  // Empty or whitespace body
  assert.equal(getNoteExcerpt('标题', ''), '');
  assert.equal(getNoteExcerpt('标题', undefined), '');

  // Strip complex markdown tokens
  const body3 = '> 引用文字\n- [ ] 待办项\n~~删除文字~~';
  assert.equal(getNoteExcerpt('测试', body3), '引用文字 - 待办项 删除文字');
});

test('getDraftExcerpt: returns up to 2 clean lines without markdown syntax', () => {
  assert.equal(getDraftExcerpt(''), '');
  assert.equal(getDraftExcerpt(undefined), '');
  assert.equal(getDraftExcerpt('   \n\n  '), '');

  // Markdown heading, task item, and links stripped
  const body1 = '# 第一行思考\n- [x] 完成任务项 [链接](http://example.com)\n> 第三行引用';
  assert.equal(
    getDraftExcerpt(body1),
    '第一行思考\n完成任务项 链接'
  );

  // Wiki link and formatting stripped
  const body2 = '这是包含 [[WikiNote|别名]] 和 `code` 与 **加粗** 的草稿\n第二行内容\n第三行内容被截断';
  assert.equal(
    getDraftExcerpt(body2),
    '这是包含 WikiNote 和 code 与 加粗 的草稿\n第二行内容'
  );

  // Blank lines skipped
  const body3 = '\n\n  \n第一行实际内容\n\n\n第二行实际内容\n第三行';
  assert.equal(
    getDraftExcerpt(body3),
    '第一行实际内容\n第二行实际内容'
  );
});

test('没有 [[ 候选时保留 Vditor 原生键盘处理', () => {
  callback('onKey', { pickerRef: { current: null } })({
    key: 'ArrowDown', isComposing: false, keyCode: 0,
    preventDefault: () => assert.fail('无笔记候选时应保留原生按键处理'),
    stopPropagation: () => assert.fail('无笔记候选时不应拦截按键'),
  });
});

test('[[ 笔记候选仍可用方向键选择', () => {
  let picker = { start: 0, query: '', index: 0 };
  let prevented = false;
  let stopped = false;
  callback('onKey', {
    pickerRef: { current: picker },
    allNotesRef: { current: [{ id: 'n-1', title: 'One' }, { id: 'n-2', title: 'Two' }] },
    allFilesRef: { current: [] },
    filterCandidates, pickerKey,
    setPicker: (next: typeof picker) => { picker = next; },
  })({
    key: 'ArrowDown', isComposing: false, keyCode: 0,
    preventDefault: () => { prevented = true; },
    stopPropagation: () => { stopped = true; },
  });
  assert.equal(picker.index, 1);
  assert.ok(prevented);
  assert.ok(stopped);
});

test('笔记右上角更多菜单包含复制绝对路径与在 Finder 中打开操作', () => {
  const notesSrc = fs.readFileSync(new URL('./NotesView.tsx', import.meta.url), 'utf-8');
  assert.ok(notesSrc.includes('复制绝对路径'), '应包含复制绝对路径菜单项');
  assert.ok(notesSrc.includes('在 Finder 中打开'), '应包含在 Finder 中打开菜单项');
  assert.ok(notesSrc.includes('VaultService.GetNotePath'), '应调用 GetNotePath 获取绝对路径');
  assert.ok(notesSrc.includes('VaultService.RevealNoteInFinder'), '应调用 RevealNoteInFinder 打开文件');
  assert.ok(notesSrc.includes('copyToClipboard'), '应使用 copyToClipboard 复制路径');
  assert.ok(notesSrc.includes("showToast('已复制绝对路径')"), '复制成功应弹出 Toast 提示');
});

test('笔记外部冲突处理：干净状态下静默重载，脏状态下提供极简操作条与覆盖选项', () => {
  const notesSrc = fs.readFileSync(new URL('./NotesView.tsx', import.meta.url), 'utf-8');
  assert.ok(notesSrc.includes('!dirty'), '应先判断当前编辑器是否处于干净状态');
  assert.ok(notesSrc.includes('isDirtyRef.current(curTitle, curTags, curBody)'), '静默重载在异步返回后应二次检查脏状态防丢输入');
  assert.ok(notesSrc.includes('lastSavedStateRef.current.body = vditor.getValue()'), 'Vditor 挂载后应将基准正文对齐为编辑器规范化值，避免打开即判定为脏数据');
  assert.ok(notesSrc.includes('normalizeBody'), '应使用 normalizeBody 归一化换行符与尾随空白对比正文，避免假冲突');
  assert.ok(!notesSrc.includes('isUserEditedRef'), '精简状态：不需要维护额外的 isUserEditedRef 标记');
  assert.ok(!notesSrc.includes('isVditorMountedRef'), '精简状态：直接使用 vditorRef 判定挂载，不维护冗余布尔值');
  assert.ok(!notesSrc.includes('hasConflictRef'), '精简状态：保存冲突收敛至 saveStatus 状态机');
  assert.ok(!notesSrc.includes('isSavingRef'), '精简状态：保存中统一由 inFlightSaveRef 判定');
  assert.ok(notesSrc.includes('用本地草稿覆盖'), '冲突栏应提供用本地草稿覆盖按钮');
  assert.ok(notesSrc.includes('载入外部版本'), '冲突栏应提供载入外部版本按钮');
  assert.ok(notesSrc.includes('handleResolveConflictKeepMine'), '应包含覆盖外部保存的逻辑');
  assert.ok(!notesSrc.includes('subVault = Events.On(\'vault:changed\''), '音频播放器内不应存在多余的重复 vault:changed 监听器');
  assert.ok(!notesSrc.includes('currentSrc.includes(fileName)'), '图片刷新不应使用模糊的前缀/子串匹配');
  assert.ok(notesSrc.includes('srcName === fileName'), '图片刷新应对文件名作精确比对与 URL 解码');
  assert.ok(!notesSrc.includes('自动保存已停止，当前本地草稿尚未写盘。为防内容丢失'), '不应再使用旧的长篇恐吓说明文案');
  assert.ok(!notesSrc.includes('<span>保存中...</span>'), '本地自动写盘应静默无感，不应在右上角闪烁保存中提示');
});

test('笔记编辑器生命周期与防重置：Vditor 挂载仅依赖 loadingNote，保存不重构编辑器', () => {
  const notesSrc = fs.readFileSync(new URL('./NotesView.tsx', import.meta.url), 'utf-8');
  assert.ok(
    notesSrc.includes('}, [loadingNote]);'),
    'Vditor 挂载 useEffect 依赖数组应仅为 [loadingNote]，不能包含 initialNote，避免保存时销毁编辑器并失焦滚顶'
  );
  assert.ok(
    notesSrc.includes('inFlightSaveRef.current'),
    '应使用 inFlightSaveRef 记录在途保存状态'
  );
  assert.ok(
    notesSrc.includes('isDiskIdenticalToLocal'),
    '应对比磁盘内容与最后保存或在途保存状态，判定是否为自身写入事件'
  );
  assert.ok(
    notesSrc.includes('if (diskBody !== vditorRef.current.getValue())'),
    '仅在外部磁盘正文与当前编辑器内容真实不一致时才调用 setValue'
  );
});
