# ADR-0002: Use Riverpod 3 for state/DI and go_router for navigation

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
Features must use ports without knowing their implementations. Apps and tests must be able
to swap implementations. Navigation must support tabs that keep their state, deep links,
Android predictive back, and web URLs later.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **Riverpod 3** | DI + state in one tool, compile-safe, trivial overrides in tests | Learning curve |
| Bloc + get_it | Explicit events | Two libraries; a service locator hides dependencies |
| **go_router** | Official, deep links, `StatefulShellRoute` | Some boilerplate for nested navigators |
| auto_route | Typed routes | Codegen; third-party |

## Decision
- One `Provider` per domain port in `docscan_contracts`, which throws until the app
  overrides it in `bootstrap.dart`.
- Feature state uses `Notifier` / `AsyncNotifier` (no codegen, no legacy `StateProvider`).
- go_router with a `StatefulShellRoute.indexedStack` for the four tabs. Features export
  route builders that take the root navigator key, so detail screens cover the tab bar.
- The navigation contract is `Routes` + `ToolId` in `docscan_contracts`.

## Consequences
- Widget tests override ports with fakes (`ProviderScope(overrides: [...])`).
- Features stay decoupled: Home opens a tool with `context.push(Routes.tool(ToolId.merge))`.
