import 'dart:async';

import 'package:docscan_contracts/src/entitlements.dart';
import 'package:docscan_contracts/src/monetization.dart';
import 'package:docscan_contracts/src/routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Providers ────────────────────────────────────────────────────────────────

/// Licensing. Overridden in apps/scanner/lib/bootstrap.dart with the
/// engine_billing adapter (or [FreeEntitlementService] in the free,
/// ad-supported build); unwired it unlocks everything (tests, tools).
final entitlementServiceProvider = Provider<EntitlementService>(
  (ref) => const StaticEntitlementService(),
);

/// The current entitlement (with the debug simulation applied). Always
/// [FreeEntitlement] when the build is free with ads, whatever the service
/// or the simulation say.
final entitlementProvider =
    NotifierProvider<EntitlementController, EntitlementState>(
      EntitlementController.new,
    );

/// Whether [ProFeature] is usable right now.
final canUseProvider = Provider.family<bool, ProFeature>(
  (ref, feature) => canUse(feature, ref.watch(entitlementProvider)),
);

class EntitlementController extends Notifier<EntitlementState> {
  @override
  EntitlementState build() {
    if (ref.watch(monetizationModeProvider).isFree) {
      return const FreeEntitlement();
    }
    final service = ref.watch(entitlementServiceProvider);
    final simulated = ref.watch(entitlementSimulationProvider);
    final sub = service.changes.listen((s) {
      if (ref.mounted) state = simulated?.state ?? s;
    });
    ref.onDispose(sub.cancel);
    return simulated?.state ?? service.current;
  }

  /// Re-reads the service (time-based changes such as the trial ending).
  void recheck() {
    if (ref.read(monetizationModeProvider).isFree) return;
    final simulated = ref.read(entitlementSimulationProvider);
    state = simulated?.state ?? ref.read(entitlementServiceProvider).current;
  }
}

// ── Debug / QA simulation (compiled out of release builds) ─────────────────

/// Simulated entitlement for QA, without the licence server.
///
/// Set at build time: `flutter run --dart-define=IDSNAP_SIMULATE_ENTITLEMENT=expired`
/// (trial, dayPass, monthly, expired, offlineNeverRegistered), or from
/// Settings › Subscription › Developer in debug/profile builds. Release
/// builds ignore both: every path is behind the `kReleaseMode` constant.
enum EntitlementSimulation {
  trial,
  dayPass,
  monthly,
  expired,
  offlineNeverRegistered;

  /// The simulated state, relative to the current time.
  EntitlementState get state {
    final now = DateTime.now();
    return switch (this) {
      trial => TrialEntitlement(endsAt: now.add(const Duration(hours: 5))),
      dayPass => DayPassEntitlement(
        expiresAt: now.add(const Duration(days: 2, hours: 3)),
      ),
      monthly => MonthlyEntitlement(
        renewsAt: now.add(const Duration(days: 20)),
        expiresAt: now.add(const Duration(days: 23)),
      ),
      expired => const ExpiredEntitlement(reason: LapseReason.trialEnded),
      offlineNeverRegistered => const ExpiredEntitlement(
        reason: LapseReason.notActivated,
      ),
    };
  }
}

const _simulationDefine = String.fromEnvironment('IDSNAP_SIMULATE_ENTITLEMENT');

final entitlementSimulationProvider =
    NotifierProvider<EntitlementSimulationController, EntitlementSimulation?>(
      EntitlementSimulationController.new,
    );

class EntitlementSimulationController extends Notifier<EntitlementSimulation?> {
  @override
  EntitlementSimulation? build() {
    if (kReleaseMode) return null;
    return EntitlementSimulation.values.asNameMap()[_simulationDefine];
  }

  /// No-op in release builds.
  void select(EntitlementSimulation? value) {
    if (kReleaseMode) return;
    state = value;
  }
}

// ── Gating ───────────────────────────────────────────────────────────────────

/// THE way to gate a Pro feature. Call it at the feature's entry point,
/// before navigating or starting work:
///
/// ```dart
/// onTap: () async {
///   if (!await ensurePro(context, ref, ProFeature.qrTools)) return;
///   if (context.mounted) unawaited(context.push(Routes.qrGenerator));
/// }
/// ```
///
/// Returns true immediately when the feature is free (see [featurePolicy]),
/// when the build is free with ads (always, and the paywall is never
/// opened), or when the user is entitled (trial or Pro). Otherwise opens
/// the paywall and
/// returns whether the user is entitled when it closes (bought or
/// restored). Needs a GoRouter above [context]; without one it returns
/// false for locked features.
Future<bool> ensurePro(
  BuildContext context,
  WidgetRef ref,
  ProFeature feature,
) async {
  if (!requiresPro(feature)) return true;
  if (ref.read(monetizationModeProvider).isFree) return true;
  ref.read(entitlementProvider.notifier).recheck();
  if (ref.read(canUseProvider(feature))) return true;
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  await router.push<bool>(Routes.paywall(feature: feature));
  if (!context.mounted) return false;
  final allowed = ref.read(canUseProvider(feature));
  return allowed;
}

/// [ensurePro], then push [location] if allowed. For tiles and buttons.
Future<void> pushIfPro(
  BuildContext context,
  WidgetRef ref,
  ProFeature feature,
  String location,
) async {
  if (!await ensurePro(context, ref, feature)) return;
  if (context.mounted) unawaited(GoRouter.of(context).push(location));
}

/// Label for `ToolTile.badge`: "Pro" when [feature] is locked, else null.
String? proBadgeLabel(WidgetRef ref, ProFeature feature) =>
    ref.watch(canUseProvider(feature)) ? null : 'Pro';

/// Small "PRO" marker shown next to a locked feature (nothing when the
/// feature is usable, e.g. during the trial).
class ProBadge extends ConsumerWidget {
  const ProBadge(this.feature, {super.key});

  final ProFeature feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(canUseProvider(feature))) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Pro feature',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_rounded,
              size: 12,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              'PRO',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Router backstop ─────────────────────────────────────────────────────────

/// The Pro feature behind an app location, or null for free locations.
/// Entry points call [ensurePro] first; the router uses this as a backstop
/// for every other way in (document shortcuts, deep links). Finishing a
/// scan already in progress (review/crop/save/resume) is never blocked.
ProFeature? proFeatureForLocation(Uri uri) {
  final s = uri.pathSegments;
  if (s.isEmpty) return null;
  if (s.first == 'scan') {
    if (s.length == 1) {
      return uri.queryParameters['source'] == ScanSource.resume.name
          ? null
          : ProFeature.scan;
    }
    return switch (s[1]) {
      'id-card' => ProFeature.idCard,
      'passport-photo' => ProFeature.passportPhoto,
      _ => null,
    };
  }
  if (s.first == 'tools' && s.length > 1) {
    // QR tool: scanning and history stay free; creating codes is Pro.
    if (s[1] == 'qr') {
      return s.length > 2 && s[2] == 'generate' ? ProFeature.qrTools : null;
    }
    final tool = ToolId.values.where((t) => t.path == s[1]).firstOrNull;
    return tool == null ? null : _toolFeatures[tool];
  }
  return null;
}

/// Tool → Pro feature. Tools not listed here stay free: removing a
/// password the user knows gives them back their own file, so
/// [ToolId.removePdfPassword] is deliberately absent.
const _toolFeatures = <ToolId, ProFeature>{
  ToolId.kits: ProFeature.kits,
  ToolId.ocr: ProFeature.ocr,
  ToolId.convert: ProFeature.convert,
  ToolId.signPdf: ProFeature.signature,
  ToolId.mySignature: ProFeature.signature,
  ToolId.imagesToPdf: ProFeature.pdfTools,
  ToolId.merge: ProFeature.pdfTools,
  ToolId.split: ProFeature.pdfTools,
  ToolId.organize: ProFeature.pdfTools,
  ToolId.compressPdf: ProFeature.pdfTools,
  ToolId.pdfToImages: ProFeature.pdfTools,
  ToolId.compressImage: ProFeature.imageTools,
  ToolId.photoCrop: ProFeature.imageTools,
  ToolId.resizeImage: ProFeature.imageTools,
  ToolId.protectFile: ProFeature.protectFile,
};

/// go_router redirect: sends a locked location to the paywall, which
/// continues to it after a purchase.
String? proRedirect(Uri uri, EntitlementState state) {
  final feature = proFeatureForLocation(uri);
  if (feature == null || canUse(feature, state)) return null;
  return Routes.paywall(feature: feature, from: uri.toString());
}
