import 'package:feature_library/src/document_browser.dart';
import 'package:feature_library/src/vault.dart';
import 'package:flutter/material.dart';

/// ID Vault tab: the user's top-level folders and loose files.
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) => const VaultBrowser(
    leading: SliverToBoxAdapter(
      child: Column(children: [PrivacyBanner(), SecureNotesEntry()]),
    ),
  );
}
