import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:meta/meta.dart';

/// How faithfully an output reproduces its source (PRD §8). Shown in the UI
/// next to every conversion so users know what to expect.
enum FidelityClass {
  visual(
    'Keeps appearance',
    'Pages are stored as images. Looks the same; text is not editable.',
  ),
  content(
    'Extracts content',
    'Text and data are kept; layout, fonts and images may change.',
  ),
  reconstructed(
    'Rebuilds layout',
    'Structure is inferred. Review the result before sharing.',
  ),
  native(
    'Format-aware',
    'Converted by a format-aware engine. Close, but not pixel-identical.',
  );

  const FidelityClass(this.label, this.explanation);
  final String label;
  final String explanation;
}

enum ConversionCategory {
  toPdf('Convert to PDF'),
  fromPdf('Convert from PDF'),
  images('Images'),
  text('Text & office');

  const ConversionCategory(this.label);
  final String label;
}

/// A supported source → destination pair, declared up front (PRD FR-09).
@immutable
class ConversionSpec {
  const ConversionSpec({
    required this.id,
    required this.title,
    required this.inputs,
    required this.output,
    required this.fidelity,
    required this.category,
    this.limitations = const [],
    this.multipleInputs = false,
    this.worksOffline = true,
  });

  final String id;
  final String title;
  final Set<DocumentFormat> inputs;
  final DocumentFormat output;
  final FidelityClass fidelity;
  final ConversionCategory category;
  final List<String> limitations;
  final bool multipleInputs;
  final bool worksOffline;
}

@immutable
class ConversionInput {
  const ConversionInput({
    required this.path,
    required this.name,
    required this.format,
  });

  /// Absolute path readable by the app.
  final String path;

  /// Display name without extension.
  final String name;
  final DocumentFormat format;
}

@immutable
class ConversionRequest {
  const ConversionRequest({
    required this.specId,
    required this.inputs,
    this.options = const {},
  });

  final String specId;
  final List<ConversionInput> inputs;

  /// Spec-specific options (e.g. `{'pageSize': 'a4'}`); unknown keys ignored.
  final Map<String, Object?> options;
}

/// One produced file, not yet committed to the library.
@immutable
class OutputFile {
  const OutputFile({
    required this.bytes,
    required this.format,
    required this.suggestedName,
    this.expectedPages,
    this.passwordProtected = false,
  });

  final Uint8List bytes;
  final DocumentFormat format;
  final String suggestedName;

  /// When set, validation checks the committed PDF has this many pages.
  final int? expectedPages;

  /// An encrypted PDF (Protect file). The producer already verified it by
  /// reopening it with the password; commit only checks that it is a PDF
  /// that asks for one, and records [expectedPages].
  final bool passwordProtected;
}
