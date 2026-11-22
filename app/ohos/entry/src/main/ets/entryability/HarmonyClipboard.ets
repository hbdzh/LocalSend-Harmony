import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { discardClipboardCopies, readAuthorizedClipboard } from './HarmonyClipboardData';

class PasteDialogParams {
  chinese: boolean;
  paste: () => void;
  cancel: () => void;
  denied: () => void;
  constructor(chinese: boolean, paste: () => void, cancel: () => void, denied: () => void) {
    this.chinese = chinese;
    this.paste = paste;
    this.cancel = cancel;
    this.denied = denied;
  }
}

@Builder
function pasteDialog(params: PasteDialogParams) {
  Column({ space: 20 }) {
    Text(params.chinese ? '点击系统粘贴按钮以读取剪贴板' : 'Use the system paste button to read the clipboard')
      .fontSize(18)
    PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE })
      .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
        if (result === PasteButtonOnClickResult.SUCCESS) params.paste();
        else params.denied();
      })
    Button(params.chinese ? '取消' : 'Cancel').onClick(() => params.cancel())
  }
  .padding(24)
  .backgroundColor($r('sys.color.ohos_id_color_dialog_bg'))
  .borderRadius(24)
}

export class HarmonyClipboard {
  private context: common.UIAbilityContext;
  private busy: boolean = false;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async open(chinese: boolean, result: MethodResult): Promise<void> {
    if (this.busy) { result.error('clipboard_busy', 'Clipboard dialog is already open', null); return; }
    this.busy = true;
    let done = false;
    let processing = false;
    try {
      const mainWindow = await window.getLastWindow(this.context);
      const ui = mainWindow.getUIContext();
      const prompt = ui.getPromptAction();
      let content: ComponentContent<PasteDialogParams>;
      const close = (): void => {
        prompt.closeCustomDialog(content).catch((error: Error): void => console.error('Cannot close paste dialog: ' + String(error)))
          .finally((): void => { this.busy = false; });
      };
      const cancel = (): void => {
        if (done || processing) return;
        done = true;
        result.success(null);
        close();
      };
      const paste = (): void => {
        if (done || processing) return;
        processing = true;
        readAuthorizedClipboard(this.context.filesDir).then((data: Map<string, Object>): void => {
          if (!done) { done = true; result.success(data); close(); }
          else discardClipboardCopies(data);
        }).catch((error: Error): void => {
          if (!done) { done = true; result.error('clipboard_failed', String(error), null); close(); }
        });
      };
      const denied = (): void => {
        if (done || processing) return;
        done = true;
        result.error('clipboard_denied', 'Paste authorization failed', null);
        close();
      };
      content = new ComponentContent(ui, wrapBuilder(pasteDialog), new PasteDialogParams(chinese, paste, cancel, denied));
      await prompt.openCustomDialog(content, {
        autoCancel: false,
        onDidDisappear: (): void => {
          this.busy = false;
          if (!done) { done = true; result.success(null); }
        },
      });
    } catch (error) {
      this.busy = false;
      if (!done) { done = true; result.error('clipboard_failed', String(error), null); }
    }
  }
}
