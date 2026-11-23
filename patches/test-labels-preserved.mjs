// Regression: `update labels=[3]` on a task carrying labels 2 and 4 used to
// route through the bulk label endpoint, whose `{label_ids: [...]}` payload
// Vikunja discards (it models the route as `{labels: [...]}`). The server read
// an empty list, removed every label, applied none, and still reported
// success. The patched path must read the task's existing labels and add only
// what is missing on the individual PUT endpoint -- never the bulk one. Ported
// from upstream democratize-technology/vikunja-mcp#92 (#49 for the payload
// analysis and the authoritative GET /tasks/{id}/labels read). The same defect
// existed on `create`, `bulk-create` and `bulk-update field=labels`.
import { createRequire } from 'module';
import test from 'node:test';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);

const PKG = process.env.VIKUNJA_MCP_DIST || '/tmp/vikunja-patched/dist';

function makeMockClient(existingLabelsByTask) {
  const calls = { adds: [], bulkLabelCalls: 0, labelReads: 0 };
  const mockClient = {
    tasks: {
      // The broken bulk endpoint: any call here is the bug we are guarding.
      async updateTaskLabels() {
        calls.bulkLabelCalls += 1;
        throw new Error('test: updateTaskLabels (bulk label endpoint) must never be called');
      },
      // Authoritative per-task label list.
      async getTaskLabels(taskId) {
        calls.labelReads += 1;
        return existingLabelsByTask[taskId] ?? [];
      },
      async getTask(taskId) {
        // The embedded labels array is deliberately empty: it is not reliably
        // populated, which is why the fix reads the dedicated endpoint.
        return { id: taskId, title: `task ${taskId}`, project_id: 5, labels: [] };
      },
      async addLabelToTask(taskId, labelTask) {
        calls.adds.push({ taskId, labelId: labelTask.label_id });
        return { ...labelTask };
      },
      async updateTask(taskId, data) {
        return { ...data, id: taskId };
      },
      async getProjectTasks() {
        return [];
      },
      async createTask(_projectId, data) {
        mockClient._nextId = (mockClient._nextId ?? 9) + 1;
        return { ...data, id: mockClient._nextId };
      },
    },
    _calls: calls,
  };
  return mockClient;
}

require.cache[require.resolve(`${PKG}/client.js`)] = {
  id: require.resolve(`${PKG}/client.js`),
  filename: require.resolve(`${PKG}/client.js`),
  loaded: true,
  exports: { getVikunjaClient: async () => globalThis.__mockClient },
};

test('update labels=[3] on a task with labels 2 and 4 keeps 2 and 4 and adds 3', async () => {
  const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);
  globalThis.__mockClient = makeMockClient({ 7: [{ id: 2 }, { id: 4 }] });

  const result = await updateTask({ id: 7, labels: [3] });
  const parsed = JSON.parse(result.content[0].text);

  assert.equal(
    globalThis.__mockClient._calls.bulkLabelCalls,
    0,
    'update touched the bulk label endpoint',
  );
  assert.deepEqual(
    globalThis.__mockClient._calls.adds,
    [{ taskId: 7, labelId: 3 }],
    'expected exactly one addLabelToTask for the missing label 3',
  );
  assert.ok(parsed.success, 'update reported failure');
  assert.ok(parsed.metadata.affectedFields.includes('labels'), 'affectedFields missing "labels"');
});

test('update labels=[2, 4] when both are already present is a no-op, not an error', async () => {
  const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);
  globalThis.__mockClient = makeMockClient({ 7: [{ id: 2 }, { id: 4 }] });

  const result = await updateTask({ id: 7, labels: [2, 4] });

  assert.deepEqual(globalThis.__mockClient._calls.adds, [], 're-applied labels already on the task');
  assert.equal(globalThis.__mockClient._calls.bulkLabelCalls, 0);
  assert.ok(JSON.parse(result.content[0].text).success);
});

test('update falls back to the embedded task labels when the label endpoint fails, and still never clears', async () => {
  const { updateTask } = require(`${PKG}/tools/tasks/crud.js`);
  const mock = makeMockClient({});
  mock.tasks.getTaskLabels = async () => {
    throw new Error('label endpoint unavailable');
  };
  // The fallback read sees 2 and 4 (unlike the empty embedded array above).
  mock.tasks.getTask = async (taskId) => ({
    id: taskId,
    title: 't',
    project_id: 5,
    labels: [{ id: 2 }, { id: 4 }],
  });
  globalThis.__mockClient = mock;

  await updateTask({ id: 7, labels: [3] });

  assert.deepEqual(mock._calls.adds, [{ taskId: 7, labelId: 3 }]);
  assert.equal(mock._calls.bulkLabelCalls, 0);
});

test('create applies requested labels via the individual endpoint without a label read', async () => {
  const { createTask } = require(`${PKG}/tools/tasks/crud.js`);
  globalThis.__mockClient = makeMockClient({});

  const result = await createTask({ projectId: 5, title: 'fresh', labels: [3, 5] });
  const parsed = JSON.parse(result.content[0].text);

  assert.equal(globalThis.__mockClient._calls.labelReads, 0, 'read labels for a brand-new task');
  assert.deepEqual(
    globalThis.__mockClient._calls.adds.map(({ labelId }) => labelId),
    [3, 5],
  );
  assert.equal(globalThis.__mockClient._calls.bulkLabelCalls, 0);
  assert.ok(parsed.success);
});

test('bulk-update field=labels adds only missing labels per task and never touches the bulk endpoints', async () => {
  const { bulkUpdateTasks } = require(`${PKG}/tools/tasks/bulk-operations.js`);
  const mock = makeMockClient({ 1: [{ id: 2 }, { id: 4 }], 2: [] });
  mock.tasks.bulkUpdateTasks = async () => {
    throw new Error('test: bulkUpdateTasks (server bulk endpoint) must never be called');
  };
  globalThis.__mockClient = mock;

  const result = await bulkUpdateTasks({ taskIds: [1, 2], field: 'labels', value: [3, 4] });
  const parsed = JSON.parse(result.content[0].text);

  // Task 1 keeps 2 and 4 (4 skipped as present), gets 3. Task 2 gets 3 and 4.
  assert.deepEqual(
    mock._calls.adds,
    [
      { taskId: 1, labelId: 3 },
      { taskId: 2, labelId: 3 },
      { taskId: 2, labelId: 4 },
    ],
  );
  assert.equal(mock._calls.bulkLabelCalls, 0);
  assert.ok(parsed.success, 'bulk-update reported failure');
});

test('bulk-create applies requested labels via the individual endpoint', async () => {
  const { bulkCreateTasks } = require(`${PKG}/tools/tasks/bulk-operations.js`);
  globalThis.__mockClient = makeMockClient({});

  const result = await bulkCreateTasks({
    projectId: 5,
    tasks: [{ title: 'a', labels: [3] }, { title: 'b', labels: [3, 5] }],
  });
  const parsed = JSON.parse(result.content[0].text);

  assert.deepEqual(
    globalThis.__mockClient._calls.adds.map(({ taskId, labelId }) => ({ taskId, labelId })),
    [{ taskId: 10, labelId: 3 }, { taskId: 11, labelId: 3 }, { taskId: 11, labelId: 5 }],
  );
  assert.equal(globalThis.__mockClient._calls.bulkLabelCalls, 0);
  assert.ok(parsed.success);
});
