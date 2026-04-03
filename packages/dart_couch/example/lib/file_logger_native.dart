import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class FileLogger {
  static IOSink? _sink;
  static String? _logFilePath;

  /// Request storage permissions needed to write to Downloads on Android.
  /// Returns true if Downloads should be attempted.
  static Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return false;

    // Android 11+ (API 30+): need MANAGE_EXTERNAL_STORAGE
    // Android 10 and below: need WRITE_EXTERNAL_STORAGE
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    // Ask for MANAGE_EXTERNAL_STORAGE (opens the "All files access" screen
    // on Android 11+). On older versions this falls through to storage.
    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) return true;

    // Fallback for Android <=10
    final storageResult = await Permission.storage.request();
    return storageResult.isGranted;
  }

  static Future<void> init() async {
    final now = DateTime.now();
    final date =
        '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final time =
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final fileName = 'einkaufsliste_${date}_$time.log';

    // Request permission before trying to write to Downloads.
    final hasStoragePermission = await _requestStoragePermission();

    // Try candidate directories in order. The Downloads folder is preferred
    // because it is easy to access from a file manager, but writing there
    // requires storage permission. If permission was denied or the open fails
    // we fall back to the app-specific external storage (no permission needed).
    final candidates = <Future<String?> Function()>[
      if (Platform.isAndroid && hasStoragePermission)
        () async {
          final d = Directory('/storage/emulated/0/Download');
          return await d.exists() ? d.path : null;
        },
      () async => (await getExternalStorageDirectory())?.path,
      () async => (await getApplicationSupportDirectory()).path,
    ];

    bool downloadsFailed = false;
    for (final getDir in candidates) {
      final dirPath = await getDir();
      if (dirPath == null) continue;
      try {
        final file = File('$dirPath/$fileName');
        _sink = file.openWrite(mode: FileMode.append);
        _logFilePath = file.path;
        if (downloadsFailed) {
          // ignore: avoid_print
          print('[FileLogger] Downloads not writable. '
              'On Android 11+, grant "All files access" in '
              'Settings > Apps > Einkaufsliste > Permissions.');
          // ignore: avoid_print
          print('[FileLogger] Logging to fallback: $_logFilePath');
        } else {
          // ignore: avoid_print
          print('[FileLogger] Logging to: $_logFilePath');
        }
        return;
      } on FileSystemException catch (_) {
        downloadsFailed = true;
      }
    }
  }

  static void writeln(String line) {
    _sink?.writeln(line);
  }

  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  static String? get logFilePath => _logFilePath;

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
