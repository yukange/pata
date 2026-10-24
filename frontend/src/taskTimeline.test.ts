import { test } from 'node:test';
import assert from 'node:assert';
import {
  buildTaskTimelineItems,
  formatActivityTimestamp,
  formatFullLocalTimestamp,
  type TaskActivity,
  type TaskLike,
} from './taskTimeline.ts';

function createMockTask(overrides?: Partial<TaskLike>): TaskLike {
  return {
    id: 't-test-001',
    title: '测试任务',
    status: 'todo',
    completed_at: null,
    status_events: [],
    ...overrides,
  };
}

test('buildTaskTimelineItems: 手动 Activity 与完成/重新打开事件按时间正向混排', () => {
  const task = createMockTask({
    status: 'done',
    status_events: [
      {
        action: 'completed',
        at: '2026-10-20T10:00:00Z',
      },
      {
        action: 'reopened',
        at: '2026-10-20T11:00:00Z',
      },
      {
        action: 'completed',
        at: '2026-10-20T14:00:00Z',
      },
    ],
  });

  const activities: TaskActivity[] = [
    {
      id: 'a-001',
      at: '2026-10-20T09:30:00Z',
      body: '初版沟通',
    },
    {
      id: 'a-002',
      at: '2026-10-20T12:00:00Z',
      body: '重新修改方案',
    },
  ];

  const items = buildTaskTimelineItems(task, activities);

  assert.strictEqual(items.length, 5);

  // 正向顺序（由早到晚）：
  // 1. 09:30 初版沟通 (activity)
  // 2. 10:00 首次完成 (status_event)
  // 3. 11:00 重新打开 (status_event)
  // 4. 12:00 修改方案 (activity)
  // 5. 14:00 再次完成 (status_event)
  assert.strictEqual(items[0].kind, 'activity');
  assert.strictEqual(items[0].at, '2026-10-20T09:30:00Z');
  assert.strictEqual((items[0] as any).activity.id, 'a-001');

  assert.strictEqual(items[1].kind, 'status_event');
  assert.strictEqual(items[1].at, '2026-10-20T10:00:00Z');
  assert.strictEqual((items[1] as any).action, 'completed');

  assert.strictEqual(items[2].kind, 'status_event');
  assert.strictEqual(items[2].at, '2026-10-20T11:00:00Z');
  assert.strictEqual((items[2] as any).action, 'reopened');

  assert.strictEqual(items[3].kind, 'activity');
  assert.strictEqual(items[3].at, '2026-10-20T12:00:00Z');
  assert.strictEqual((items[3] as any).activity.id, 'a-002');

  assert.strictEqual(items[4].kind, 'status_event');
  assert.strictEqual(items[4].at, '2026-10-20T14:00:00Z');
  assert.strictEqual((items[4] as any).action, 'completed');
});

test('buildTaskTimelineItems: 只有状态事件无手动 Activity 时能看到历史', () => {
  const task = createMockTask({
    status: 'done',
    status_events: [
      {
        action: 'completed',
        at: '2026-10-20T10:00:00Z',
      },
    ],
  });

  const items = buildTaskTimelineItems(task, []);
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].kind, 'status_event');
  assert.strictEqual((items[0] as any).action, 'completed');
});

test('buildTaskTimelineItems: 两者均为空时返回空列表', () => {
  const task = createMockTask({
    status: 'todo',
    status_events: [],
  });

  const items = buildTaskTimelineItems(task, []);
  assert.strictEqual(items.length, 0);
});

test('buildTaskTimelineItems: 完成 -> 重新打开 -> 再完成 三次事件完整保留并正向排序', () => {
  const task = createMockTask({
    status: 'done',
    status_events: [
      {
        action: 'completed',
        at: '2026-10-18T10:00:00Z',
      },
      {
        action: 'reopened',
        at: '2026-10-19T10:00:00Z',
      },
      {
        action: 'completed',
        at: '2026-10-20T10:00:00Z',
      },
    ],
  });

  const items = buildTaskTimelineItems(task, []);
  assert.strictEqual(items.length, 3);
  assert.strictEqual((items[0] as any).action, 'completed');
  assert.strictEqual(items[0].at, '2026-10-18T10:00:00Z');
  assert.strictEqual((items[1] as any).action, 'reopened');
  assert.strictEqual(items[1].at, '2026-10-19T10:00:00Z');
  assert.strictEqual((items[2] as any).action, 'completed');
  assert.strictEqual(items[2].at, '2026-10-20T10:00:00Z');
});

test('buildTaskTimelineItems: 相同时间戳时次序稳定', () => {
  const sameTime = '2026-10-20T10:00:00.000Z';
  const task = createMockTask({
    status_events: [
      {
        action: 'completed',
        at: sameTime,
      },
    ],
  });

  const activities: TaskActivity[] = [
    {
      id: 'a-001',
      at: sameTime,
      body: '同一秒的记录',
    },
  ];

  const firstRun = buildTaskTimelineItems(task, activities);
  const secondRun = buildTaskTimelineItems(task, activities);

  assert.strictEqual(firstRun.length, 2);
  assert.strictEqual(firstRun[0].key, secondRun[0].key);
  assert.strictEqual(firstRun[1].key, secondRun[1].key);
});

test('buildTaskTimelineItems: 兼容老数据或外部修改仅有 completed_at 却无 status_events 记录', () => {
  const task = createMockTask({
    status: 'done',
    completed_at: '2026-10-20T09:00:00Z',
    status_events: [],
  });

  const items = buildTaskTimelineItems(task, []);
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].kind, 'status_event');
  assert.strictEqual(items[0].at, '2026-10-20T09:00:00Z');
  assert.strictEqual((items[0] as any).action, 'completed');
});

test('buildTaskTimelineItems: 创建来源与同时间生命周期顺序，不生成普通 Activity', () => {
  const at = '2026-10-23T09:20:00+08:00';
  const task = createMockTask({
    created_at: at,
    created_by: 'agent',
    status: 'done',
    status_events: [
      { action: 'completed', at: '2026-10-23T01:20:00Z', by: 'agent' },
      { action: 'reopened', at },
      { action: 'completed', at, by: 'agent' },
    ],
  });
  const items = buildTaskTimelineItems(task, [{ id: 'a-agent', at, body: '评论', by: 'agent' }]);
  assert.deepStrictEqual(items.map((item) => item.kind === 'status_event' ? [item.action, item.by] : ['activity', item.activity.by]), [
    ['creation', 'agent'], ['completed', 'agent'], ['reopened', undefined], ['completed', 'agent'], ['activity', 'agent'],
  ]);
  assert.strictEqual(items[0].key, `0-created-${task.id}`);
  assert.deepStrictEqual(items, buildTaskTimelineItems(task, [{ id: 'a-agent', at, body: '评论', by: 'agent' }]));
});

test('buildTaskTimelineItems: 旧数据创建与 completed_at 兜底均默认为我', () => {
  const items = buildTaskTimelineItems(createMockTask({
    created_at: '2026-10-22T23:50:00+08:00',
    status: 'done', completed_at: '2026-10-23T00:10:00+08:00',
  }), []);
  assert.deepStrictEqual(items.map((item) => item.kind === 'status_event' && [item.action, item.by]), [
    ['creation', undefined], ['completed', undefined],
  ]);
});

test('buildTaskTimelineItems: 同时发生的十次以上状态事件仍保留写入顺序', () => {
  const task = createMockTask({
    status_events: Array.from({ length: 12 }, (_, idx) => ({
      action: idx % 2 === 0 ? 'completed' : 'reopened', at: '2026-10-23T09:00:00Z',
    })),
  });
  const items = buildTaskTimelineItems(task, []);
  assert.deepStrictEqual(items.map((item) => item.kind === 'status_event' && item.action), task.status_events?.map((event) => event.action));
});

test('buildTaskTimelineItems: 旧完成事件不能遮蔽缺失对应事件的 completed_at', () => {
  const items = buildTaskTimelineItems(createMockTask({
    status: 'done', completed_at: '2026-10-23T00:10:00+08:00',
    status_events: [{ action: 'completed', at: '2026-10-22T09:00:00+08:00', by: 'agent' }],
  }), []);
  assert.strictEqual(items.length, 2);
  assert.ok(items[1].kind === 'status_event' && items[1].action === 'completed' && items[1].by === undefined);
});

test('formatActivityTimestamp: 格式化不同日期的展示时间', () => {
  const now = new Date(2026, 9, 20, 15, 30, 0); // 2026-10-20 15:30:00
  const todayIso = new Date(2026, 9, 20, 10, 5, 0).toISOString();
  const thisYearIso = new Date(2026, 8, 15, 9, 20, 0).toISOString();
  const prevYearIso = new Date(2025, 4, 1, 8, 0, 0).toISOString();

  assert.match(formatActivityTimestamp(todayIso, now), /^\d{2}:\d{2}$/);
  assert.match(formatActivityTimestamp(thisYearIso, now), /^\d{2}-\d{2} \d{2}:\d{2}$/);
  assert.match(formatActivityTimestamp(prevYearIso, now), /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
  assert.strictEqual(formatActivityTimestamp(''), '');
});

test('formatFullLocalTimestamp: 完整本机时间展示', () => {
  const dateIso = new Date(2026, 9, 20, 10, 5, 3).toISOString();
  const formatted = formatFullLocalTimestamp(dateIso);
  assert.match(formatted, /^2026-10-20 \d{2}:\d{2}:\d{2}$/);
  assert.strictEqual(formatFullLocalTimestamp(null), '');
  assert.strictEqual(formatFullLocalTimestamp(''), '');
});
