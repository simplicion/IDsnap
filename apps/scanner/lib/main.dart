import 'package:docscan_scanner/app.dart';
import 'package:docscan_scanner/bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = await buildOverrides();
  runApp(ProviderScope(overrides: overrides, child: const DocScanApp()));
}
