import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Trigger a browser file download by creating a Blob URL and
/// programmatically clicking an `<a>` tag.
///
/// The URL is revoked immediately after the click so the browser
/// doesn't hold the bytes alive.
Future<void> downloadBlob(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  // `package:web` requires the Blob constructor to be fed a JS array
  // of BlobPart values. A typed `Uint8List` round-trips through
  // `toJS` automatically.
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
