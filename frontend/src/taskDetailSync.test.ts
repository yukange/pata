import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { dedupeTags } from './tagUtils.ts';

// Execute the component's real callbacks without a browser or a second React renderer.
const source = ts.createSourceFile('TaskDetailPanel.tsx', fs.readFileSync(new URL('./TaskDetailPanel.tsx', import.meta.url), 'utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
const callbacks = new Map<string, ts.Expression>();
function visit(node: ts.Node) {
  if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) {
    const init = node.initializer;
    callbacks.set(node.name.text, ts.isCallExpression(init) && init.expression.getText(source) === 'useCallback' ? init.arguments[0] : init);
  }
  if (ts.isCallExpression(node) && node.expression.getText(source) === 'Events.On' && node.arguments[0].getText(source) === "'vault:changed'") {
    callbacks.set('onVaultChanged', node.arguments[1]);
  }
  ts.forEachChild(node, visit);
}
visit(source);

function callback(name: string, context: Record<string, any>): (...args: any[]) => any {
  const expression = callbacks.get(name);
  assert.ok(expression, `missing ${name} callback`);
  const code = ts.transpileModule(`(${expression.getText(source)})`, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  return vm.runInNewContext(code, context);
}

function inspector() {
  const original = { id: 't-test', title: '任务', status: 'todo', description: '', tags: [], note_refs: {} };
  const remote = { ...original, status: 'done', status_events: [{ action: 'completed', by: 'agent' }] };
  const state: Record<string, any> = { Task: original };
  const writes: any[] = [];
  const reloads: Promise<void>[] = [];
  const timers: { run: () => void; cancelled: boolean }[] = [];
  const context: Record<string, any> = {
    taskId: original.id, task: original, detailTitle: '新标题',
    latestTaskRef: { current: original }, latestTitleRef: { current: original.title },
    latestStatusRef: { current: 'todo' }, latestDueRef: { current: '' },
    latestTagsRef: { current: [] }, latestBodyRef: { current: '' }, latestRefsRef: { current: {} },
    externalModifiedRef: { current: false }, externalChangeVersionRef: { current: 0 },
    hasDraftRef: { current: false }, debounceTimerRef: { current: null },
    dedupeTags, pruneRefs: (_body: string, refs: object) => refs,
    isConflictErr: (err: Error) => err.message.includes('conflict'),
    loadActivities: async () => {}, onChanged: () => {},
    setTimeout: (run: () => void) => {
      const timer = { run, cancelled: false };
      timers.push(timer);
      return timer;
    },
    clearTimeout: (timer: { cancelled: boolean }) => { timer.cancelled = true; },
    VaultService: {
      GetTask: async () => remote,
      UpdateTask: async (input: any) => { writes.push(input); return { ...remote, ...input }; },
    },
  };
  for (const name of ['Task', 'DetailTitle', 'DetailStatus', 'DetailDue', 'DetailTags', 'DetailBody', 'DetailRefs', 'DetailError', 'ConflictError', 'ExternalModified', 'LoadError', 'Saving']) {
    context[`set${name}`] = (value: any) => { state[name] = typeof value === 'function' ? value(state[name]) : value; };
  }
  context.applyTask = callback('applyTask', context);
  const reload = callback('reload', context);
  context.reload = (...args: any[]) => {
    const pending = reload(...args);
    reloads.push(pending);
    return pending;
  };
  context.saveTask = callback('saveTask', context);
  return { context, state, writes, reloads, timers, remote, changed: callback('onVaultChanged', context) };
}

test('MCP completion pauses queued, blur, and keyboard saves while preserving a task draft', async () => {
  const h = inspector();
  callback('handleBodyChange', h.context)('未保存的正文');
  const timer = h.timers[0];
  h.changed({ data: { entity_id: 't-test' } });
  assert.equal(timer.cancelled, true);
  assert.equal(h.context.debounceTimerRef.current, null);
  assert.equal(h.state.DetailBody, '未保存的正文');
  assert.equal(h.reloads.length, 0);

  timer.run(); // Even an already queued callback must not write stale status.
  await callback('handleTitleBlur', h.context)();
  assert.equal(await h.context.saveTask(), false);
  callback('handleBodyChange', h.context)('继续编辑的草稿');
  assert.equal(h.state.DetailBody, '继续编辑的草稿');
  assert.equal(h.timers.length, 1);
  assert.equal(h.writes.length, 0);

  h.context.VaultService.GetTask = async () => { throw new Error('读取失败'); };
  await h.context.reload();
  assert.equal(h.context.externalModifiedRef.current, true);
  assert.equal(await h.context.saveTask(), false);

  h.context.VaultService.GetTask = async () => h.remote;
  await h.context.reload();
  assert.equal(h.context.externalModifiedRef.current, false);
  assert.equal(h.context.latestStatusRef.current, 'done');
  assert.equal(await h.context.saveTask({ title: '新标题' }), true);
  assert.equal(h.writes[0].status, 'done');
});

test('MCP completion refreshes a clean inspector and ignores changes to other tasks', async () => {
  const h = inspector();
  h.changed({ data: { entity_id: 't-other' } });
  assert.equal(h.reloads.length, 0);
  assert.equal(h.context.externalModifiedRef.current, false);
  h.changed({ data: { entity_id: 't-test' } });
  assert.equal(h.context.externalModifiedRef.current, true);
  await h.reloads[0];
  assert.equal(h.state.Task.status, 'done');
  assert.equal(h.state.Task.status_events[0].by, 'agent');
  assert.equal(h.context.latestStatusRef.current, 'done');
  assert.equal(h.context.externalModifiedRef.current, false);
});

test('Automatic refresh preserves a draft started while loading and rejects older responses', async () => {
  const h = inspector();
  let finish!: (task: any) => void;
  h.context.VaultService.GetTask = () => new Promise((resolve) => { finish = resolve; });
  h.changed({ data: { entity_id: 't-test' } });
  callback('handleBodyChange', h.context)('加载期间输入的草稿');
  finish(h.remote);
  await h.reloads[0];
  assert.equal(h.state.Task.status, 'todo');
  assert.equal(h.context.externalModifiedRef.current, true);

  h.context.hasDraftRef.current = false;
  h.changed({ data: { entity_id: 't-test' } });
  const finishOld = finish;
  h.changed({ data: { entity_id: 't-test' } });
  finish(h.remote);
  await h.reloads[2];
  finishOld({ ...h.remote, status: 'todo' });
  await h.reloads[1];
  assert.equal(h.state.Task.status, 'done');
  assert.equal(h.context.externalModifiedRef.current, false);
});

test('A save response cannot clear an external-change guard raised during that save', async () => {
  const h = inspector();
  let finish!: (task: any) => void;
  h.context.VaultService.UpdateTask = () => new Promise((resolve) => { finish = resolve; });
  const pending = h.context.saveTask({ title: '新标题' });
  h.changed({ data: { entity_id: 't-test' } });
  finish(h.remote);
  assert.equal(await pending, false);
  assert.equal(h.context.externalModifiedRef.current, true);
  assert.equal(h.state.ExternalModified, true);
  assert.equal(h.state.Task.title, '任务');
});
