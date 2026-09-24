import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';

/// Plain-language privacy explanation.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _points = <(IconData, String, String)>[
    (
      Icons.person_off_outlined,
      'No account',
      'You never sign in. DocScan has no user accounts and no servers that know who you are.',
    ),
    (
      Icons.cloud_off_rounded,
      'No uploads',
      'Scanning, filters, text recognition, PDF tools and conversions run on this device. '
          'Your documents are not uploaded anywhere.',
    ),
    (
      Icons.ios_share_rounded,
      'Sharing is your choice',
      'When you tap Share, the file goes to the app you pick (email, chat, cloud drive). '
          'From then on, that app’s privacy rules apply.',
    ),
    (
      Icons.insights_outlined,
      'No content analytics',
      'We never collect document images, recognized text, file names or file contents.',
    ),
    (
      Icons.download_for_offline_outlined,
      'System components',
      'On some Android phones the camera scanner module is provided by Google Play services and may be '
          'downloaded once by the system. Your documents are still processed on the device.',
    ),
    (
      Icons.gavel_outlined,
      'Not a certified copy',
      'A scan is a convenient digital copy. It is not legally certified and does not replace an '
          'official original unless the receiving organization accepts it.',
    ),
    (
      Icons.delete_sweep_outlined,
      'You stay in control',
      'Delete any document, or everything at once from Settings → Storage. '
          'Uninstalling the app removes all of its data.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy')),
    body: ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        Text(
          'Your documents stay on your phone',
          style: context.text.headlineSmall,
        ),
        const SizedBox(height: Space.x2),
        Text(
          'DocScan is built to work offline. Here is exactly what that means.',
          style: context.text.bodyLarge?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
        const SizedBox(height: Space.x6),
        for (final (icon, title, body) in _points)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon, size: 40),
                const SizedBox(width: Space.x4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: context.text.titleMedium),
                      ),
                      const SizedBox(height: Space.x1),
                      Text(body, style: context.text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
