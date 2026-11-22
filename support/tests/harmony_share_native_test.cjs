// Runs the real ArkTS sharing code with local system API fakes; no device is required.
// NODE_PATH must include DevEco's bundled TypeScript module.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const typescript = require('typescript');

function createSubject(root, overrides = {}) {
  const listeners = [];
  const nativeFs = {
    mkdtempSync: fs.mkdtempSync, listFileSync: fs.readdirSync, lstatSync: overrides.lstatSync || fs.lstatSync,
    rmdirSync: p => fs.rmSync(p, { recursive: true, force: true }), renameSync: fs.renameSync, unlinkSync: fs.unlinkSync,
  };
  const share = {
    ShareResultCode: { SHARE_SUCCESS: 0, SEND_FAILED: 1 },
    on: (...args) => listeners.push(['on', ...args]),
    off: (...args) => listeners.push(['off', ...args]),
  };
  const modules = {
    '@kit.AbilityKit': {},
    '@kit.ShareKit': { harmonyShare: share, systemShare: {} },
    '@kit.ArkUI': { window: { getLastWindow: overrides.getWindow || (async () => ({ getWindowProperties: () => ({ id: 7 }) })) } },
    '@kit.BasicServicesKit': { deviceInfo: { deviceType: '2in1', sdkApiVersion: overrides.api || 20 } },
    '@kit.CoreFileKit': { fileIo: nativeFs, fileUri: { getUriFromPath: p => 'file://' + encodeURI(p), FileUri: class { constructor(uri) { this.path = decodeURIComponent(uri.slice(7)); } } } },
    '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { FILE: 'general.file' } } },
    '@ohos/flutter_ohos': {},
  };
  const source = fs.readFileSync(path.join(__dirname, '../../app/ohos/entry/src/main/ets/entryability/HarmonyShare.ets'), 'utf8');
  const js = typescript.transpileModule(source, { compilerOptions: { module: typescript.ModuleKind.CommonJS, target: typescript.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => modules[name] || {}, canIUse: () => true, console });
  const subject = new exports.HarmonyShare({ filesDir: root, cacheDir: root });
  return { subject, listeners };
}

function temporary(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'localsend-native-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}

test('cancelling registration while waiting for a window does not install a listener', async t => {
  const root = temporary(t);
  let resolveWindow;
  const wait = new Promise(resolve => { resolveWindow = resolve; });
  const { subject, listeners } = createSubject(root, { getWindow: () => wait });
  const registering = subject.startReceiving();
  subject.stopReceiving();
  resolveWindow({ getWindowProperties: () => ({ id: 7 }) });
  await registering;
  assert.equal(listeners.length, 0);
});

test('old API does not register PC reception', async t => {
  const { subject, listeners } = createSubject(temporary(t), { api: 18 });
  await subject.startReceiving();
  assert.equal(listeners.length, 0);
});

test('only successful completed receives appear in the persistent list', async t => {
  const root = temporary(t);
  const { subject } = createSubject(root);
  let callbacks, receivedDir;
  await subject.receiveKnock({ receive: async (uri, cb) => { receivedDir = decodeURIComponent(uri.slice(7)); callbacks = cb; } });
  const received = path.join(receivedDir, '中文 file.txt');
  fs.writeFileSync(received, 'complete');
  callbacks.onDataReceived({ getRecords: () => [{ uri: 'file://' + encodeURI(received) }] });
  let listed;
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail });
  assert.equal(listed.length, 0);
  callbacks.onResult(0);
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail });
  assert.equal(listed.length, 1);
  assert.equal(fs.readFileSync(listed[0], 'utf8'), 'complete');
  assert.match(listed[0], /localsend-knock-complete-/);
  assert.equal(subject.pending.length, 1);
  callbacks.onResult(1);
  assert.equal(subject.pending.length, 1);
});

test('a failed receive keeps partial data out of the completed list', async t => {
  const root = temporary(t);
  const { subject } = createSubject(root);
  let callbacks, receivedDir;
  await subject.receiveKnock({ receive: async (uri, cb) => { receivedDir = decodeURIComponent(uri.slice(7)); callbacks = cb; } });
  const received = path.join(receivedDir, 'partial.txt');
  fs.writeFileSync(received, 'partial');
  callbacks.onDataReceived({ getRecords: () => [{ uri: 'file://' + encodeURI(received) }] });
  callbacks.onResult(1);
  let listed;
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail });
  assert.equal(listed.length, 0);
  assert.equal(subject.pending.length, 1);
  assert.equal(subject.pending[0].failed, 1);
});

test('rejects paths outside the receive directory and skips symbolic links', async t => {
  const root = temporary(t);
  const { subject } = createSubject(root);
  let callbacks, receivedDir;
  await subject.receiveKnock({ receive: async (uri, cb) => { receivedDir = decodeURIComponent(uri.slice(7)); callbacks = cb; } });
  const good = path.join(receivedDir, 'good.txt');
  const external = path.join(root, 'outside.txt');
  const link = path.join(receivedDir, 'link.txt');
  fs.writeFileSync(good, 'good');
  fs.writeFileSync(external, 'outside');
  fs.symlinkSync(external, link);
  callbacks.onDataReceived({ getRecords: () => [good, external, link].map(item => ({ uri: 'file://' + encodeURI(item) })) });
  callbacks.onResult(0);
  let listed;
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail });
  assert.equal(listed.length, 1);
  assert.equal(path.basename(listed[0]), 'good.txt');
  assert.equal(subject.pending[0].failed, 2);
});


test('only inactive pending files can be listed or deleted, and completed files are protected', async t => {
  const root = temporary(t);
  const { subject } = createSubject(root);
  let callbacks, receivedDir;
  await subject.receiveKnock({ receive: async (uri, cb) => { receivedDir = decodeURIComponent(uri.slice(7)); callbacks = cb; } });
  const partial = path.join(receivedDir, 'partial.txt');
  const sibling = path.join(receivedDir, 'sibling.txt');
  fs.writeFileSync(partial, 'partial');
  fs.writeFileSync(sibling, 'keep');
  let listed;
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail }, true);
  assert.equal(listed.length, 0);
  let failure;
  const result = { success: () => {}, error: (_code, message) => { failure = message; } };
  subject.deletePendingKnockFile({ argument: () => partial }, result);
  assert.match(failure, /active/);
  callbacks.onResult(1);
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail }, true);
  assert.equal(listed.length, 2);
  const completeDir = fs.mkdtempSync(path.join(root, 'localsend-knock-complete-'));
  const complete = path.join(completeDir, 'keep.txt');
  fs.writeFileSync(complete, 'keep');
  failure = undefined;
  subject.deletePendingKnockFile({ argument: () => complete }, result);
  assert.match(failure, /Invalid/);
  subject.deletePendingKnockFile({ argument: () => partial }, result);
  assert.equal(fs.existsSync(partial), false);
  assert.equal(fs.readFileSync(sibling, 'utf8'), 'keep');
  assert.equal(fs.readFileSync(complete, 'utf8'), 'keep');
});

test('receive rejection releases partial files for recovery without deleting them', async t => {
  const root = temporary(t);
  const { subject } = createSubject(root);
  let partial;
  await subject.receiveKnock({ receive: async (uri, callbacks) => {
    const dir = decodeURIComponent(uri.slice(7));
    partial = path.join(dir, 'interrupted.bin');
    fs.writeFileSync(partial, 'data');
    callbacks.onDataReceived({ getRecords: () => [{ uri: 'file://' + encodeURI(partial) }] });
    throw Error('transfer interrupted');
  } });
  let listed;
  subject.listKnockFiles({ success: value => { listed = value.get('paths'); }, error: assert.fail }, true);
  assert.equal(listed.length, 1);
  assert.equal(listed[0], partial);
  assert.equal(subject.pending.length, 1);
  assert.equal(subject.pending[0].failed, 1);
});


test('failure before data callback retains partially written files', async t => {
  const root = temporary(t);
  const { subject } = createSubject(root);
  let partial;
  await subject.receiveKnock({ receive: async (uri, callbacks) => {
    partial = path.join(decodeURIComponent(uri.slice(7)), 'partial.bin');
    fs.writeFileSync(partial, 'unfinished');
    callbacks.onResult(1);
  } });
  let result;
  subject.listKnockFiles({ success: value => { result = value; }, error: assert.fail }, true);
  assert.deepEqual(Array.from(result.get('paths')), [partial]);
  assert.equal(fs.readFileSync(partial, 'utf8'), 'unfinished');
});


test('unreadable entries are counted while other files remain visible', t => {
  const root = temporary(t);
  const dir = fs.mkdtempSync(path.join(root, 'localsend-knock-pending-'));
  const readable = path.join(dir, 'readable.txt');
  const blocked = path.join(dir, 'blocked.txt');
  fs.writeFileSync(readable, 'ok');
  fs.writeFileSync(blocked, 'no');
  const { subject } = createSubject(root, { lstatSync: p => {
    if (p === blocked) throw Error('denied');
    return fs.lstatSync(p);
  } });
  let result;
  subject.listKnockFiles({ success: value => { result = value; }, error: assert.fail }, true);
  assert.deepEqual(Array.from(result.get('paths')), [readable]);
  assert.equal(result.get('failed'), 1);
});
