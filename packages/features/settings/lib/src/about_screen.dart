import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';

/// App version, principles and open-source licenses.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.version = '0.1.0'});

  final String version;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.x4),
        const Center(
          child: IconBadge(Icons.document_scanner_rounded, size: 88),
        ),
        const SizedBox(height: Space.x4),
        Center(child: Text('DocScan', style: context.text.headlineSmall)),
        Center(
          child: Text(
            'Version $version',
            style: context.text.bodyMedium?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: Space.x3),
        const Center(child: OfflineBadge()),
        const SizedBox(height: Space.x6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Text(
              'Scan, organize and convert documents privately on your phone. '
              'No account, no uploads, and the essential tools are free.',
              style: context.text.bodyLarge,
            ),
          ),
        ),
        const SizedBox(height: Space.x4),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.menu_book_outlined),
                title: Text('Documentation'),
                subtitle: Text(
                  'Guides and format support are in the DocScan docs app',
                ),
              ),
              const Divider(indent: Space.x4, endIndent: Space.x4),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('Open-source licenses'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'DocScan',
                  applicationVersion: version,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
