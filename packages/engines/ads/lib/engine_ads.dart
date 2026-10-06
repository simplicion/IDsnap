/// Advertising engine (ADR-0013): Google Mobile Ads behind [AdsPlatform],
/// with consent-first start-up, test IDs outside release builds and a
/// frequency cap for interstitials. The only package that may link an ads
/// SDK; everything else talks to the `AdsService` port in docscan_contracts.
library;

export 'src/ads_config.dart';
export 'src/ads_engine.dart';
export 'src/ads_platform.dart';
export 'src/frequency_cap.dart';
export 'src/google_ads_platform.dart' show GoogleAdsPlatform;
