import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('Today uses inline existing-task suggestions without removing yesterday carryover', () => {
  const today = readFileSync(new URL('./TodayView.tsx', import.meta.url), 'utf8');
  const tasks = readFileSync(new URL('./TasksView.tsx', import.meta.url), 'utf8');

  assert.match(today, /existingTasks=\{tasks\}[\s\S]*?onSelectExisting=\{handleAddExisting\}/);
  assert.doesNotMatch(today, /从已有任务中选择|addModalOpen/);
  assert.match(today, /昨日未完成/);
  assert.match(today, /加入今天/);
  assert.match(today, /关闭昨日未完成提醒/);
  assert.match(today, /dismissedYesterdayForDate/);
  assert.match(tasks, /<QuickCreateInput/);
  assert.doesNotMatch(tasks, /onSelectExisting=/);
});

test('QuickCreateInput keeps Enter-to-create unless an existing task is explicitly selected', () => {
  const input = readFileSync(new URL('./QuickCreateInput.tsx', import.meta.url), 'utf8');

  // No initial active selection so normal typing is not hijacked
  assert.match(input, /useState<string\s*\|\s*null>\(null\)/);
  // Arrow key selection explicitly binds Enter to adding the selected existing task
  assert.match(input, /e\.key\s*===\s*['"]Enter['"]\s*&&\s*activeTaskIndex\s*>=\s*0/);
  // Plain Enter still creates a task
  assert.match(input, /if\s*\(\s*e\.key\s*===\s*['"]Enter['"]\s*\)\s*\{[\s\S]*?submit\(\)/);
  // Chinese IME composition protects Enter from submitting early
  assert.match(input, /isComposing\s*\|\|\s*e\.keyCode\s*===\s*229/);
  // Tag autocomplete remains available
  assert.match(input, /if\s*\(\s*open\s*\)\s*\{/);
  // Selecting keeps the dropdown open and maintains selection on the next item; Escape blurs the input
  assert.match(input, /selectExisting[\s\S]*?setActiveTaskId\(nextTaskId\)/);
  assert.match(input, /selectExisting[\s\S]*?setDismissedFor\(null\)/);
  assert.match(input, /e\.key\s*===\s*['"]Escape['"][\s\S]*?inputRef\.current\?\.blur\(\)/);
  assert.match(input, /onBlur[\s\S]*?setDismissedFor\(null\)/);

  // Tabs for uncompleted and completed tasks when browsing without search
  assert.match(input, /useState<'uncompleted'\s*\|\s*'completed'>\('uncompleted'\)/);
  assert.match(input, /!hasQuery\s*&&[\s\S]*?role="tablist"/);
  assert.match(input, /e\.key\s*===\s*['"]ArrowRight['"][\s\S]*?setTab\('completed'\)/);
  assert.match(input, /e\.key\s*===\s*['"]ArrowLeft['"][\s\S]*?setTab\('uncompleted'\)/);
  // Arrow keys clamp at boundaries without cycling/wrapping
  assert.match(input, /Math\.min\(activeTaskIndex\s*\+\s*1,\s*taskOptions\.length\s*-\s*1\)/);
  assert.match(input, /Math\.max\(activeTaskIndex\s*-\s*1,\s*0\)/);
  assert.doesNotMatch(input, /% taskOptions\.length/);
});
