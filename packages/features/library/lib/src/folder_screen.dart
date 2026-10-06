import 'package:feature_library/src/document_browser.dart';
import 'package:flutter/material.dart';

/// One folder of the ID Vault, at any depth. Locked folders show their
/// contents only after unlocking.
class FolderScreen extends StatelessWidget {
  const FolderScreen({required this.folderId, super.key});

  final String folderId;

  @override
  Widget build(BuildContext context) =>
      VaultBrowser(key: ValueKey(folderId), folderId: folderId);
}
