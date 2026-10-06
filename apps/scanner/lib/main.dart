import 'package:docscan_scanner/app_info.dart';
import 'package:docscan_scanner/error_reporting.dart';
import 'package:docscan_scanner/vault_startup.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything can fail: local-only error logging and a friendly error
  // widget in release builds (audit H-08).
  installErrorHandlers();
  configureSupportContact();
  // startApp catches every startup failure and shows a recovery screen.
  await startApp();
}
