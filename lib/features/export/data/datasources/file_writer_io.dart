import 'dart:io';
import 'dart:typed_data';

/// Native (dart:io) implementation of [writeFileBytes]. Selected by
/// the conditional import in `file_dialog_save_datasource.dart` for
/// every non-web target.
Future<void> writeFileBytes(String path, Uint8List bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
}
