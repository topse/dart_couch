import 'dart:io' show gzip;

/// Decompress gzip-encoded data using dart:io's GZipCodec.
Future<List<int>> gzipDecode(List<int> data) async => gzip.decode(data);

/// Streaming gzip decompression using dart:io's GZipCodec decoder.
Stream<List<int>> gzipDecodeStream(Stream<List<int>> input) =>
    input.transform(gzip.decoder);
