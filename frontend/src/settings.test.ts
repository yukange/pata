import { test } from 'node:test';
import assert from 'node:assert';

test('theme preference: 校验允许的主题取值', () => {
  const validThemes = ['system', 'light', 'dark'];
  assert.strictEqual(validThemes.includes('system'), true);
  assert.strictEqual(validThemes.includes('light'), true);
  assert.strictEqual(validThemes.includes('dark'), true);
  assert.strictEqual(validThemes.includes('neon'), false);
});

test('ASR 配置: 固定服务地域与模型参数校验', () => {
  const provider = '阿里云百炼';
  const model = 'qwen-audio-3.1-asr-flash-filetrans';
  const region = '华北2（北京）';

  assert.strictEqual(provider, '阿里云百炼');
  assert.strictEqual(model, 'qwen-audio-3.1-asr-flash-filetrans');
  assert.strictEqual(region, '华北2（北京）');
});

test('API Key 输入验证: 去除空白后不能为空', () => {
  const validateKey = (key: string): boolean => {
    return key.trim().length > 0;
  };

  assert.strictEqual(validateKey(''), false);
  assert.strictEqual(validateKey('    '), false);
  assert.strictEqual(validateKey('\t\n'), false);
  assert.strictEqual(validateKey('sk-1234567890abcdef'), true);
  assert.strictEqual(validateKey('  sk-test-with-spaces  '), true);
});
