import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:routerino/routerino.dart';

class FileInfoDialog extends StatelessWidget {
  final ReceiveHistoryEntry entry;

  const FileInfoDialog({required this.entry, super.key});

  Widget _field(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          SelectableText(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.dialogs.fileInfo.title),
      content: isHarmonyOS
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!entry.isMessage) ...[
                    _field(context, t.dialogs.fileInfo.fileName, entry.fileName),
                    _field(context, t.dialogs.fileInfo.path, entry.savedToGallery ? t.progressPage.savedToGallery : (entry.path ?? '')),
                  ],
                  _field(context, t.dialogs.fileInfo.size, entry.fileSize.asReadableFileSize),
                  _field(context, t.dialogs.fileInfo.sender, entry.senderAlias),
                  _field(context, t.dialogs.fileInfo.time, entry.timestampString(context)),
                  if (entry.isMessage) _field(context, '', entry.fileName),
                ],
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: IntrinsicColumnWidth(),
                        2: IntrinsicColumnWidth(),
                      },
                      children: [
                        if (!entry.isMessage) ...[
                          TableRow(
                            children: [
                              Text(t.dialogs.fileInfo.fileName, maxLines: 1),
                              const SizedBox(width: 10),
                              SelectableText(entry.fileName),
                            ],
                          ),
                          TableRow(
                            children: [
                              Text(t.dialogs.fileInfo.path),
                              const SizedBox(width: 10),
                              SelectableText(entry.savedToGallery ? t.progressPage.savedToGallery : (entry.path ?? '')),
                            ],
                          ),
                        ],
                        TableRow(
                          children: [
                            Text(t.dialogs.fileInfo.size),
                            const SizedBox(width: 10),
                            SelectableText(entry.fileSize.asReadableFileSize),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(t.dialogs.fileInfo.sender),
                            const SizedBox(width: 10),
                            SelectableText(entry.senderAlias),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(t.dialogs.fileInfo.time),
                            const SizedBox(width: 10),
                            SelectableText(entry.timestampString(context)),
                          ],
                        ),
                      ],
                    ),
                    if (entry.isMessage)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SelectableText(entry.fileName),
                      ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.close),
        ),
      ],
    );
  }
}
