/// IDSnap licensing.
///
/// SWITCHED OFF in the default build: IDSnap is free with ads
/// (`IDSNAP_MONETIZATION=ads`, docs/adr/0013-free-with-ads.md) and nothing
/// in this package is constructed. It is kept, tested, for the paid modes:
///
/// `IDSNAP_MONETIZATION=licence`: licence tokens from the IDSnap licence
/// server, paid through 180 Pay, verified offline (`LicenceEngine`,
/// docs/adr/0012-180pay-licence-server.md). The licence client here is
/// the only network code written for the app.
///
/// `IDSNAP_MONETIZATION=store`: Google Play Billing / StoreKit through
/// `in_app_purchase` with a local trial (`BillingEngine`, ADR-0009).
library;

export 'package:engine_license/engine_license.dart'
    show DevLicenceKeys, LicenceVerifier, hashDeviceId, isDevLicencePublicKey;

export 'src/billing_engine.dart';
export 'src/billing_storage.dart';
export 'src/billing_store.dart';
export 'src/entitlement_cache.dart' show CachedEntitlement, CachedKind;
export 'src/in_app_purchase_store.dart';
export 'src/licence/device_identity.dart';
export 'src/licence/licence_client.dart';
export 'src/licence/licence_config.dart';
export 'src/licence/licence_engine.dart';
export 'src/model.dart';
export 'src/play_signature.dart';
export 'src/resolver.dart';
export 'src/trial.dart';
