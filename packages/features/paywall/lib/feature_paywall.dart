/// IDSnap Pro: paywall (monthly or day pass via 180 Pay), Settings ›
/// Subscription and the subscription terms. Gating itself lives in
/// docscan_contracts (`ensurePro`, `ProBadge`).
library;

export 'src/copy.dart' show networkPrivacyLine;
export 'src/paywall_screen.dart'
    show PaywallScreen, dayPassPresets, pricingProvider;
export 'src/routes.dart';
export 'src/subscription_screen.dart'
    show SubscriptionScreen, describeSubscription;
export 'src/terms_screen.dart' show SubscriptionTermsScreen;
