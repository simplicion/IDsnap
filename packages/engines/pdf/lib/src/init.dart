import 'package:pdfrx/pdfrx.dart';

/// Initializes PDFium for Flutter apps. Call once in `main()` before any
/// [PdfEngineImpl] read/render/manipulation call.
///
/// Pure-Dart hosts (CLI tools, `flutter test`) should call `pdfrxInitialize()`
/// from `package:pdfrx/pdfrx.dart` instead.
Future<void> initPdfEngine() => pdfrxFlutterInitialize();
