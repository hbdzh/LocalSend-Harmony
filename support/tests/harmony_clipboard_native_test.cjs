const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const typescript = require('typescript');

function subject(t, { pixel, text, fail = false, uris = [], copyFails = [], recordFails = [] } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'localsend-clipboard-'));
  const store = path.join(root, 'localsend-clipboard-imports');
  fs.mkdirSync(store);
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  let released = 0;
  let pixelReleased = 0;
  const modules = {
    '@kit.BasicServicesKit': { pasteboard: { MIMETYPE_TEXT_URI: 'text/uri', getSystemPasteboard: () => ({
      getData: async () => ({
        getRecordCount: () => uris.length,
        getRecord: i => {
          if (recordFails.includes(i)) throw Error('record unavailable');
          return { getValidTypes: () => ['text/uri'], getData: async () => uris[i] };
        },
        getPrimaryPixelMap: () => pixel ? { release: async () => { pixelReleased++; } } : undefined,
        getPrimaryText: () => text,
      }),
    }) } },
    '@kit.CoreFileKit': { fileIo: {
      mkdtempSync: fs.mkdtempSync, unlinkSync: fs.unlinkSync, closeSync: value => fs.closeSync(typeof value === 'number' ? value : value.fd),
      statSync: fs.fstatSync, lstatSync: fs.lstatSync, listFileSync: fs.readdirSync,
      rmdirSync: dir => fs.rmSync(dir, { recursive: true, force: true }),
      OpenMode: { CREATE: 1, READ_WRITE: 2, READ_ONLY: 4 },
      openSync: file => file.startsWith('file://') ? ({ fd: fs.openSync(file.slice(7), 'r') }) : ({ fd: fs.openSync(file, 'w+') }),
      copy: async (source, dest) => {
        fs.cpSync(source.slice(7), path.join(dest.slice(7), path.basename(source)), { recursive: true });
        if (copyFails.includes(path.basename(source))) throw Error('copy failed');
      },
    }, fileUri: { getUriFromPath: value => 'file://' + value } },
    '@kit.ImageKit': { image: { createImagePacker: () => ({
      packToFile: async (_pixel, fd) => { fs.writeSync(fd, Buffer.from('png')); if (fail) throw Error('encode failed'); },
      release: async () => { released++; },
    }) } },
  };
  const source = fs.readFileSync(path.join(__dirname, '../../app/ohos/entry/src/main/ets/entryability/HarmonyClipboardData.ets'), 'utf8');
  const js = typescript.transpileModule(source, { compilerOptions: { module: typescript.ModuleKind.CommonJS, target: typescript.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => modules[name], console, Map });
  return { root, store, read: () => exports.readAuthorizedClipboard(root), discard: data => exports.discardClipboardCopies(data), released: () => released, pixelReleased: () => pixelReleased };
}

test('prefers an image, saves it in private cache and releases the encoder', async t => {
  const clip = subject(t, { pixel: {}, text: 'alternative text' });
  const result = await clip.read();
  assert.ok(result.get('path').startsWith(clip.root + '/'));
  assert.equal(fs.readFileSync(result.get('path'), 'utf8'), 'png');
  assert.equal(clip.released(), 1);
  assert.equal(clip.pixelReleased(), 1);
});

test('imports folder URIs including nested and empty folders alongside files', async t => {
  const uris = [];
  const clip = subject(t, { uris, copyFails: ['bad-folder'], recordFails: [2] });
  const folder = path.join(clip.root, 'folder');
  fs.mkdirSync(path.join(folder, 'nested', 'empty'), { recursive: true });
  fs.writeFileSync(path.join(folder, 'nested', 'file.txt'), 'contents');
  fs.mkdirSync(path.join(clip.root, 'bad-folder'));
  fs.writeFileSync(path.join(clip.root, 'separate.txt'), 'separate');
  uris.push(...[folder, path.join(clip.root, 'bad-folder'), folder, path.join(clip.root, 'separate.txt')].map(p => 'file://' + p));
  const result = await clip.read();
  assert.equal(result.get('failed'), 2);
  const [imported] = result.get('directories');
  assert.equal(fs.readFileSync(path.join(imported, 'nested', 'file.txt'), 'utf8'), 'contents');
  assert.deepEqual(fs.readdirSync(path.join(imported, 'nested', 'empty')), []);
  assert.equal(fs.readFileSync(result.get('paths')[0], 'utf8'), 'separate');
  assert.ok(fs.existsSync(path.join(folder, 'nested', 'file.txt')));
  assert.equal(fs.readdirSync(clip.store).filter(name => name.startsWith('localsend-clipboard-file-')).length, 2);
  clip.discard(result);
  assert.equal(fs.readdirSync(clip.store).filter(name => name.startsWith('localsend-clipboard-file-')).length, 0);
  assert.ok(fs.existsSync(path.join(folder, 'nested', 'file.txt')));
});

test('returns text and removes a failed image output', async t => {
  const text = subject(t, { text: 'hello' });
  assert.equal((await text.read()).get('text'), 'hello');
  const image = subject(t, { pixel: {}, fail: true });
  await assert.rejects(image.read(), /encode failed/);
  const dir = path.join(image.store, fs.readdirSync(image.store)[0]);
  assert.deepEqual(fs.readdirSync(dir), []);
  assert.equal(image.released(), 1);
  assert.equal(image.pixelReleased(), 1);
});

test('imports multiple file URIs without name collisions and reports failed entries', async t => {
  const uris = [];
  const clip = subject(t, { uris, pixel: {}, copyFails: ['bad.txt'] });
  const a = path.join(clip.root, 'a');
  const b = path.join(clip.root, 'b');
  fs.mkdirSync(a); fs.mkdirSync(b);
  fs.writeFileSync(path.join(a, 'same.txt'), 'first');
  fs.writeFileSync(path.join(b, 'same.txt'), 'second');
  fs.writeFileSync(path.join(a, 'bad.txt'), 'source');
  uris.push('file://' + path.join(a, 'same.txt'), 'file://' + path.join(b, 'same.txt'), 'file://' + path.join(a, 'bad.txt'));
  const result = await clip.read();
  assert.equal(result.get('failed'), 1);
  const files = result.get('paths');
  assert.equal(files.length, 2);
  assert.notEqual(files[0], files[1]);
  assert.deepEqual(Array.from(files, file => fs.readFileSync(file, 'utf8')), ['first', 'second']);
  assert.equal(fs.readFileSync(path.join(a, 'same.txt'), 'utf8'), 'first');
  assert.equal(fs.readFileSync(path.join(a, 'bad.txt'), 'utf8'), 'source');
  assert.equal(fs.readdirSync(clip.store).filter(name => name.startsWith('localsend-clipboard-file-')).length, 2);
  assert.equal(clip.pixelReleased(), 0);
});
