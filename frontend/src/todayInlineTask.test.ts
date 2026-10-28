import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('Today uses inline existing-task suggestions without removing yesterday carryover', () => {
  const today = readFileSync(new URL('./TodayView.tsx', import.meta.url), 'utf8');
  const tasks = readFileSync(new URL('./TasksView.tsx', import.meta.url), 'utf8');

  assert.ok(today.includes('existingTasks={tasks}') && today.includes('onSelectExisting={handleAddExisting}'));
  assert.ok(!today.includes('从已有任务中选择') && !today.includes('addModalOpen'));
  assert.ok(today.includes('昨日未完成') && today.includes('加入今天'));
  assert.ok(tasks.includes('<QuickCreateInput') && !tasks.includes('onSelectExisting='));
});

test('QuickCreateInput keeps Enter-to-create unless an existing task is explicitly selected', () => {
  const input = readFileSync(new URL('./QuickCreateInput.tsx', import.meta.url), 'utf8');

  assert.ok(input.includes('useState<string | null>(null)'), 'existing task must have no initial selection');
  assert.ok(input.includes("e.key === 'Enter' && activeTaskIndex >= 0"), 'explicit arrow selection adds an existing task');
  assert.ok(input.includes("if (e.key === 'Enter') {\n      e.preventDefault();\n      void submit();"), 'plain Enter still creates a task');
  assert.ok(input.includes('e.nativeEvent.isComposing || e.keyCode === 229'), 'Chinese IME must not submit');
  assert.ok(input.includes('if (open) {'), 'original tag autocomplete remains available');
});
