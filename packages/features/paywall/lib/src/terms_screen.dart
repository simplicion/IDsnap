import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_paywall/src/copy.dart';
import 'package:flutter/material.dart';

/// Subscription terms and the licensing privacy notice, shown in the app
/// (no web page needed offline).
class SubscriptionTermsScreen extends StatelessWidget {
  const SubscriptionTermsScreen({super.key});

  static const sections = <(String, String)>[
    (
      'Free day',
      'IDSnap includes every feature free for 24 hours, starting the first '
          'time this phone connects to the IDSnap licence server. No account '
          'or card is needed and nothing is charged when it ends. There is '
          'one free day per phone: reinstalling the app does not start a new '
          'one.',
    ),
    (
      'Plans',
      'Monthly: a subscription that renews every month until you cancel. '
          'Day pass: a single payment for the number of days you choose; it '
          'ends by itself and never renews. Days you buy are added after '
          'any paid time you already have. The amount is computed by the '
          'IDSnap server and shown on the $paymentProvider page before you '
          'pay.',
    ),
    (
      'Payment',
      'Payments are handled by $paymentProvider, in your browser. IDSnap '
          'never sees or stores your card, UPI or bank details. Your '
          'licence is unlocked only after $paymentProvider confirms the '
          'payment to the IDSnap server.',
    ),
    (
      'Cancelling and refunds',
      'Cancel the monthly plan any time: $cancelHowTo. Everything stays '
          'unlocked until the end of the period you paid for. Refund '
          'requests are handled through $paymentProvider and IDSnap support.',
    ),
    (
      'Working offline',
      'Once your free day or plan is active, IDSnap works fully offline '
          'until it ends. It needs the internet only to start the free day, '
          'to pay, and to refresh the licence. Setting the phone’s date back '
          'pauses the licence until the correct date is restored.',
    ),
    (
      'What stays free',
      'Opening, viewing, sharing and exporting your documents, browsing '
          'folders, unlocking the app and locked folders, reading your '
          'notes, exporting all your data, and the Authenticator (viewing, '
          'copying and adding sign-in codes) never need a plan.',
    ),
    (
      'Privacy',
      '$networkPrivacyLine The IDSnap licence server receives only a '
          'scrambled (hashed) identifier of this phone — never the raw '
          'device ID — plus the platform and app version, and keeps your '
          'plan, its expiry and your payment sessions. $paymentProvider '
          'tells it the amount paid and, when you give one to '
          '$paymentProvider, your e-mail address (kept only to open the '
          'billing portal). No documents, file names, contacts or location '
          'are ever sent.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Subscription terms')),
    body: ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        for (final (title, body) in sections) ...[
          Semantics(
            header: true,
            child: Text(title, style: context.text.titleMedium),
          ),
          const SizedBox(height: Space.x1),
          Text(body, style: context.text.bodyMedium),
          const SizedBox(height: Space.x5),
        ],
      ],
    ),
  );
}
