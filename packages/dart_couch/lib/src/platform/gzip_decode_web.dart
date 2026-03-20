import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Decompress gzip-encoded data on web using the Compression Streams API.
///
/// Uses the browser's built-in DecompressionStream which is supported in all
/// modern browsers (Chrome 80+, Firefox 113+, Safari 16.4+).
Future<List<int>> gzipDecode(List<int> data) async {
  final compressed = Uint8List.fromList(data);
  final ds = web.DecompressionStream('gzip');
  final writer = ds.writable.getWriter();
  writer.write(compressed.toJS);
  writer.close();

  final reader = ds.readable.getReader() as web.ReadableStreamDefaultReader;
  final chunks = <int>[];

  while (true) {
    final result = await reader.read().toDart;
    if (result.done) break;
    final chunk = (result.value as JSUint8Array).toDart;
    chunks.addAll(chunk);
  }

  return chunks;
}

/// Streaming gzip decompression on web using the Compression Streams API.
///
/// Pipes the input stream through the browser's DecompressionStream and
/// yields decompressed chunks as they become available.
Stream<List<int>> gzipDecodeStream(Stream<List<int>> input) async* {
  final ds = web.DecompressionStream('gzip');
  final writer = ds.writable.getWriter();
  final reader = ds.readable.getReader() as web.ReadableStreamDefaultReader;

  // Feed input chunks to the decompressor in the background.
  bool writerDone = false;
  final writeFuture = () async {
    await for (final chunk in input) {
      writer.write(Uint8List.fromList(chunk).toJS);
    }
    await writer.close().toDart;
    writerDone = true;
  }();

  // Read decompressed chunks as they become available.
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;
      yield (result.value as JSUint8Array).toDart;
    }
  } finally {
    // Ensure the writer future completes even if consumer cancels.
    if (!writerDone) {
      try {
        await writer.close().toDart;
      } catch (_) {}
    }
    await writeFuture;
  }
}
