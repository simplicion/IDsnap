import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// "Add account": scan a QR code or type the key.
Future<void> showAddAccountSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.x2,
              ),
              child: Text('Add account', style: sheet.text.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('Scan QR code'),
              subtitle: const Text(
                'Use the camera, or pick a screenshot. Works offline.',
              ),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(context.push(Routes.authenticatorScan));
              },
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_rounded),
              title: const Text('Enter key manually'),
              subtitle: const Text('Type the setup key the website shows.'),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(context.push(Routes.authenticatorAdd));
              },
            ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
