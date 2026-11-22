// Exercise our ArkTS control flow with small system API fakes; device behavior remains unverified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const typescript = require('typescript');

function subject(t, settings = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'localsend-pc-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'source');
  const cache = path.join(root, 'cache');
  fs.mkdirSync(source); fs.mkdirSync(cache);
  fs.writeFileSync(path.join(source, 'item.txt'), 'data');
  const listeners = {};
  const trayEvents = {};
  const trayCalls = [];
  const trayPending = [];
  const tray = {
    on: (event, fn) => { trayEvents[event] = fn; },
    off: event => { delete trayEvents[event]; },
    addToStatusBar: (_ctx, item, cb) => { trayCalls.push(item); if (settings.deferTray) trayPending.push(cb); else cb(settings.trayFailure ? Error('unavailable') : undefined); },
    removeFromStatusBar: () => trayCalls.push('removed'),
    isStatusBarCapabilitySupported: async () => true,
  };
  const policies = [];
  const fileShare = {
    OperationMode: { READ_MODE: 1, WRITE_MODE: 2 },
    persistPermission: async p => policies.push(['persist', p[0].uri, p[0].operationMode]),
    activatePermission: async p => policies.push(['activate', p[0].uri, p[0].operationMode]),
    revokePermission: async p => policies.push(['revoke', p[0].uri, p[0].operationMode]),
  };
  let registrations = 0;
  const net = { on: (event, fn) => { listeners[event] = fn; }, register: cb => {
    if (++registrations === 1 && settings.failFirstNetworkRegister) throw Error('registration failed');
    cb();
  }, unregister: cb => cb() };
  const picker = {
    DocumentSelectMode: { FOLDER: 1 }, DocumentSelectOptions: class {},
    DocumentViewPicker: class { async select() { return settings.cancel ? [] : ['source-uri']; } },
  };
  const fileIo = {
    mkdtempSync: fs.mkdtempSync, listFileSync: fs.readdirSync, lstatSync: fs.lstatSync,
    OpenMode: { READ_ONLY: 0, DIR: 0 }, openSync: () => ({ fd: 5, path: source }),
    statSync: () => ({ isDirectory: () => true, isFile: () => true }), closeSync: () => {},
    rmdirSync: p => fs.rmSync(p, { recursive: true, force: true }),
    copy: async (_src, dest) => {
      if (settings.copyError) throw Error('copy failed');
      fs.cpSync(source, path.join(dest, 'folder'), { recursive: true });
    },
  };
  const modules = {
    '@ohos/flutter_ohos': { FlutterAbility: class { onForeground() {} onWindowStageCreate() {} }, FlutterManager: {} },
    '../plugins/GeneratedPluginRegistrant': {},
    '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel': {},
    '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall': {},
    '@kit.BasicServicesKit': { deviceInfo: { deviceType: '2in1', sdkApiVersion: settings.api || 20 } },
    '@kit.CoreFileKit': { picker, fileIo, fileShare, fileUri: { getUriFromPath: p => p } },
    '@kit.NetworkKit': { connection: { createNetConnection: () => net } },
    '@kit.ArkData': {}, '@kit.AbilityKit': { wantConstant: { Flags: { FLAG_AUTH_READ_URI_PERMISSION: 1 } }, autoStartupManager: { getAutoStartupStatusForSelf: async () => true, isAutoStartupSupported: () => true } }, '@kit.NotificationKit': {},
    '@kit.StatusBarExtensionKit': { statusBarManager: tray }, '@kit.ImageKit': { image: { createImageSource: () => ({ createPixelMap: async () => ({}) }) } },
    '@kit.ArkUI': {}, '@kit.BackgroundTasksKit': {}, './HarmonyShare': {},
  };
  const src = fs.readFileSync(path.join(__dirname, '../../app/ohos/entry/src/main/ets/entryability/EntryAbility.ets'), 'utf8');
  const js = typescript.transpileModule(src, { compilerOptions: { module: typescript.ModuleKind.CommonJS, target: typescript.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => modules[name] || {}, canIUse: () => true, console });
  const ability = new exports.default();
  ability.context = { cacheDir: cache, abilityInfo: { bundleName: 'org.localsend' }, resourceManager: { getRawFileContentSync: () => new Uint8Array([1]) }, startAbility: async () => {} };
  return { ability, root, source, cache, listeners, policies, trayEvents, trayCalls, trayPending };
}

test('folder picker imports into isolated cache', async t => {
  const { ability, source, cache } = subject(t);
  let result;
  await ability.pickFolder({ success: value => { result = value; }, error: assert.fail });
  assert.ok(result.startsWith(cache + '/'));
  assert.equal(fs.readFileSync(path.join(result, 'item.txt'), 'utf8'), 'data');
  assert.equal(fs.readFileSync(path.join(source, 'item.txt'), 'utf8'), 'data');
});

test('folder picker cancellation and failure preserve original and clean cache', async t => {
  for (const settings of [{ cancel: true }, { copyError: true }]) {
    const { ability, source, cache } = subject(t, settings);
    let value, failure;
    await ability.pickFolder({ success: v => { value = v; }, error: (code) => { failure = code; } });
    if (settings.cancel) assert.equal(value, null); else assert.equal(failure, 'pick_folder_failed');
    assert.deepEqual(fs.readdirSync(cache), []);
    assert.equal(fs.readFileSync(path.join(source, 'item.txt'), 'utf8'), 'data');
  }
});

test('network observer forwards connectivity and property changes', t => {
  const { ability, listeners } = subject(t);
  const calls = [];
  ability.networkChannel = { invokeMethod: method => calls.push(method) };
  ability.startNetworkObserver({ success: () => {}, error: assert.fail });
  listeners.netAvailable(); listeners.netConnectionPropertiesChange(); listeners.netLost();
  assert.deepEqual(calls, ['changed', 'changed', 'changed']);
});

test('network observer can register again after a synchronous failure', t => {
  const { ability } = subject(t, { failFirstNetworkRegister: true });
  let error;
  ability.startNetworkObserver({ success: assert.fail, error: code => { error = code; } });
  assert.equal(error, 'network_observer');
  let registered = false;
  ability.startNetworkObserver({ success: () => { registered = true; }, error: assert.fail });
  assert.equal(registered, true);
});

test('window close decision minimizes or permits close', async t => {
  const { ability } = subject(t);
  let minimized = 0;
  ability.pcWindow = { minimize: async () => { minimized++; } };
  ability.windowChannel = { invokeMethod: (_method, _args, callbacks) => callbacks.success('minimize') };
  assert.equal(await ability.confirmWindowClose(), true);
  assert.equal(minimized, 1);
  ability.windowChannel = { invokeMethod: (_method, _args, callbacks) => callbacks.success('close') };
  assert.equal(await ability.confirmWindowClose(), false);
});


test('receive folder access persists, activates and revokes the picked URI', async t => {
  const { ability, source, policies } = subject(t);
  let choice, active;
  await ability.chooseReceiveFolder({ success: v => { choice = v; }, error: assert.fail });
  assert.equal(choice.get('uri'), 'source-uri');
  assert.equal(choice.get('path'), source);
  const call = { argument: () => 'source-uri' };
  await ability.activateReceiveFolder(call, { success: v => { active = v; }, error: assert.fail });
  assert.equal(active, source);
  await ability.revokeReceiveFolder(call, { success: () => {}, error: assert.fail });
  assert.deepEqual(policies, [['persist', 'source-uri', 3], ['activate', 'source-uri', 3], ['revoke', 'source-uri', 3]]);
});


test('opening a file sends a read-only view request and reports failures', async t => {
  const { ability } = subject(t);
  let want, success = false, failure;
  ability.context.startAbility = async value => { want = value; };
  const call = { argument: () => '/sandbox/report.pdf' };
  await ability.openFile(call, { success: () => { success = true; }, error: assert.fail });
  assert.equal(success, true);
  assert.equal(want.uri, '/sandbox/report.pdf');
  assert.equal(want.action, 'ohos.want.action.viewData');
  assert.equal(want.flags, 1);
  ability.context.startAbility = async () => { throw Error('no application'); };
  await ability.openFile(call, { success: assert.fail, error: code => { failure = code; } });
  assert.equal(failure, 'open_file_failed');
});

test('topmost state is applied or returns a platform error', async t => {
  const { ability } = subject(t);
  let value, failure;
  ability.pcWindow = { setWindowTopmost: async v => { value = v; } };
  await ability.setTopmost({ argument: () => true }, { success: () => {}, error: assert.fail });
  assert.equal(value, true);
  ability.pcWindow.setWindowTopmost = async () => { throw Error('unsupported mode'); };
  await ability.setTopmost({ argument: () => true }, { success: assert.fail, error: code => { failure = code; } });
  assert.equal(failure, 'window_topmost_failed');
});


function setTray(ability, enabled) {
  return new Promise((resolve, reject) => {
    ability.setTray({ argument: () => enabled }, { success: resolve, error: (code, message) => reject(Error(code + ': ' + message)) });
  });
}

test('tray registration gates close minimization and can be disabled', async t => {
  const { ability, trayEvents, trayCalls } = subject(t);
  let minimized = 0, restored = 0;
  ability.pcWindow = { minimize: async () => { minimized++; }, restore: async () => { restored++; } };
  ability.isForeground = false;
  await setTray(ability, true);
  ability.windowChannel = { invokeMethod: (_method, args, callbacks) => {
    assert.equal(args.get('trayEnabled'), true);
    callbacks.success('minimize');
  } };
  assert.equal(await ability.confirmWindowClose(), true);
  assert.equal(minimized, 1);
  trayEvents.statusBarIconClick({});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(restored, 0);
  ability.onForeground();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(restored, 1);
  await setTray(ability, false);
  assert.equal(trayEvents.statusBarIconClick, undefined);
  assert.equal(trayCalls.at(-1), 'removed');
});

test('failed tray registration does not intercept window closing', async t => {
  const { ability, trayEvents } = subject(t, { trayFailure: true });
  await assert.rejects(setTray(ability, true), /tray_failed/);
  assert.equal(trayEvents.statusBarIconClick, undefined);
  assert.equal(await ability.confirmWindowClose(), false);
});

test('startup status is queried only on supported API versions', async t => {
  for (const [api, expected] of [[20, false], [21, true]]) {
    const { ability } = subject(t, { api });
    let result;
    await ability.autoStartupStatus({ success: value => { result = value; }, error: assert.fail });
    assert.equal(result.get('supported'), expected);
    if (expected) assert.equal(result.get('enabled'), true);
  }
});


test('rapid tray enable and disable leaves the icon disabled', async t => {
  const { ability, trayPending, trayCalls, trayEvents } = subject(t, { deferTray: true });
  const enable = setTray(ability, true);
  const disable = setTray(ability, false);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(trayPending.length, 1);
  trayPending[0]();
  await Promise.all([enable, disable]);
  assert.equal(ability.trayEnabled, false);
  assert.equal(trayCalls.at(-1), 'removed');
  assert.equal(trayEvents.statusBarIconClick, undefined);
});

test('tray restore waits for the main window to be created', async t => {
  const { ability } = subject(t);
  let restored = 0;
  ability.trayRestoreRequested = true;
  ability.onForeground();
  assert.equal(ability.trayRestoreRequested, true);
  const window = { on: () => {}, restore: async () => { restored++; } };
  ability.onWindowStageCreate({ getMainWindowSync: () => window });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(restored, 1);
  assert.equal(ability.trayRestoreRequested, false);
});

test('a pending tray registration is removed when the engine is gone', async t => {
  const { ability, trayPending, trayCalls, trayEvents } = subject(t, { deferTray: true });
  const enable = setTray(ability, true);
  await new Promise(resolve => setImmediate(resolve));
  // An old engine was torn down and a replacement started before the callback.
  ability.trayEngineReady = true;
  ability.trayGeneration++;
  trayPending[0]();
  await assert.rejects(enable, /tray_failed/);
  assert.equal(ability.trayEnabled, false);
  assert.equal(trayCalls.at(-1), 'removed');
  assert.equal(trayEvents.statusBarIconClick, undefined);
});
