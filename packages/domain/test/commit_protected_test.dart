import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:test/test.dart';

class _Files implements FileStore {
  final deleted = <String>[];

  @override
  Future<String> writeTemp(Uint8List bytes, String extension) async =>
      '/tmp/out.$extension';

  @override
  Future<String> commit(String tempPath, String extension) async =>
      'documents/x.$extension';

  @override
  String absolute(String relativePath) => '/app/$relativePath';

  @override
  Future<void> delete(String absoluteOrRelativePath) async =>
      deleted.add(absoluteOrRelativePath);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo implements DocumentRepository {
  final added = <Document>[];

  @override
  Future<Result<void>> add(Document document) async {
    added.add(document);
    return const Ok(null);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// PDFium stand-in: [code] is what opening without a password returns.
class _Pdf implements PdfEngine {
  _Pdf(this.code);
  final FailureCode? code;

  @override
  Future<Result<int>> pageCount(String path) async =>
      code == null ? const Ok(2) : Err(AppFailure(code!));

  @override
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  }) async => Err(AppFailure(code ?? FailureCode.corruptFile));

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Images implements ImageProcessor {
  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final pdfBytes = Uint8List.fromList('%PDF-1.7 encrypted'.codeUnits);

  CommitOutput commit(_Files files, _Repo repo, FailureCode? open) =>
      CommitOutput(
        files: files,
        repository: repo,
        pdf: _Pdf(open),
        images: _Images(),
      );

  test('commits a password-protected PDF that asks for its password', () async {
    final files = _Files();
    final repo = _Repo();
    final r = await commit(files, repo, FailureCode.passwordProtected)(
      OutputFile(
        bytes: pdfBytes,
        format: DocumentFormat.pdf,
        suggestedName: 'Tax (protected)',
        expectedPages: 3,
        passwordProtected: true,
      ),
    );
    expect(r.failureOrNull, isNull);
    expect(repo.added.single.pageCount, 3);
    expect(repo.added.single.thumbnailPath, isNull);
  });

  test('rejects a "protected" PDF that opens without a password', () async {
    final files = _Files();
    final r = await commit(files, _Repo(), null)(
      OutputFile(
        bytes: pdfBytes,
        format: DocumentFormat.pdf,
        suggestedName: 'x',
        passwordProtected: true,
      ),
    );
    expect(r.failureOrNull?.code, FailureCode.outputValidationFailed);
    expect(files.deleted, ['/tmp/out.pdf']);
  });

  test('rejects a protected output that PDFium cannot read', () async {
    final r = await commit(_Files(), _Repo(), FailureCode.corruptFile)(
      OutputFile(
        bytes: pdfBytes,
        format: DocumentFormat.pdf,
        suggestedName: 'x',
        passwordProtected: true,
      ),
    );
    expect(r.failureOrNull?.code, FailureCode.outputValidationFailed);
  });
}
