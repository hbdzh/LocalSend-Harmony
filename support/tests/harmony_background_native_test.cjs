// Exercises the real ArkTS long-task bridge with local fakes, without an OHOS device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const typescript = require('typescript');

function createSubject({ failStart = false, failStop = false, failPublish = false, tasksExist = true } = {}) {
  const events = [];
  class FlutterAbility { constructor() { this.context = { abilityInfo: { bundleName: 'org.localsend' } }; } }
  const modules = {
    '@ohos/flutter_ohos': { FlutterAbility },
    '../plugins/GeneratedPluginRegistrant': {},
    '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel': {},
    '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall': {},
    '@kit.AbilityKit': { wantAgent: { OperationType: { START_ABILITY: 1 }, WantAgentFlags: { CONSTANT_FLAG: 1 }, getWantAgent: async () => ({}) } },
    '@kit.NotificationKit': { notificationManager: {
      SlotType: { LIVE_VIEW: 10 }, ContentType: { NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW: 11 },
      publish: async request => { events.push(['publish', request]); if (failPublish) throw Error('publish denied'); },
    } },
    '@kit.BackgroundTasksKit': { backgroundTaskManager: {
      startBackgroundRunning: async (_context, modes) => { events.push(['start', modes]); if (failStart) throw Error('denied'); return { notificationId: 42, continuousTaskId: 17 }; },
      stopBackgroundRunning: async () => { events.push(['stop']); if (failStop) throw Error('stop failed'); },
      getAllContinuousTasks: async () => tasksExist ? [{ notificationId: 42 }] : [],
    } },
    '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: 20 } }, '@kit.CoreFileKit': {}, '@kit.ArkData': {}, '@kit.ArkUI': {}, './HarmonyShare': {},
  };
  const source = fs.readFileSync(path.join(__dirname, '../../app/ohos/entry/src/main/ets/entryability/EntryAbility.ets'), 'utf8');
  const js = typescript.transpileModule(source, { compilerOptions: { module: typescript.ModuleKind.CommonJS, target: typescript.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => modules[name] || {}, console });
  const subject = new exports.default();
  subject.backgroundChannel = { invokeMethod: method => events.push([method]) };
  async function call(method, args = {}) {
    const result = {};
    await subject.backgroundTask({ method, argument: key => args[key] }, {
      success: () => { result.ok = true; }, error: (_code, message) => { result.error = message; },
    });
    return result;
  }
  return { events, call, cancel: id => subject.backgroundCancelled({ id }) };
}

test('publishes live progress using the task notification id and stops cleanly', async () => {
  const { events, call } = createSubject();
  assert.equal((await call('start')).ok, true);
  assert.equal((await call('progress', { title: 'Sending', text: '50%', progress: 50 })).ok, true);
  const request = events[1][1];
  assert.equal(request.id, 42);
  assert.equal(request.content.systemLiveView.typeCode, 8);
  assert.equal(request.template.data.progressValue, 50);
  assert.equal((await call('stop')).ok, true);
  await call('progress', { title: 'late', text: 'late', progress: 99 });
  assert.equal(events.filter(event => event[0] === 'publish').length, 1);
});

test('reports denied tasks and never publishes progress for them', async () => {
  const { events, call } = createSubject({ failStart: true });
  assert.match((await call('start')).error, /denied/);
  await call('progress', { title: 'Sending', text: '0%', progress: 0 });
  assert.equal(events.filter(event => event[0] === 'publish').length, 0);
});


test('stop failures preserve the id when the task still exists', async () => {
  const { events, call } = createSubject({ failStop: true });
  await call('start');
  assert.match((await call('stop')).error, /stop failed/);
  await call('start');
  assert.equal(events.filter(event => event[0] === 'start').length, 1);
  assert.equal((await call('progress', { title: 'x', text: 'y', progress: 10 })).ok, true);
});

test('detects a system-cancelled task when progress publishing fails', async () => {
  const { call } = createSubject({ failPublish: true, tasksExist: false });
  await call('start');
  assert.match((await call('progress', { title: 'x', text: 'y', progress: 10 })).error, /ended by system/);
  assert.match((await call('progress', { title: 'x', text: 'y', progress: 10 })).error, /not running/);
});

test('treats a missing task as already stopped', async () => {
  const { call } = createSubject({ failStop: true, tasksExist: false });
  await call('start');
  assert.equal((await call('stop')).ok, true);
});

test('a cancellation of this task notifies Flutter and permits a new request', async () => {
  const { events, call, cancel } = createSubject();
  await call('start');
  cancel(18);
  assert.equal(events.some(event => event[0] === 'cancelled'), false);
  cancel(17);
  assert.equal(events.filter(event => event[0] === 'cancelled').length, 1);
  await call('start');
  assert.equal(events.filter(event => event[0] === 'start').length, 2);
});
