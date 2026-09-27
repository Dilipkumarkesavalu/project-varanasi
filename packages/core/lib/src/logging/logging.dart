import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Root logger for app code. Use child loggers: `appLogger('billing.invoices')`.
Logger appLogger(String name) => Logger('varanasi.$name');

/// Configures `package:logging` once per app.
///
/// Every record is printed as one JSON line (same shape as the backend, ADR-0008 §11)
/// so browser-console logs can be searched by `correlation_id`. Debug builds log
/// everything; release builds log `INFO` and above. Never log tokens or personal data.
void setupLogging({required String appName, void Function(String line)? sink}) {
  final write = sink ?? debugPrint;
  hierarchicalLoggingEnabled = true;
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  Logger.root.clearListeners();
  Logger.root.onRecord.listen((record) {
    write(
      jsonEncode({
        'timestamp': record.time.toUtc().toIso8601String(),
        'level': record.level.name.toLowerCase(),
        'app': appName,
        'logger': record.loggerName,
        'event': record.message,
        if (record.error != null) 'error': record.error.toString(),
      }),
    );
  });
}
