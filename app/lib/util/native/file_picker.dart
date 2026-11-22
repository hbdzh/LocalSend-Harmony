import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/apk_picker_page.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/determine_image_type.dart';
import 'package:localsend_app/util/image_converter.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/harmony_clipboard_cache.dart';
import 'package:localsend_app/util/native/harmony_empty_folder.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/asset_picker_translated_text_delegate.dart';
import 'package:localsend_app/widget/dialogs/loading_dialog.dart';
import 'package:localsend_app/widget/dialogs/message_input_dialog.dart';
import 'package:localsend_app/widget/dialogs/no_permission_dialog.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/util/file_path_helper.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:logging/logging.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:uri_content/uri_content.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

final _logger = Logger('FilePickerHelper');
final _uriContent = UriContent();

enum FilePickerOption {
  file(Icons.description),
  folder(Icons.folder),
  media(Icons.image),
  text(Icons.subject),
  app(Icons.apps),
  clipboard(Icons.paste)
  ;

  const FilePickerOption(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case FilePickerOption.file:
        return t.sendTab.picker.file;
      case FilePickerOption.folder:
        return t.sendTab.picker.folder;
      case FilePickerOption.media:
        return t.sendTab.picker.media;
      case FilePickerOption.text:
        return t.sendTab.picker.text;
      case FilePickerOption.app:
        return t.sendTab.picker.app;
      case FilePickerOption.clipboard:
        return t.sendTab.picker.clipboard;
    }
  }

  /// Returns the options for the current platform.
  static List<FilePickerOption> getOptionsForPlatform() {
    if (!kIsWeb && Platform.operatingSystem == 'ohos') {
      return [FilePickerOption.file, FilePickerOption.text, FilePickerOption.clipboard];
    }
    if (checkPlatform([TargetPlatform.iOS])) {
      // On iOS, picking from media is most common.
      // The file app is very limited.
      return [
        FilePickerOption.media,
        FilePickerOption.text,
        FilePickerOption.clipboard,
        FilePickerOption.file,
        FilePickerOption.folder,
      ];
    } else if (checkPlatform([TargetPlatform.android])) {
      // On android, the file app is most powerful.
      // It actually also allows to pick media files.
      return [
        FilePickerOption.file,
        FilePickerOption.media,
        FilePickerOption.clipboard,
        FilePickerOption.text,
        FilePickerOption.folder,
        FilePickerOption.app,
      ];
    } else {
      // Desktop
      return [
        FilePickerOption.file,
        FilePickerOption.folder,
        FilePickerOption.text,
        FilePickerOption.clipboard,
      ];
    }
  }
}

class PickFileAction extends AsyncGlobalAction {
  final FilePickerOption option;
  final BuildContext context;

  PickFileAction({
    required this.option,
    required this.context,
  });

  @override
  Future<void> reduce() async {
    switch (option) {
      case FilePickerOption.file:
        await _pickFiles(context, ref);
        break;
      case FilePickerOption.folder:
        // ignore: use_build_context_synchronously
        await _pickFolder(context, ref);
        break;
      case FilePickerOption.media:
        // ignore: use_build_context_synchronously
        await _pickMedia(context, ref);
        break;
      case FilePickerOption.text:
        // ignore: use_build_context_synchronously
        await _pickText(context, ref);
        break;
      case FilePickerOption.clipboard:
        // ignore: use_build_context_synchronously
        await _pickClipboard(context, ref);
        break;
      case FilePickerOption.app:
        // ignore: use_build_context_synchronously
        await _pickApp(context);
        break;
    }
  }

  @override
  String toString() {
    return 'PickAction(option: $option)';
  }
}

Future<void> _pickFiles(BuildContext context, Ref ref) async {
  final hasLoadingDialog = checkPlatform([TargetPlatform.android]);
  if (hasLoadingDialog) {
    // On android, the files are copied to the cache which takes some time.
    // ignore: unawaited_futures
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingDialog(),
    );
  }
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final result = await android_channel.pickFilesAndroid();
      if (result != null) {
        await ref
            .redux(selectedSendingFilesProvider)
            .dispatchAsync(
              AddFilesAction(
                files: result,
                converter: CrossFileConverters.convertFileInfo,
              ),
            );
      }
    } else {
      final result = await openFiles();
      await ref
          .redux(selectedSendingFilesProvider)
          .dispatchAsync(
            AddFilesAction(
              files: result,
              converter: CrossFileConverters.convertXFile,
            ),
          );
    }
  } catch (e) {
    if (e is PlatformException && e.code == 'CANCELED') {
      // User canceled the file picker
      _logger.info('User canceled file picker');
      return;
    }

    // ignore: use_build_context_synchronously
    await showDialog(context: context, builder: (_) => const NoPermissionDialog());
    _logger.warning('Failed to pick files', e);
  } finally {
    if (hasLoadingDialog) {
      // ignore: use_build_context_synchronously
      Routerino.context.popUntilRoot(); // remove loading dialog
    }
  }
}

Future<void> _pickFolder(BuildContext context, Ref ref) async {
  if (checkPlatform([TargetPlatform.android])) {
    try {
      await Permission.storage.request();
    } catch (e) {
      _logger.warning('Failed to request storage permission', e);
    }
  }

  if (!context.mounted) {
    return;
  }

  // ignore: unawaited_futures
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LoadingDialog(),
  );
  await sleepAsync(200); // Wait for the dialog to be shown
  try {
    if (defaultTargetPlatform == TargetPlatform.android && (ref.read(deviceInfoProvider).androidSdkInt ?? 0) >= android_channel.contentUriMinSdk) {
      // Android 8 and above have more predictable content URIs that we can parse.
      final result = await android_channel.pickDirectoryAndroid();
      if (result != null) {
        await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddAndroidDirectoryAction(result));
      }
    } else {
      final directoryPath = isHarmonyOS
          ? await const MethodChannel('org.localsend.localsend_app/harmony_device').invokeMethod<String>('pickFolder')
          : await pickDirectoryPath();
      if (directoryPath != null) {
        final zip = isHarmonyOS ? await prepareHarmonyFolder(directoryPath) : null;
        if (zip != null) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(files: [zip], converter: CrossFileConverters.convertFile),
              );
        } else {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directoryPath, followLinks: !isHarmonyOS));
        }
      }
    }
  } catch (e) {
    if (e is PlatformException && e.code == 'CANCELED') {
      // User canceled the file picker
      _logger.info('User canceled file picker');
      return;
    }

    _logger.warning('Failed to pick directory', e);
    // ignore: use_build_context_synchronously
    await showDialog(context: context, builder: (_) => const NoPermissionDialog());
  } finally {
    // ignore: use_build_context_synchronously
    Routerino.context.popUntilRoot(); // remove loading dialog
  }
}

Future<void> _pickMedia(BuildContext context, Ref ref) async {
  if (checkPlatform([TargetPlatform.android])) {
    await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
  }

  if (!context.mounted) return;

  final oldBrightness = Theme.of(context).brightness;
  final List<AssetEntity>? result = await AssetPicker.pickAssets(
    context,
    pickerConfig: const AssetPickerConfig(maxAssets: 999, textDelegate: TranslatedAssetPickerTextDelegate()),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // restore brightness for Android
    await sleepAsync(500);
    if (context.mounted) {
      await updateSystemOverlayStyleWithBrightness(oldBrightness);
    }
  });

  if (result != null) {
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction(
            files: result,
            converter: CrossFileConverters.convertAssetEntity,
          ),
        );
  }
}

Future<void> _pickText(BuildContext context, Ref ref) async {
  final result = await showDialog<String>(context: context, builder: (_) => const MessageInputDialog());
  if (result != null) {
    ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: result));
  }
}

Future<void> _pickClipboard(BuildContext context, Ref ref) async {
  if (isHarmonyOS) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    try {
      final clipboardStore = await HarmonyClipboardCache.store();
      final value = await const MethodChannel(
        'org.localsend.localsend_app/harmony_clipboard',
      ).invokeMapMethod<String, dynamic>('read', {'chinese': chinese});
      final paths = (value?['paths'] as List?)?.cast<String>();
      final path = value?['path'] as String?;
      if (paths != null) {
        var failed = (value?['failed'] as int?) ?? 0;
        var zipped = false;
        for (final importedPath in paths) {
          try {
            HarmonyClipboardCache.register(File(importedPath).parent.path);
            await ref
                .redux(selectedSendingFilesProvider)
                .dispatchAsync(
                  AddFilesAction(
                    files: [File(importedPath)],
                    converter: (file) async {
                      final name = file.path.fileName;
                      return CrossFile(
                        name: name,
                        fileType: name.guessFileType(),
                        size: await file.length(),
                        thumbnail: null,
                        asset: null,
                        path: file.path,
                        bytes: null,
                        lastModified: null,
                        lastAccessed: null,
                      );
                    },
                  ),
                );
          } catch (error, stack) {
            failed++;
            _logger.warning('Could not add pasted file', error, stack);
            await _discardHarmonyClipboardCopy(importedPath);
          }
        }
        for (final directory in (value?['directories'] as List? ?? const []).cast<String>()) {
          File? zip;
          try {
            HarmonyClipboardCache.register(Directory(directory).parent.path);
            zip = await prepareHarmonyFolder(directory, temporaryDirectory: clipboardStore);
            if (zip != null) {
              HarmonyClipboardCache.register(zip.parent.path);
              await ref
                  .redux(selectedSendingFilesProvider)
                  .dispatchAsync(
                    AddFilesAction(files: [zip], converter: CrossFileConverters.convertFile),
                  );
              zipped = true;
              await _discardHarmonyClipboardCopy(directory);
            } else {
              await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory, followLinks: false));
            }
          } catch (error, stack) {
            failed++;
            _logger.warning('Could not add pasted folder', error, stack);
            if (zip != null) {
              try {
                await zip.parent.delete(recursive: true);
                HarmonyClipboardCache.forget(zip.parent.path);
              } catch (cleanupError, cleanupStack) {
                _logger.warning('Could not remove failed folder ZIP', cleanupError, cleanupStack);
              }
            }
            await _discardHarmonyClipboardCopy(directory);
          }
        }
        if ((failed > 0 || zipped) && context.mounted) {
          final messages = <String>[
            if (failed > 0) chinese ? '$failed 个剪贴板文件或文件夹无法导入。' : '$failed clipboard file(s) could not be imported.',
            if (zipped) chinese ? '包含空文件夹，已打包为 ZIP；接收后解压即可恢复。' : 'Folders containing empty folders were packed as ZIP; extract after receiving.',
          ];
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(messages.join('\n'))));
        }
      } else if (path != null) {
        HarmonyClipboardCache.register(File(path).parent.path);
        await ref
            .redux(selectedSendingFilesProvider)
            .dispatchAsync(
              AddFilesAction(
                files: [File(path)],
                converter: (file) async => CrossFile(
                  name: 'clipboard.png',
                  fileType: FileType.image,
                  size: await file.length(),
                  thumbnail: null,
                  asset: null,
                  path: file.path,
                  bytes: null,
                  lastModified: null,
                  lastAccessed: null,
                ),
              ),
            );
      } else if (value?['text'] != null) {
        ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: value!['text'] as String));
      } else if (value != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.general.noItemInClipboard)));
      }
    } catch (error, stack) {
      _logger.warning('Could not read HarmonyOS clipboard', error, stack);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chinese ? '无法读取剪贴板，请重试或使用文件选择。' : 'Could not read the clipboard. Try again or choose a file.')),
        );
      }
    }
    return;
  }
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null) {
    ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: data!.text!));
    return;
  }

  final image = await Pasteboard.image;
  if (image != null) {
    // Adding temporary variable because Dart analyzer somehow doesn't properly downcast Uint8List? to Uint8List
    Uint8List currImage = image;
    String imageType = determineImageType(image);

    // On Windows, Pasteboard read image from clipboard as BMP which is large and inefficient. Attempt to convert to PNG
    if (imageType == 'bmp') {
      try {
        final pngImage = await convertBmpToPng(image);
        currImage = pngImage;
        imageType = 'png';
      } catch (e) {
        // Fail to convert to png, proceed with existing bmp
      }
    }

    final now = DateTime.now();
    final fileName =
        'clipboard_${now.year}-${now.month.twoDigitString}-${now.day.twoDigitString}_${now.hour.twoDigitString}-${now.minute.twoDigitString}.$imageType';
    ref
        .redux(selectedSendingFilesProvider)
        .dispatch(
          AddBinaryAction(
            bytes: currImage,
            fileType: FileType.image,
            fileName: fileName,
          ),
        );
    return;
  }

  final List<String> files = await Pasteboard.files();
  if (files.isNotEmpty) {
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction(
            files: files.map((e) => XFile(e)).toList(),
            converter: (file) async {
              if (!file.path.startsWith('content://')) {
                return CrossFileConverters.convertXFile(file);
              }
              // handle content uri
              return CrossFile(
                name: file.name,
                fileType: file.name.guessFileType(),
                size: await _uriContent.getContentLength(Uri.parse(file.path)) ?? -1,
                path: file.path,
                thumbnail: null,
                asset: null,
                bytes: null,
                lastModified: null,
                lastAccessed: null,
              );
            },
          ),
        );
    return;
  }

  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(t.general.noItemInClipboard),
    ),
  );
}

Future<void> _discardHarmonyClipboardCopy(String itemPath) async {
  try {
    final cache = p.normalize((await HarmonyClipboardCache.store()).absolute.path);
    final parent = p.normalize(Directory(itemPath).absolute.parent.path);
    if (p.dirname(parent) == cache && p.basename(parent).startsWith('localsend-clipboard-file-')) {
      await Directory(parent).delete(recursive: true);
      HarmonyClipboardCache.forget(parent);
    }
  } catch (error, stack) {
    _logger.warning('Could not remove clipboard copy', error, stack);
  }
}

Future<void> _pickApp(BuildContext context) async {
  // Currently, only Android APK
  await context.push(() => const ApkPickerPage());
}

extension on int {
  String get twoDigitString => toString().padLeft(2, '0');
}
