import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _Point = (IconData, String, String);

/// Plain-language privacy explanation. What it says about the internet
/// depends on how the build earns money: free with ads (ADR-0013) or a
/// paid licence (ADR-0012). Both texts must stay true to the code.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  /// Free build: the only network traffic is the ads SDK's.
  static const _adsPoints = <_Point>[
    (
      Icons.campaign_outlined,
      'Free, with ads from Google',
      'Your documents, IDs and codes never leave this phone. IDSnap is free and shows ads on '
          'a few screens; the ads are provided by Google, which may use your device’s '
          'advertising ID. IDSnap itself sends nothing over the internet: the only '
          'connections are made by Google’s advertising software (Google Mobile Ads) to load '
          'and measure ads. It can collect the advertising ID and other device identifiers, '
          'your approximate location (worked out from your IP address), which ads you saw or '
          'tapped, and diagnostic data such as crash and performance information. It has no '
          'access to your vault: no document, photo, recognised text, file name, note, '
          'authenticator secret or code is ever given to it.',
    ),
    (
      Icons.block_outlined,
      'Where ads never appear',
      'Ads show on Home, the Tools list, some tool screens and after a tool has finished '
          'and saved its result. There are never ads in your ID Vault, on any folder or '
          'document, in the Authenticator, in Secure notes, on lock screens, in the camera '
          'and scanning screens, on password or signature screens, or in Settings.',
    ),
    (
      Icons.tune_rounded,
      'Your ad choices',
      'Where the law asks for it (for example in the EEA, the UK and Switzerland), IDSnap '
          'asks for your choice before any ad is requested, and you can change it at any '
          'time in Settings → Ad privacy choices. If you don’t allow personalised ads, '
          'IDSnap asks Google for non-personalised ads only. You can also reset or delete '
          'your advertising ID in your phone’s settings (on Android: Settings → Privacy → '
          'Ads). On iPhone, IDSnap does not ask to track you and does not use the '
          'advertising identifier.',
    ),
  ];

  /// Paid builds: the only network traffic is the licence client's.
  static const _paidPoints = <_Point>[
    (
      Icons.wifi_rounded,
      'Internet: licence and payments only',
      'Your documents never leave this phone. IDSnap connects to the internet only to check '
          'your licence and for payments. The IDSnap licence server receives a scrambled '
          '(hashed) identifier of this phone — never the raw device ID — plus the platform '
          'and app version, and keeps your plan, its expiry and your payment sessions. '
          'Payments are made on the 180 Pay page in your browser: your card, UPI or bank '
          'details go to 180 Pay, never to IDSnap. 180 Pay tells the licence server the '
          'amount paid and, if you gave it one, your e-mail address (kept only to open the '
          'billing portal). With a valid licence IDSnap works fully offline. There are no ads.',
    ),
  ];

  static const _before = <_Point>[
    (
      Icons.person_off_outlined,
      'No account',
      'You never sign in. IDSnap has no user accounts and never asks for your name, phone '
          'number or contacts.',
    ),
    (
      Icons.cloud_off_rounded,
      'No uploads',
      'Scanning, filters, text recognition, PDF tools and conversions run on this device. '
          'Your documents are not uploaded anywhere.',
    ),
  ];

  static const _after = <_Point>[
    (
      Icons.enhanced_encryption_outlined,
      'Encrypted on this phone',
      'Your vault files, thumbnails, notes and database are encrypted on this phone (AES-256). '
          'The key is kept in the phone’s secure hardware-backed storage and never leaves it, '
          'so a phone backup can’t restore your vault to another phone. '
          'To move, use Settings → Your data → Export all data: one backup file with your '
          'documents, notes, authenticator accounts, signatures and settings, protected with a '
          'password you choose (AES-256).',
    ),
    (
      Icons.ios_share_rounded,
      'Sharing is your choice',
      'When you tap Share or Save to device, IDSnap makes an unencrypted copy and the file goes '
          'to the app you pick (email, chat, cloud drive). From then on, that app’s privacy rules '
          'apply. A full backup is encrypted with your password unless you switch that off; file '
          'and folder names in it stay readable.',
    ),
    (
      Icons.insights_outlined,
      'No content analytics',
      'IDSnap never collects document images, recognized text, file names or file contents, '
          'and contains no analytics or crash-reporting service of its own.',
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
  ];

  static const _controlFree = <_Point>[
    (
      Icons.delete_sweep_outlined,
      'You stay in control',
      'Delete any document, or use Settings → Storage → Erase everything to remove every '
          'document (also in locked folders), folder, note, authenticator account, signature, QR '
          'history entry, PIN and setting from this phone. '
          'Uninstalling the app removes all of its data.',
    ),
  ];

  static const _controlPaid = <_Point>[
    (
      Icons.delete_sweep_outlined,
      'You stay in control',
      'Delete any document, or use Settings → Storage → Erase everything to remove every '
          'document (also in locked folders), folder, note, authenticator account, signature, QR '
          'history entry, PIN and setting from this phone. Only your IDSnap Pro licence is kept. '
          'Uninstalling the app removes all of its data.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(monetizationModeProvider).showsAds;
    final points = [
      ..._before,
      ...ads ? _adsPoints : _paidPoints,
      ..._after,
      ...ads ? _controlFree : _controlPaid,
    ];
    return Scaffold(
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
            ads
                ? 'Everything you do with your documents happens on this '
                      'phone. Here is exactly what that means, including what '
                      'the ads on a few screens involve.'
                : 'IDSnap is built to work offline. Here is exactly what that '
                      'means, including the little it sends to check your '
                      'licence.',
            style: context.text.bodyLarge?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          const SizedBox(height: Space.x6),
          for (final (icon, title, body) in points)
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
}
