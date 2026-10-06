import 'dart:convert';
import 'dart:io';

import 'package:license_server/license_server.dart';

/// Creates the monthly plan at 180 Pay with the documented API:
///
///     POST {ONE_EIGHTY_CORE_URL}/api/v1/subscriptions/plans
///     Authorization: Bearer <client_secret>
///
/// Run once per environment, with the same environment variables as the
/// server:
///
///     dart run tool/create_plan.dart            # asks before sending
///     dart run tool/create_plan.dart --yes      # no prompt (CI)
///
/// The plan can also be created by hand in the 180 Developer Console
/// (Pricing Tables); the plan code must equal MONTHLY_PLAN_CODE.
Future<void> main(List<String> args) async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnv(Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
    return;
  }
  final plan = monthlyPlan(config);
  stdout.writeln(
    'About to create plan "${plan.planCode}" at ${config.coreUrl.host}: '
    '${majorUnits(plan.amountCents)} ${plan.currency} every '
    '${plan.intervalCount} ${plan.interval}.',
  );
  if (!args.contains('--yes')) {
    stdout.write('Send this to the LIVE 180 Pay API? [y/N] ');
    if (stdin.readLineSync()?.trim().toLowerCase() != 'y') {
      stdout.writeln('Cancelled.');
      return;
    }
  }
  exitCode = await createMonthlyPlan(
    config: config,
    gateway: OneEightyPayGateway(config),
    out: stdout.writeln,
  );
}

/// The monthly plan this server sells, from its configuration.
PlanDefinition monthlyPlan(ServerConfig config) => PlanDefinition(
  planCode: config.monthlyPlanCode,
  name: '${config.appName} Monthly',
  description:
      'All ${config.appName} features on one device. Renews every month '
      'until cancelled.',
  amountCents: config.monthPriceCents,
  currency: config.currency,
  metadata: {'app': config.appName.toLowerCase(), 'product': 'monthly'},
);

/// Sends the plan and reports the outcome. Returns a process exit code.
Future<int> createMonthlyPlan({
  required ServerConfig config,
  required PayGateway gateway,
  required void Function(String line) out,
}) async {
  final PlanResult result;
  try {
    result = await gateway.createPlan(monthlyPlan(config));
  } on GatewayException catch (e) {
    out('Failed: ${e.message}');
    return 1;
  }
  out('HTTP ${result.statusCode}');
  if (result.body != null) {
    out(const JsonEncoder.withIndent('  ').convert(result.body));
  }
  out(
    result.ok
        ? 'Plan created. Keep MONTHLY_PLAN_CODE=${config.monthlyPlanCode}.'
        : 'The gateway refused the plan (it may already exist).',
  );
  return result.ok ? 0 : 1;
}
