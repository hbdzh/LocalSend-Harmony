
import { FlutterAbility, FlutterEngine, FlutterManager } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import MethodChannel, { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { deviceInfo, emitter } from '@kit.BasicServicesKit';
import { picker, fileIo as fs, fileUri, fileShare } from '@kit.CoreFileKit';
import { unifiedDataChannel, uniformDataStruct } from '@kit.ArkData';
import { AbilityConstant, Want, wantAgent, wantConstant, bundleManager, autoStartupManager } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { window } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { statusBarManager } from '@kit.StatusBarExtensionKit';
import { image } from '@kit.ImageKit';
import { connection } from '@kit.NetworkKit';
import { HarmonyShare } from './HarmonyShare';
import { HarmonyClipboard } from './HarmonyClipboard';

class DroppedFile {
  source: fs.File;
  target: string;
  directory: string;

  constructor(source: fs.File, target: string, directory: string) {
    this.source = source;
    this.target = target;
    this.directory = directory;
  }
}

export default class EntryAbility extends FlutterAbility {
  private dragEnterId: number = 0;
  private dragLeaveId: number = 0;
  private dropId: number = 0;
  private dropChannel: MethodChannel | undefined;
  private share: HarmonyShare | undefined;
  private clipboard: HarmonyClipboard | undefined;
  private transferNotificationId: number | undefined;
  private transferTaskId: number | undefined;
  private backgroundChannel: MethodChannel | undefined;
  private stoppingTransferTask: boolean = false;
  private backgroundCancelled = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (this.stoppingTransferTask || this.transferNotificationId === undefined ||
        (this.transferTaskId !== undefined && this.transferTaskId !== info.id)) return;
    this.transferNotificationId = undefined;
    this.transferTaskId = undefined;
    this.backgroundChannel?.invokeMethod('cancelled', null);
  };
  private isForeground: boolean = false;
  private trayEnabled: boolean = false;
  private trayEngineReady: boolean = true;
  private trayGeneration: number = 0;
  private trayOperation: Promise<void> = Promise.resolve();
  private trayRestoreRequested: boolean = false;
  private trayIconClick = (_event: emitter.EventData): void => {
    this.trayRestoreRequested = true;
    const want: Want = { bundleName: this.context.abilityInfo.bundleName, abilityName: 'EntryAbility' };
    this.context.startAbility(want).then((): void => {
      if (this.isForeground) this.restoreTrayWindow();
    }).catch((error: Error): void => {
      this.trayRestoreRequested = false;
      console.error('Cannot open window: ' + String(error));
    });
  };

  private restoreTrayWindow(): void {
    if (!this.trayRestoreRequested || !this.pcWindow || !this.isForeground) return;
    this.trayRestoreRequested = false;
    this.pcWindow.restore().catch((error: Error): void => console.error('Cannot restore window: ' + String(error)));
  }
  private windowChannel: MethodChannel | undefined;
  private pcWindow: window.Window | undefined;
  private network: connection.NetConnection | undefined;
  private networkChannel: MethodChannel | undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    if (!this.share) this.share = new HarmonyShare(this.context);
    this.share.accept(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    this.share?.accept(want);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    this.trayEngineReady = true;
    this.trayGeneration++;
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    if (!this.share) this.share = new HarmonyShare(this.context);
    this.share.attach(flutterEngine);
    this.clipboard = new HarmonyClipboard(this.context);
    const clipboardChannel = new MethodChannel(flutterEngine.getDartExecutor(), 'org.localsend.localsend_app/harmony_clipboard');
    clipboardChannel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'read') this.clipboard?.open(call.argument('chinese') === true, result);
      else result.notImplemented();
    }});
    const background = new MethodChannel(flutterEngine.getDartExecutor(), 'org.localsend.localsend_app/harmony_background');
    this.backgroundChannel = background;
    if (deviceInfo.sdkApiVersion >= 15) {
      try { backgroundTaskManager.on('continuousTaskCancel', this.backgroundCancelled); }
      catch (error) { console.error('Cannot observe background task cancellation: ' + String(error)); }
    }
    background.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'start' || call.method === 'stop' || call.method === 'progress') this.backgroundTask(call, result);
      else result.notImplemented();
    }});
    this.windowChannel = new MethodChannel(flutterEngine.getDartExecutor(), 'org.localsend.localsend_app/harmony_window');
    this.windowChannel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'setTopmost') this.setTopmost(call, result);
      else if (call.method === 'setTray') this.setTray(call, result);
      else if (call.method === 'autoStartupStatus') this.autoStartupStatus(result);
      else result.notImplemented();
    }});
    this.networkChannel = new MethodChannel(flutterEngine.getDartExecutor(), 'org.localsend.localsend_app/harmony_network');
    this.networkChannel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'start') this.startNetworkObserver(result);
      else result.notImplemented();
    }});
    const channel = new MethodChannel(flutterEngine.getDartExecutor(), 'org.localsend.localsend_app/harmony_device');
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'deviceType') {
          result.success(deviceInfo.deviceType);
        } else if (call.method === 'deviceModel') {
          result.success(deviceInfo.marketName || deviceInfo.productModel || 'HarmonyOS');
        } else if (call.method === 'appVersion') {
          this.getAppVersion(result);
        } else if (call.method === 'chooseReceiveFolder') {
          this.chooseReceiveFolder(result);
        } else if (call.method === 'activateReceiveFolder') {
          this.activateReceiveFolder(call, result);
        } else if (call.method === 'revokeReceiveFolder') {
          this.revokeReceiveFolder(call, result);
        } else if (call.method === 'chooseExportFolder') {
          this.chooseExportFolder(result);
        } else if (call.method === 'pickFolder') {
          this.pickFolder(result);
        } else if (call.method === 'openFile') {
          this.openFile(call, result);
        } else if (call.method === 'exportFile') {
          this.exportFile(call, result);
        } else if (call.method === 'requestNotifications') {
          this.requestNotifications(result);
        } else if (call.method === 'notifyIncoming') {
          this.notifyIncoming(call, result);
        } else {
          result.notImplemented();
        }
      }
    });
    if (deviceInfo.deviceType === '2in1') {
      this.dropChannel = new MethodChannel(flutterEngine.getDartExecutor(), 'org.localsend.localsend_app/harmony_drop');
      const manager = FlutterManager.getInstance();
      this.dragEnterId = manager.addDragEnterCb({ do: (_event: DragEvent, _extra: string): void => {
        this.dropChannel?.invokeMethod('entered', null);
      }});
      this.dragLeaveId = manager.addDragLeaveCb({ do: (_event: DragEvent, _extra: string): void => {
        this.dropChannel?.invokeMethod('exited', null);
      }});
      this.dropId = manager.addDropCb({ do: (event: DragEvent, _extra: string): void => {
        if (this.containsFolder(event)) {
          this.loadFolderDrop(event);
        } else {
          this.handleDrop(event);
        }
      }});
    }
  }

  private startNetworkObserver(result: MethodResult): void {
    if (this.network) { result.success(null); return; }
    try {
      const net = connection.createNetConnection();
      const changed = (): void => { this.networkChannel?.invokeMethod('changed', null); };
      net.on('netAvailable', changed);
      net.on('netLost', changed);
      net.on('netConnectionPropertiesChange', changed);
      this.network = net;
      net.register((error): void => {
        if (error) {
          this.network = undefined;
          result.error('network_observer', String(error), null);
        } else result.success(null);
      });
    } catch (error) {
      this.network = undefined;
      result.error('network_observer', String(error), null);
    }
  }

  private receiveFolderPolicy(uri: string): fileShare.PolicyInfo {
    return { uri: uri, operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE };
  }

  private receiveFolderPath(uri: string): string {
    const folder = fs.openSync(uri, fs.OpenMode.READ_ONLY | fs.OpenMode.DIR);
    try {
      if (!fs.statSync(folder.fd).isDirectory() || !folder.path) throw new Error('Selected location is not a directory');
      return folder.path;
    } finally { fs.closeSync(folder); }
  }

  private async chooseReceiveFolder(result: MethodResult): Promise<void> {
    try {
      if (deviceInfo.deviceType !== '2in1' || !canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
        throw new Error('Persistent folder access is unavailable');
      }
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      if (!uris || uris.length === 0) { result.success(null); return; }
      const uri = uris[0];
      await fileShare.persistPermission([this.receiveFolderPolicy(uri)]);
      const response = new Map<string, Object>();
      response.set('uri', uri);
      response.set('path', this.receiveFolderPath(uri));
      result.success(response);
    } catch (error) { result.error('receive_folder_failed', String(error), null); }
  }

  private async activateReceiveFolder(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const uri = call.argument('uri') as string;
      if (!uri) throw new Error('Missing directory URI');
      await fileShare.activatePermission([this.receiveFolderPolicy(uri)]);
      result.success(this.receiveFolderPath(uri));
    } catch (error) { result.error('receive_folder_failed', String(error), null); }
  }

  private async revokeReceiveFolder(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const uri = call.argument('uri') as string;
      await fileShare.revokePermission([this.receiveFolderPolicy(uri)]);
      result.success(null);
    } catch (error) { result.error('receive_folder_failed', String(error), null); }
  }

  private async chooseExportFolder(result: MethodResult): Promise<void> {
    try {
      if (deviceInfo.deviceType !== '2in1') throw new Error('Folder selection is available on PC only');
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      result.success(uris && uris.length > 0 ? uris[0] : null);
    } catch (error) {
      result.error('pick_export_folder_failed', String(error), null);
    }
  }

  private async pickFolder(result: MethodResult): Promise<void> {
    let root = '';
    try {
      if (deviceInfo.deviceType !== '2in1') throw new Error('Folder selection is available on PC only');
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      if (!uris || uris.length === 0) { result.success(null); return; }
      root = fs.mkdtempSync(this.context.cacheDir + '/localsend-folder-XXXXXX');
      await fs.copy(uris[0], fileUri.getUriFromPath(root));
      const entries = fs.listFileSync(root);
      if (entries.length !== 1 || !fs.lstatSync(root + '/' + entries[0]).isDirectory()) {
        throw new Error('Could not import selected folder');
      }
      result.success(root + '/' + entries[0]);
    } catch (error) {
      if (root) { try { fs.rmdirSync(root); } catch (_) {} }
      result.error('pick_folder_failed', String(error), null);
    }
  }

  private async backgroundTask(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (call.method === 'start') {
        if (this.transferNotificationId !== undefined) { result.success(null); return; }
        const agent = await wantAgent.getWantAgent({
          wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: 'EntryAbility' }],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 4102,
          actionFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG],
        });
        const task = await backgroundTaskManager.startBackgroundRunning(this.context, ['dataTransfer'], agent);
        this.transferNotificationId = task.notificationId;
        this.transferTaskId = task.continuousTaskId;
      } else if (call.method === 'stop') {
        if (this.transferNotificationId !== undefined) {
          this.stoppingTransferTask = true;
          try {
            await backgroundTaskManager.stopBackgroundRunning(this.context);
            this.transferNotificationId = undefined;
            this.transferTaskId = undefined;
          } finally {
            this.stoppingTransferTask = false;
          }
        }
      } else if (this.transferNotificationId !== undefined) {
        const title = call.argument('title') as string;
        const text = call.argument('text') as string;
        const progress = call.argument('progress') as number;
        const template: notificationManager.NotificationTemplate = {
          name: 'downloadTemplate', data: { title: title, fileName: text, progressValue: progress }
        };
        const request: notificationManager.NotificationRequest = {
          id: this.transferNotificationId,
          notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
          content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
            systemLiveView: { typeCode: 8, title: title, text: text } },
          template: template
        };
        await notificationManager.publish(request);
      } else {
        throw new Error('Background task is not running');
      }
      result.success(null);
    } catch (error) {
      // A task can be cancelled by the system. Only clear our id after the system
      // confirms it no longer exists; transient query failures retain the id.
      if (this.transferNotificationId !== undefined && deviceInfo.sdkApiVersion >= 20 &&
          (call.method === 'stop' || call.method === 'progress')) {
        try {
          const tasks = await backgroundTaskManager.getAllContinuousTasks(this.context);
          const id = this.transferNotificationId;
          if (!tasks.some((task: backgroundTaskManager.ContinuousTaskInfo): boolean => task.notificationId === id)) {
            this.transferNotificationId = undefined;
            this.transferTaskId = undefined;
            if (call.method === 'stop') result.success(null);
            else result.error('background_task_missing', 'Background task ended by system', null);
            return;
          }
        } catch (_) { /* Keep the id until the task state is known. */ }
      }
      result.error('background_task_failed', String(error), null);
    }
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    super.onWindowStageCreate(stage);
    if (deviceInfo.deviceType === '2in1' && deviceInfo.sdkApiVersion >= 14) {
      try {
        this.pcWindow = stage.getMainWindowSync();
        if (deviceInfo.sdkApiVersion >= 15) this.pcWindow.on('windowWillClose', (): Promise<boolean> => this.confirmWindowClose());
      } catch (error) { console.error('Window close interception unavailable: ' + String(error)); }
    }
    if (this.isForeground) {
      this.restoreTrayWindow();
      this.share?.startReceiving();
    }
  }

  onWindowStageDestroy(): void {
    this.share?.stopReceiving();
    try { this.pcWindow?.off('windowWillClose'); } catch (error) { console.error(String(error)); }
    this.pcWindow = undefined;
    super.onWindowStageDestroy();
  }

  private setTray(call: MethodCall, result: MethodResult): void {
    const enabled = call.argument('enabled') as boolean;
    const generation = this.trayGeneration;
    const operation = this.trayOperation.then((): Promise<void> => this.applyTray(enabled, generation));
    this.trayOperation = operation.catch((): void => {});
    operation.then((): void => result.success(null)).catch((error: Error): void => result.error('tray_failed', String(error), null));
  }

  private async applyTray(enabled: boolean, generation: number): Promise<void> {
    if (!this.trayEngineReady || generation !== this.trayGeneration) throw new Error('Flutter engine is unavailable');
    if (enabled === this.trayEnabled) return;
    if (!enabled) {
      statusBarManager.removeFromStatusBar(this.context);
      statusBarManager.off('statusBarIconClick', this.trayIconClick);
      this.trayEnabled = false;
      return;
    }
    if (deviceInfo.deviceType !== '2in1' || deviceInfo.sdkApiVersion < 15 ||
        !canIUse('SystemCapability.PCService.StatusBarManager')) throw new Error('Status bar is unavailable');
    if (deviceInfo.sdkApiVersion >= 26 && !await statusBarManager.isStatusBarCapabilitySupported(this.context)) {
      throw new Error('Status bar is unavailable');
    }
    const whiteData = this.context.resourceManager.getRawFileContentSync('tray-white.png');
    const blackData = this.context.resourceManager.getRawFileContentSync('tray-black.png');
    const white = await image.createImageSource(whiteData.buffer).createPixelMap();
    const black = await image.createImageSource(blackData.buffer).createPixelMap();
    const item: statusBarManager.StatusBarItem = {
      icons: { white: white, black: black },
      quickOperation: { abilityName: '', title: 'LocalSend', height: 1 },
      statusBarGroupMenu: [[{ title: 'LocalSend', menuAction: { abilityName: 'EntryAbility' } }]],
    };
    if (!this.trayEngineReady || generation !== this.trayGeneration) throw new Error('Flutter engine is unavailable');
    statusBarManager.on('statusBarIconClick', this.trayIconClick);
    try {
      await new Promise<void>((resolve, reject): void => {
        statusBarManager.addToStatusBar(this.context, item, (error): void => {
          if (error) reject(error); else resolve();
        });
      });
    } catch (error) {
      statusBarManager.off('statusBarIconClick', this.trayIconClick);
      throw new Error(String(error));
    }
    if (!this.trayEngineReady || generation !== this.trayGeneration) {
      statusBarManager.removeFromStatusBar(this.context);
      statusBarManager.off('statusBarIconClick', this.trayIconClick);
      throw new Error('Flutter engine is unavailable');
    }
    this.trayEnabled = true;
  }

  private async autoStartupStatus(result: MethodResult): Promise<void> {
    try {
      const data = new Map<string, boolean>();
      const supported = deviceInfo.deviceType === '2in1' && deviceInfo.sdkApiVersion >= 21 &&
        (deviceInfo.sdkApiVersion < 26 || autoStartupManager.isAutoStartupSupported());
      data.set('supported', supported);
      if (supported) data.set('enabled', await autoStartupManager.getAutoStartupStatusForSelf());
      result.success(data);
    } catch (error) { result.error('auto_startup_status_failed', String(error), null); }
  }

  private async setTopmost(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (!this.pcWindow || deviceInfo.deviceType !== '2in1' || deviceInfo.sdkApiVersion < 14) {
        throw new Error('Window pinning is unavailable');
      }
      const enabled = call.argument('enabled') as boolean;
      await this.pcWindow.setWindowTopmost(enabled);
      result.success(null);
    } catch (error) { result.error('window_topmost_failed', String(error), null); }
  }

  private confirmWindowClose(): Promise<boolean> {
    return new Promise<boolean>((resolve): void => {
      const channel = this.windowChannel;
      if (!channel) { resolve(this.trayEnabled); return; }
      const args = new Map<string, Object>();
      args.set('trayEnabled', this.trayEnabled);
      channel.invokeMethod('willClose', args, {
        success: (decision: ESObject): void => {
          if (decision === 'minimize' && this.pcWindow) {
            this.pcWindow.minimize().then((): void => resolve(true)).catch((error: Error): void => {
              console.error('Cannot minimize window: ' + String(error));
              this.windowChannel?.invokeMethod('trayMinimizeFailed', null);
              resolve(true);
            });
          } else resolve(decision !== 'close');
        },
        error: (): void => resolve(true),
        notImplemented: (): void => resolve(this.trayEnabled),
      });
    });
  }

  onForeground(): void {
    super.onForeground();
    this.isForeground = true;
    if (this.trayRestoreRequested) this.restoreTrayWindow();
    this.share?.startReceiving();
  }

  onBackground(): void {
    this.isForeground = false;
    this.share?.stopReceiving();
    this.share?.disarm();
    super.onBackground();
  }

  private async getAppVersion(result: MethodResult): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const version = new Map<string, Object>();
      version.set('version', info.versionName);
      version.set('buildNumber', String(info.versionCode));
      result.success(version);
    } catch (error) {
      result.error('bundle_info_failed', String(error), null);
    }
  }

  private containsFolder(event: DragEvent): boolean {
    try {
      for (const record of event.getData().getRecords()) {
        try {
          const type = record.getType();
          if (type === 'general.folder') return true;
          if (type === 'general.file-uri') {
            if ((record.getValue() as uniformDataStruct.FileUri).fileType === 'general.folder') return true;
          } else if (type === 'general.file') {
            // Some file managers report both files and folders as general.file.
            const uri = (record as unifiedDataChannel.File).uri;
            let file: fs.File | undefined;
            try {
              file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
              if (fs.statSync(file.fd).isDirectory()) return true;
            } finally {
              if (file) fs.closeSync(file);
            }
          }
        } catch (_) { /* Continue checking the other records. */ }
      }
    } catch (_) {
      // Let the normal file handler report an unreadable record.
    }
    return false;
  }

  private loadFolderDrop(event: DragEvent): void {
    let root: string = '';
    let completed = false;
    try {
      root = fs.mkdtempSync(this.context.cacheDir + '/localsend-drop-folder-XXXXXX');
      const destination = root;
      const options: DataSyncOptions = {
        destUri: fileUri.getUriFromPath(destination),
        fileConflictOptions: unifiedDataChannel.FileConflictOptions.SKIP,
        progressIndicator: unifiedDataChannel.ProgressIndicator.DEFAULT,
        dataProgressListener: (progress: unifiedDataChannel.ProgressInfo, data: unifiedDataChannel.UnifiedData | null): void => {
          if (completed || progress.status === unifiedDataChannel.ListenerStatus.PROCESSING) return;
          completed = true;
          if (progress.status !== unifiedDataChannel.ListenerStatus.FINISHED || !data) {
            try { fs.rmdirSync(destination); } catch (_) {}
            this.reportDrop([], [], 1);
            return;
          }
          const files: Array<string> = [];
          const directories: Array<string> = [];
          let failed = 0;
          try {
            for (const name of fs.listFileSync(destination)) {
              if (!name || name === '.' || name === '..' || name.includes('/') || name.includes('\\')) {
                failed++;
                continue;
              }
              try {
                const path = destination + '/' + name;
                const info = fs.lstatSync(path);
                if (info.isDirectory()) directories.push(path);
                else if (info.isFile()) files.push(path);
                else failed++;
              } catch (_) {
                failed++;
              }
            }
            // SKIP avoids overwriting names; report records not copied.
            failed = Math.max(failed, data.getRecords().length - files.length - directories.length);
          } catch (_) {
            failed++;
          }
          this.reportDrop(files, directories, failed, destination);
        }
      };
      // Must be invoked synchronously inside the onDrop callback, so the
      // system can carry the temporary folder grants into its copy operation.
      event.startDataLoading(options);
    } catch (_) {
      if (root) { try { fs.rmdirSync(root); } catch (_) {} }
      if (!completed) this.reportDrop([], [], 1);
    }
  }

  cleanUpFlutterEngine(flutterEngine: FlutterEngine): void {
    this.trayEngineReady = false;
    this.trayGeneration++;
    this.share?.detach();
    if (deviceInfo.sdkApiVersion >= 15) {
      try { backgroundTaskManager.off('continuousTaskCancel', this.backgroundCancelled); }
      catch (error) { console.error('Cannot remove background cancellation observer: ' + String(error)); }
    }
    this.backgroundChannel?.setMethodCallHandler(null);
    this.backgroundChannel = undefined;
    if (this.network) {
      try { this.network.unregister((error): void => { if (error) console.error('Network observer cleanup failed: ' + String(error)); }); }
      catch (error) { console.error('Network observer cleanup failed: ' + String(error)); }
      this.network = undefined;
    }
    this.networkChannel?.setMethodCallHandler(null);
    this.networkChannel = undefined;
    this.windowChannel = undefined;
    const manager = FlutterManager.getInstance();
    if (this.dragEnterId) manager.removeDragEnterCb(this.dragEnterId);
    if (this.dragLeaveId) manager.removeDragLeaveCb(this.dragLeaveId);
    if (this.dropId) manager.removeDropCb(this.dropId);
    this.dragEnterId = 0;
    this.dragLeaveId = 0;
    this.dropId = 0;
    this.dropChannel = undefined;
    super.cleanUpFlutterEngine(flutterEngine);
  }

  private async requestNotifications(result: MethodResult): Promise<void> {
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        await notificationManager.requestEnableNotification(this.context);
      }
      result.success(await notificationManager.isNotificationEnabled());
    } catch (error) {
      result.error('notification_permission', String(error), null);
    }
  }

  private async notifyIncoming(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        const text = call.argument('text') as string;
        const agent = await wantAgent.getWantAgent({
          wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: 'EntryAbility' }],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 4101,
          actionFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG],
        });
        const request: notificationManager.NotificationRequest = {
          id: 4101,
          wantAgent: agent,
          content: {
            notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: { title: 'LocalSend', text: text }
          }
        };
        await notificationManager.publish(request);
      } else {
        throw new Error('Background task is not running');
      }
      result.success(null);
    } catch (error) {
      result.error('notification_failed', String(error), null);
    }
  }

  private async handleDrop(event: DragEvent): Promise<void> {
    const paths: Array<string> = [];
    const opened: Array<DroppedFile> = [];
    let failed = 0;
    try {
      // Open every URI before the callback returns: drag grants can end with
      // the drag session. Open descriptors remain usable for async copying.
      const records = event.getData().getRecords();
      for (const record of records) {
        try {
          const type = record.getType();
          if (type === 'general.folder') {
            failed++;
            continue;
          }
          let uri: string = '';
          if (type === 'general.file-uri') {
            uri = (record.getValue() as uniformDataStruct.FileUri).oriUri;
          } else if (type === 'general.file' || type === 'general.image' || type === 'general.video' || type === 'general.audio') {
            uri = (record as unifiedDataChannel.File).uri;
          }
          if (!uri || !uri.startsWith('file://')) {
            failed++;
            continue;
          }
          let source: fs.File | undefined;
          let targetDir: string = '';
          try {
            source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
            if (!fs.statSync(source.fd).isFile()) {
              throw new Error('Only regular files are supported');
            }
            const name = source.name.replaceAll('/', '_').replaceAll('\\', '_');
            if (!name || name === '.' || name === '..') {
              throw new Error('Invalid file name');
            }
            targetDir = fs.mkdtempSync(this.context.cacheDir + '/localsend-drop-XXXXXX');
            opened.push(new DroppedFile(source, targetDir + '/' + name, targetDir));
            source = undefined; // Ownership transferred to opened.
          } catch (error) {
            if (targetDir) {
              try { fs.rmdirSync(targetDir); } catch (_) {}
            }
            throw new Error(error instanceof Error ? error.message : String(error));
          } finally {
            if (source) fs.closeSync(source);
          }
        } catch (_) {
          failed++;
        }
      }
    } catch (_) {
      failed++;
    }
    for (const file of opened) {
      try {
        await fs.copyFile(file.source.fd, file.target);
        paths.push(file.target);
      } catch (_) {
        failed++;
        try { fs.unlinkSync(file.target); } catch (_) {}
        try { fs.rmdirSync(file.directory); } catch (_) {}
      } finally {
        try { fs.closeSync(file.source); } catch (_) {}
      }
    }
    this.reportDrop(paths, [], failed);
  }

  private reportDrop(paths: Array<string>, directories: Array<string>, failed: number, root?: string): void {
    const payload = new Map<string, Object>();
    payload.set('paths', paths);
    payload.set('directories', directories);
    payload.set('failed', failed);
    const channel = this.dropChannel;
    if (!channel) {
      if (root) { try { fs.rmdirSync(root); } catch (_) {} }
      else this.removeDropFiles(paths);
      return;
    }
    const cleanup = (): void => {
      if (root) { try { fs.rmdirSync(root); } catch (_) {} }
      else this.removeDropFiles(paths);
    };
    channel.invokeMethod('dropped', payload, {
      success: (accepted: ESObject): void => {
        if (accepted !== true) cleanup();
      },
      error: (): void => cleanup(),
      notImplemented: (): void => cleanup(),
    });
  }

  private removeDropFiles(paths: Array<string>): void {
    for (const path of paths) {
      try { fs.unlinkSync(path); } catch (_) {}
      try { fs.rmdirSync(path.substring(0, path.lastIndexOf('/'))); } catch (_) {}
    }
  }

  private async openFile(call: MethodCall, result: MethodResult): Promise<void> {
    let file: fs.File | undefined;
    try {
      const path = call.argument('path') as string;
      if (!path || !path.startsWith('/')) throw new Error('Invalid file path');
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      if (!fs.statSync(file.fd).isFile()) throw new Error('Not a file');
      const uri = fileUri.getUriFromPath(path);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
      };
      await this.context.startAbility(want);
      result.success(null);
    } catch (error) { result.error('open_file_failed', String(error), null); }
    finally { if (file) fs.closeSync(file); }
  }

  private async exportFile(call: MethodCall, result: MethodResult): Promise<void> {
    let source: fs.File | undefined;
    let destination: fs.File | undefined;
    try {
      const sourcePath = call.argument('path') as string;
      const name = call.argument('name') as string;
      if (!sourcePath || !name || name.includes('/') || name.includes('\\')) {
        result.error('invalid_argument', 'Invalid source path or file name', null);
        return;
      }
      // Check the source before asking the user to create a destination.
      let saved = false;
      try {
        source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [name];
        const preferredFolder = call.argument('preferredFolder') as string | null;
        if (preferredFolder) options.defaultFilePathUri = preferredFolder;
        const uris = await new picker.DocumentViewPicker(this.context).save(options);
        if (uris && uris.length > 0) {
          destination = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          await fs.copyFile(source.fd, destination.fd);
          saved = true;
        }
      } finally {
        try {
          if (destination) {
            fs.closeSync(destination);
          }
        } finally {
          if (source) {
            fs.closeSync(source);
          }
        }
      }
      result.success(saved);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      result.error('export_failed', message, null);
    }
  }
}
