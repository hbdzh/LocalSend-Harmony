import { common, Want } from '@kit.AbilityKit';
import { systemShare, harmonyShare } from '@kit.ShareKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';

class ShareBatch {
  paths: Array<string> = [];
  texts: Array<string> = [];
  failed: number = 0;
  kind: string = 'share';
}

/** Buffers shares until Flutter is ready, then asks Dart to acknowledge them. */
export class HarmonyShare {
  private context: common.UIAbilityContext;
  private channel: MethodChannel | undefined;
  private ready: boolean = false;
  private delivering: boolean = false;
  private pending: Array<ShareBatch> = [];
  private receivingGeneration: number = 0;
  private activeKnockDirectories: Set<string> = new Set<string>();
  private receiveRegistry: harmonyShare.RecvCapabilityRegistry | undefined;
  private receiveCallback = (target: harmonyShare.ReceivableTarget): void => {
    this.receiveKnock(target);
  };
  private knockData: systemShare.SharedData | undefined;
  private knockWindow: number | undefined;
  private knockCallback = (target: harmonyShare.SharableTarget): void => {
    const data = this.knockData;
    if (!data) return;
    this.disarm();
    target.share(data).catch((error: Error) => console.error('Harmony knock share failed: ' + String(error)));
  };

  constructor(context: common.UIAbilityContext) { this.context = context; }

  attach(engine: FlutterEngine): void {
    this.channel = new MethodChannel(engine.getDartExecutor(), 'org.localsend.localsend_app/harmony_share');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'ready') {
        this.ready = true;
        result.success(null);
        this.flush();
      } else if (call.method === 'listKnockFiles') {
        this.listKnockFiles(result, false);
      } else if (call.method === 'listPendingKnockFiles') {
        this.listKnockFiles(result, true);
      } else if (call.method === 'deletePendingKnockFile') {
        this.deletePendingKnockFile(call, result);
      } else if (call.method === 'shareSelection' || call.method === 'armKnock') {
        this.shareSelection(call, result);
      } else if (call.method === 'disarmKnock') {
        this.disarm();
        result.success(null);
      } else if (call.method === 'shareFile') {
        this.showFile(call, result);
      } else {
        result.notImplemented();
      }
    }});
  }

  async startReceiving(): Promise<void> {
    if (deviceInfo.deviceType !== '2in1' || deviceInfo.sdkApiVersion < 20 || this.receiveRegistry ||
        !canIUse('SystemCapability.Collaboration.HarmonyShare')) return;
    const generation = ++this.receivingGeneration;
    try {
      const mainWindow = await window.getLastWindow(this.context);
      if (generation !== this.receivingGeneration || this.receiveRegistry) return;
      const registry: harmonyShare.RecvCapabilityRegistry = {
        windowId: mainWindow.getWindowProperties().id,
        capabilities: [{ utd: uniformTypeDescriptor.UniformDataType.FILE, maxSupportedCount: 500 }]
      };
      harmonyShare.on('dataReceive', registry, this.receiveCallback);
      this.receiveRegistry = registry;
    } catch (error) {
      console.error('Cannot register Harmony tap receive: ' + String(error));
    }
  }

  stopReceiving(): void {
    ++this.receivingGeneration;
    const registry = this.receiveRegistry;
    this.receiveRegistry = undefined;
    if (!registry) return;
    try { harmonyShare.off('dataReceive', registry, this.receiveCallback); }
    catch (error) { console.error('Cannot unregister Harmony tap receive: ' + String(error)); }
  }

  private listKnockFiles(result: MethodResult, pending: boolean = false): void {
    try {
      const paths: Array<string> = [];
      let failed = 0;
      for (const directory of fs.listFileSync(this.context.filesDir)) {
        const prefix = pending ? 'localsend-knock-pending-' : 'localsend-knock-complete-';
        if (!directory.startsWith(prefix) || directory.includes('/')) continue;
        const root = this.context.filesDir + '/' + directory;
        if (pending && this.activeKnockDirectories.has(root)) continue;
        try {
          const rootInfo = fs.lstatSync(root);
          if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) continue;
          for (const name of fs.listFileSync(root)) {
            if (!name || name === '.' || name === '..' || name.includes('/')) continue;
            const path = root + '/' + name;
            try {
              const info = fs.lstatSync(path);
              if (info.isFile() && !info.isSymbolicLink()) paths.push(path);
            } catch (error) {
              failed++;
              console.error('Cannot inspect tap file: ' + String(error));
            }
          }
        } catch (error) {
          failed++;
          console.error('Cannot inspect tap directory: ' + String(error));
        }
      }
      const response = new Map<string, Object>();
      response.set('paths', paths);
      response.set('failed', failed);
      result.success(response);
    } catch (error) {
      result.error('list_knock_failed', String(error), null);
    }
  }

  private deletePendingKnockFile(call: MethodCall, result: MethodResult): void {
    try {
      const path = call.argument('path') as string;
      const prefix = this.context.filesDir + '/localsend-knock-pending-';
      if (!path || !path.startsWith(prefix)) throw new Error('Invalid pending file path');
      const rest = path.substring(this.context.filesDir.length + 1).split('/');
      if (rest.length !== 2 || rest[0] === 'localsend-knock-pending-' || !rest[1] ||
          rest[1] === '.' || rest[1] === '..' || rest[1].includes('\\')) throw new Error('Invalid pending file path');
      const root = this.context.filesDir + '/' + rest[0];
      if (this.activeKnockDirectories.has(root)) throw new Error('Receive is still active');
      const rootInfo = fs.lstatSync(root);
      const info = fs.lstatSync(path);
      if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink() || !info.isFile() || info.isSymbolicLink()) {
        throw new Error('Invalid pending file');
      }
      fs.unlinkSync(path);
      result.success(null);
    } catch (error) {
      result.error('delete_pending_failed', String(error), null);
    }
  }

  private async receiveKnock(target: harmonyShare.ReceivableTarget): Promise<void> {
    let directory = '';
    let finished = false;
    let dataReceived = false;
    const batch = new ShareBatch();
    batch.kind = 'knock';
    const reportFailure = (): void => {
      const failure = new ShareBatch();
      failure.kind = 'knock';
      failure.failed = 1;
      this.pending.push(failure);
      this.flush();
    };
    try {
      directory = fs.mkdtempSync(this.context.filesDir + '/localsend-knock-pending-XXXXXX');
      const destination = directory;
      this.activeKnockDirectories.add(destination);
      await target.receive(fileUri.getUriFromPath(destination), {
        onDataReceived: (data: systemShare.SharedData): void => {
          if (finished) return;
          dataReceived = true;
          for (const record of data.getRecords()) {
            try {
              if (!record.uri) throw new Error('Missing file URI');
              const path: string = new fileUri.FileUri(record.uri).path;
              if (!path.startsWith(destination + '/')) throw new Error('Outside receive directory');
              const name = path.substring(destination.length + 1);
              const info = fs.lstatSync(path);
              if (!name || name.includes('/') || name === '.' || name === '..' ||
                  !info.isFile() || info.isSymbolicLink()) throw new Error('Invalid received file');
              if (!batch.paths.includes(path)) batch.paths.push(path);
            } catch (_) { batch.failed++; }
          }
        },
        onResult: (code: harmonyShare.ShareResultCode): void => {
          if (finished) return;
          finished = true;
          this.activeKnockDirectories.delete(destination);
          if (code !== harmonyShare.ShareResultCode.SHARE_SUCCESS || !dataReceived || batch.paths.length === 0) {
            reportFailure();
            return;
          }
          try {
            // Make completed batches visible only after the system reports success.
            // Incomplete data remains in its pending directory for diagnosis/recovery.
            const complete = destination.replace('localsend-knock-pending-', 'localsend-knock-complete-');
            fs.renameSync(destination, complete);
            batch.paths = batch.paths.map((path: string): string => complete + path.substring(destination.length));
            this.pending.push(batch);
            this.flush();
          } catch (error) {
            console.error('Cannot finalize Harmony tap receive: ' + String(error));
            reportFailure();
          }
        }
      });
    } catch (error) {
      if (finished) return;
      finished = true;
      if (directory) this.activeKnockDirectories.delete(directory);
      reportFailure();
      console.error('Harmony tap receive failed: ' + String(error));
    }
  }

  private async shareSelection(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const paths = call.argument('paths') as Array<string>;
      const texts = call.argument('texts') as Array<string>;
      if (paths.length + texts.length === 0 || paths.length + texts.length > 500) throw new Error('Invalid share selection');
      const records: Array<systemShare.SharedRecord> = [];
      for (const path of paths) {
        if (!fs.statSync(path).isFile()) throw new Error('File unavailable: ' + path);
        const name = path.substring(path.lastIndexOf('/') + 1);
        const dot = name.lastIndexOf('.');
        let type = uniformTypeDescriptor.UniformDataType.FILE as string;
        if (dot >= 0) {
          try { type = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(name.substring(dot), type) || type; } catch (_) {}
        }
        records.push({ utd: type, uri: fileUri.getUriFromPath(path), title: name });
      }
      for (const content of texts) records.push({ utd: 'general.plain-text', content: content });
      const data = new systemShare.SharedData(records[0]);
      for (let i = 1; i < records.length; i++) data.addRecord(records[i]);
      if (call.method === 'shareSelection') {
        await new systemShare.ShareController(data).show(this.context, {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: systemShare.SharePreviewMode.DEFAULT,
        });
      } else {
        if (!canIUse('SystemCapability.Collaboration.HarmonyShare')) throw new Error('Huawei Share unavailable');
        this.disarm();
        this.knockData = data;
        try {
          if (deviceInfo.deviceType === '2in1') {
            const mainWindow = await window.getLastWindow(this.context);
            if (this.knockData !== data) throw new Error('Tap sharing was cancelled');
            this.knockWindow = mainWindow.getWindowProperties().id;
            harmonyShare.on('knockShare', { windowId: this.knockWindow }, this.knockCallback);
          } else {
            harmonyShare.on('knockShare', this.knockCallback);
          }
        } catch (error) {
          if (this.knockData === data) {
            this.knockData = undefined;
            this.knockWindow = undefined;
          }
          throw new Error(String(error));
        }
      }
      result.success(null);
    } catch (error) {
      result.error('share_failed', String(error), null);
    }
  }

  disarm(): void {
    if (!this.knockData) return;
    try {
      if (this.knockWindow !== undefined) harmonyShare.off('knockShare', { windowId: this.knockWindow }, this.knockCallback);
      else harmonyShare.off('knockShare', this.knockCallback);
    } catch (error) { console.error('Harmony knock unregister failed: ' + String(error)); }
    this.knockData = undefined;
    this.knockWindow = undefined;
  }

  private async showFile(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const path = call.argument('path') as string;
      if (!path || !fs.statSync(path).isFile()) throw new Error('File unavailable');
      const name = path.substring(path.lastIndexOf('/') + 1);
      const dot = name.lastIndexOf('.');
      const extension = dot >= 0 ? name.substring(dot) : '';
      let type = uniformTypeDescriptor.UniformDataType.FILE as string;
      if (extension) {
        try { type = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(extension, type) || type; } catch (_) {}
      }
      const data = new systemShare.SharedData({ utd: type, uri: fileUri.getUriFromPath(path), title: name });
      await new systemShare.ShareController(data).show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
      });
      result.success(null);
    } catch (error) {
      result.error('share_failed', String(error), null);
    }
  }

  detach(): void {
    this.stopReceiving();
    this.disarm();
    this.ready = false;
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
  }

  accept(want: Want): void {
    if (want.action !== 'ohos.want.action.sendData') return;
    this.read(want);
  }

  private async read(want: Want): Promise<void> {
    const batch = new ShareBatch();
    try {
      const records = (await systemShare.getSharedData(want)).getRecords();
      for (const record of records) {
        if (record.uri) {
          let source: fs.File | undefined;
          let dir: string = '';
          let target: string = '';
          try {
            if (!record.uri.startsWith('file://')) throw new Error('Unsupported URI');
            source = fs.openSync(record.uri, fs.OpenMode.READ_ONLY);
            if (!fs.statSync(source.fd).isFile()) throw new Error('Not a file');
            const name = source.name.replaceAll('/', '_').replaceAll('\\', '_');
            if (!name || name === '.' || name === '..') throw new Error('Invalid name');
            dir = fs.mkdtempSync(this.context.cacheDir + '/localsend-share-XXXXXX');
            target = dir + '/' + name;
            await fs.copyFile(source.fd, target);
            batch.paths.push(target);
          } catch (_) {
            batch.failed++;
            if (target) { try { fs.unlinkSync(target); } catch (_) {} }
            if (dir) { try { fs.rmdirSync(dir); } catch (_) {} }
          } finally {
            if (source) { try { fs.closeSync(source); } catch (_) {} }
          }
        } else if (record.content) {
          batch.texts.push(record.content);
        } else {
          batch.failed++;
        }
      }
    } catch (_) {
      batch.failed++;
    }
    this.pending.push(batch);
    this.flush();
  }

  private flush(): void {
    const channel = this.channel;
    if (!this.ready || this.delivering || !channel || this.pending.length === 0) return;
    this.delivering = true;
    const batch = this.pending[0];
    const payload = new Map<string, Object>();
    payload.set('kind', batch.kind);
    payload.set('paths', batch.paths);
    payload.set('texts', batch.texts);
    payload.set('failed', batch.failed);
    channel.invokeMethod('received', payload, {
      success: (accepted: ESObject): void => {
        this.delivering = false;
        if (accepted === true) { this.pending.shift(); this.flush(); }
        else { this.ready = false; }
      },
      error: (): void => { this.delivering = false; this.ready = false; },
      notImplemented: (): void => { this.delivering = false; this.ready = false; },
    });
  }
}
