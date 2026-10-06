import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// File reads and renders are deterministic — retrying a failure won't help
/// and would keep timers alive, so retries are disabled.
Duration? noRetry(int retryCount, Object error) => null;

extension _OrThrow<T> on Result<T> {
  T get orThrow => fold((v) => v, (f) => throw f);
}

/// Raw bytes of an app-readable file.
final fileBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, path) async => await ref.watch(fileStoreProvider).read(path),
  retry: noRetry,
);

final imageDetailsProvider = FutureProvider.autoDispose
    .family<ImageDetails, String>((ref, path) async {
      final bytes = await ref.watch(fileBytesProvider(path).future);
      final info = await ref.watch(imageProcessorProvider).inspect(bytes);
      return info.orThrow;
    }, retry: noRetry);

final pdfPageCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  path,
) async {
  final count = await ref.watch(pdfEngineProvider).pageCount(path);
  return count.orThrow;
}, retry: noRetry);

/// PNG thumbnail of one PDF page: `(path, pageIndex)`.
final pdfThumbProvider = FutureProvider.autoDispose
    .family<Uint8List, (String, int)>((ref, key) async {
      final png = await ref
          .watch(pdfEngineProvider)
          .renderPage(key.$1, key.$2, targetWidth: 320);
      return png.orThrow;
    }, retry: noRetry);

/// Conversion specs, empty when no engine is wired (e.g. in previews).
final conversionSpecsProvider = Provider<List<ConversionSpec>>((ref) {
  try {
    return ref.watch(conversionEngineProvider).specs;
  } on Object {
    return const [];
  }
});

final ocrCapabilityProvider = FutureProvider.autoDispose
    .family<EngineCapability, OcrScript>(
      (ref, script) async =>
          await ref.watch(textRecognizerProvider).capability(script),
      retry: noRetry,
    );

/// Pre-flight validation shared by every tool (production audit 2026-09).
final inspectInputProvider = Provider<InspectInput>(
  (ref) => InspectInput(
    files: ref.watch(fileStoreProvider),
    pdf: ref.watch(pdfEngineProvider),
  ),
);
