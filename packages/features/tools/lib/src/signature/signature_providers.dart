import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/providers.dart' show noRetry;
import 'package:feature_tools/src/signature/signature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension _OrThrow<T> on Result<T> {
  T get orThrow => fold((v) => v, (f) => throw f);
}

/// Saved signatures live in `<app files>/signatures/` (PNG + JSON index).
/// Encrypted at rest with the vault cipher when the app wires one.
final signatureLibraryProvider = Provider<SignatureLibrary>(
  (ref) => FileSignatureLibrary(
    ref.watch(fileStoreProvider).absolute('signatures'),
    cipher: ref.watch(fileCipherProvider),
  ),
);

/// Newest first, default marked.
final savedSignaturesProvider =
    FutureProvider.autoDispose<List<SavedSignature>>(
      (ref) async => (await ref.watch(signatureLibraryProvider).list()).orThrow,
      retry: noRetry,
    );

/// PNG bytes of a saved signature.
final signaturePngProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, id) async =>
          (await ref.watch(signatureLibraryProvider).load(id)).orThrow,
      retry: noRetry,
    );

/// Displayed page sizes (points) of a PDF.
final pdfPageDimensionsProvider = FutureProvider.autoDispose
    .family<List<PdfPageDimensions>, String>(
      (ref, path) async =>
          (await ref.watch(pdfStamperProvider).pageDimensions(path)).orThrow,
      retry: noRetry,
    );

/// Large page render for placing stamps: `(path, pageIndex)`.
final pdfPagePreviewProvider = FutureProvider.autoDispose
    .family<Uint8List, (String, int)>((ref, key) async {
      final png = await ref
          .watch(pdfEngineProvider)
          .renderPage(key.$1, key.$2, targetWidth: 1100);
      return png.orThrow;
    }, retry: noRetry);
