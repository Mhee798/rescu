# Rescu — solutions

Working notes for the assessment. Written as the work happens; sections for
tickets not yet started say so rather than being pre-filled.

Status legend: `not started` · `investigating` · `fixed` · `partial` · `not attempted`

---

## Environment

Everything below was verified on 2026-09-12, not assumed.

| | |
|---|---|
| Flutter | **3.27.0** via fvm (`.fvmrc`) — `fvm flutter` for every command |
| Dart VM of the running app | 3.6.0 (stable), `android_arm64` — confirmed via `getVM` on the live VM service |
| Test device | PTP N49 · **SoC SM8750** · Android 16 (API 36) |
| Baselines | `docs/baseline/flutter-analyze.txt` (no issues), `docs/baseline/flutter-test.txt` (1/1 pass), `docs/baseline/home-first-run.png` |

**Caveat that matters for RES-105.** `SM8750` is a Snapdragon 8 Elite — flagship
class, not the "mid-range Android" the ticket describes. Frame drops may be
weaker here or absent; the memory growth should still reproduce since that is a
retention problem rather than a throughput one. All performance numbers in this
file state the device they came from, and no claim is made that they generalise
to the hardware in the ticket.

There is a second Flutter (3.47.2) first on `PATH` at
`~/Documents/flutter`. It is not used for anything here.

**RES-105 "before" numbers must be measured from the step-0 baseline commit**
(`git checkout <baseline sha>` → `fvm flutter run --profile`), not from whatever
`HEAD` is at the time. RES-104 touches the home controller and would otherwise
contaminate the comparison.

---

## Part A — bugs

## RES-101 · Search shows results for the wrong query
**Status** not started

**Symptom** Typing quickly in search settles on results for an earlier, shorter query.

**Root cause** —
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## RES-102 · Crash after leaving My orders
**Status** not started

**Symptom** `setState() called after dispose()` a couple of seconds after navigating back from My orders.

**Root cause** —
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## RES-103 · Requests pile up the longer you browse
**Status** not started

**Symptom** Each "Add to bag" fires one `GET /deals/:id` per deal viewed earlier in the session.

**Root cause** —
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## RES-104 · Duplicate deals in the home feed
**Status** not started

**Symptom** Pull-to-refresh while the next page is still loading intermittently yields duplicate cards, or more items than the catalog holds.

**Root cause** —
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## RES-105 · Home feed is janky and memory keeps climbing
**Status** not started

**Symptom** Dropped frames while scrolling; memory grows until the OS kills the app. The ticket states there is more than one contributing cause.

**Root cause** — *(expected to be a list, one entry per cause, each with its own attributed improvement)*
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** — *(profile mode only; device, scenario, before/after)*

## RES-106 · Wrong pickup times; "Pickup today" filter misses deals
**Status** not started

**Symptom** A bakery open 06:00–09:30 renders "Pick up 23:00 – 02:30"; stores with slots today are missed by the **Pickup today** filter.

**Root cause** — not established. `lib/model/pickup_window_model.dart` was read
during orientation and is the obvious first place to look, but nothing has been
reproduced or confirmed yet, so no cause is claimed here.
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## RES-107 · Deep link opens to a crash
**Status** fixed — reproduced, fixed, re-verified on device

**Symptom** `rescu://open/deal?id=42&source=push` crashes with `type 'Null' is not a subtype of type 'DealModel'`. The same deal opens fine from the home feed. A fallback/error screen is explicitly not an acceptable resolution.

**Root cause** `DealDetailsController.onInit` obtains the deal exclusively from the
navigation payload — `deal = Get.arguments as DealModel` — and never reads the
`id` that the route already carries. Both feed entry points
(`deal_card.dart:24`, `flash_deals_section.dart:50`) call `Get.toNamed(..., arguments: deal)`
and so hand over a fully built model; the deep-link entry point
(`home_screen.dart:135`) calls `Get.toNamed(route)` with no arguments. On that
path `Get.arguments` is `null` and the cast throws. The controller is therefore
only constructible from a caller that already holds a `DealModel`, which a deep
link by definition does not.

`deal_details_controller.dart:28` is the **only** cast to `DealModel` anywhere in
`lib/` (`grep -rn "as DealModel" lib/` → 1 hit), so the runtime message pins the
throw site without needing a stack frame.

**Fix** The controller now obtains the deal from whichever source the entry
point actually has, instead of assuming one of them.
`Get.arguments is DealModel` → adopt it synchronously; otherwise parse
`Get.parameters['id']` and `dealRepo.fetchById`. `late final DealModel deal`
became `Rxn<DealModel>` with a nullable getter, and the screen renders content /
error / spinner off that.

Three details are load-bearing rather than incidental:

- **Keeping `late final` would have moved the crash, not removed it.** Any read
  before an async assignment throws `LateInitializationError` — a different
  failure, in whatever reads first rather than in `onInit`. The field had to
  become genuinely optional for the async path to be expressible at all.
- **The `ever(cartService.itemCount, …)` worker moved into `_watchCart()`,
  called only from `_adopt()`.** Its callback reads the deal's id, so
  subscribing in `onInit` as before would let a cart change *during* the
  deep-link fetch reach a deal that does not exist yet. It is also guarded
  against a second registration so `retry()` cannot leave two subscriptions —
  which would have quietly made RES-103 worse via this fix.
- **The add-to-bag button is not rendered while the deal is absent**, via its
  own `Obx` on `bottomSheet`. Guarding only the controller would have left a
  live button on screen during the fetch window.

The fast path is unchanged in behaviour: `_adopt` runs synchronously inside
`onInit`, so a tap from the feed still has its deal before the first build and
gains no loading frame.

**Alternative rejected** *Always fetch by id and ignore `Get.arguments`.* One
code path instead of two, and always-fresh stock. Rejected because it adds a
network round trip and a spinner to the path the ticket explicitly says already
works, to fix a path that does not — paying a regression on the common case for
the rare one. The `quantityLeft` re-check already covers staleness on the fast
path.

Also rejected, and worth naming because it is the quickest edit: making the cast
`Get.arguments as DealModel?` and rendering a "deal unavailable" screen when it
is null. That compiles and stops the crash, but the deep link would still never
show deal 42 — the ticket's requirement is a fully working page, and an error
screen is explicitly not an acceptable resolution.

**Edge cases**
- *Unknown or non-numeric id.* `getDealById` (`fake_api_service.dart:82-90`)
  has **no injected flakiness at all** — unlike `reserveDeal` and `checkout`,
  which fail on `_mutationCounter % 5 == 3`, it does latency and then either
  returns the deal or throws a deterministic 404 for an id not in the catalog.
  So the failure state is structurally *unreachable for any deal that exists*:
  deal 42 renders the real page, always, and the error screen is reachable only
  for input naming nothing. That is what keeps it on the right side of the line
  the ticket draws, rather than merely "we handle errors nicely".
  The honest caveat: the generic `catch` branch means a future non-404 failure,
  or a `DealModel.fromJson` throw on malformed data, *would* route a valid deal
  there. That branch is defence in depth, not the ticket's answer, and the Try
  again button is what stops it being terminal.
- *Transient failure.* Non-404 failures get a retryable message rather than the
  404 wording, since the deal may well exist.
- *Back pressed while the deep-link fetch is in flight.* The fetch cannot be
  cancelled, so it completes on a controller GetX has already disposed
  (`SmartManagement.full` is the default — `get_interface.dart:10`). Without a
  guard, `_adopt` would then subscribe a screen the user cancelled to the
  session-long `CartService`. Measured with temporary lifecycle logging: with a
  back press ~100ms after the push, `onClose` precedes the response in 6 runs
  out of 6; with a back press at ~250ms the response wins and the worker is
  registered legitimately. `_adopt` therefore returns early on `isClosed`.
  Verified end to end: after aborting a deep link to deal 42, a later add-to-bag
  re-checks only the deal actually viewed.
- *`Get.parameters` read after an await.* `source` and `id` are captured in
  `onInit` rather than read inside `_adopt`, which on the deep-link path now
  runs after the fetch. `Get.parameters` is global navigation state that the
  next push replaces, so reading it late could attribute the impression to
  another route's source.
- *Try again tapped twice.* `_loadFromRoute` returns early while a fetch is in
  flight, so a double tap cannot log `deal_details_view` twice. The id parse is
  synchronous, so the flag is always set before the first await.
- *No way out of the non-content states.* The back arrow on the loaded screen
  comes from `SliverAppBar`, which the loading and failure states do not have —
  the failure state was a screen a user could be parked on with no exit. Both
  now render a back affordance, shown only when `Navigator.canPop()`, mirroring
  what `AppBar` does rather than adding a button that does nothing.
- **Not handled, deliberately:** the `ever` worker is stored in `_cartWorker`
  but never disposed. That is RES-103's cause and fixing it here would fold two
  tickets into one commit. This change moves the registration; it deliberately
  does not change its lifetime.
- **Not handled, deliberately:** a deep link fired while the app is already
  top-most in the foreground still does nothing (Path 4 above). It is an
  `am start` artefact rather than a user flow.

**Evidence** Reproduced on PTP N49 (Android 16), debug build, 2026-09-12 17:03–17:07.

*Path 1 — adb cold start (app not running):*
```
adb shell am force-stop dev.rescu.rescu
adb shell "am start -a android.intent.action.VIEW \
  -d 'rescu://open/deal?id=42&source=push' dev.rescu.rescu"
```
Red `ErrorWidget`: `type 'Null' is not a subtype of type 'DealModel' in type cast`.
Screenshot: `docs/res-107/01-cold-start-crash.png`.
logcat confirms the route was entered before the throw:
`I/flutter: [rescu 17:03:55.641] analytics: screen_view {screen: /deal}`.

*Path 2 — in-app simulator (app already running):* Home → ⋮ → Simulate deep link…
→ Open, with the prefilled `rescu://open/deal?id=42&source=push`. Same crash.
Screenshot: `docs/res-107/02-in-app-dialog-crash.png`.

*Path 3 — adb warm start, app backgrounded (home button pressed first):*
`Warning: Activity not started, its current task has been brought to the front`,
then `analytics: screen_view {screen: /deal}` and the same crash. So resuming
from the background routes correctly and hits the same cast.

*Path 4 — adb warm start, app already top-most in the foreground:* the platform
reports `intent has been delivered to currently running top-most instance`, but
the app neither navigates nor crashes — it stays on Home, and no `screen_view`
is logged, so the route was never pushed.

Three of the four paths crash. Path 4 is the only one that does not route, and
it is an artefact of driving the app with `am start` rather than a user flow: a
push-notification tap necessarily resumes the app from the background or a cold
start, which is Path 3 or Path 1. It is therefore **not** treated as a second
defect in scope for this ticket — see "Edge cases" once the fix lands, and the
finding below.

**After the fix** — re-verified on the same device, 17:30–17:32.

| Path | Before | After |
|---|---|---|
| adb cold start | red `ErrorWidget` | deal 42 "Mystery Japanese Basket" renders in full |
| adb warm start, backgrounded | red `ErrorWidget` | same, renders in full |
| in-app simulator dialog | red `ErrorWidget` | same, renders in full |
| tap from home feed | worked | still works, no loading frame |
| adb warm start, already top-most | nothing happens | unchanged (out of scope) |
| `?id=999` (not in catalog) | n/a | message + Try again, no crash |

Console on the deep-link path, showing the id being fetched and `source`
surviving into analytics:
```
[rescu 17:31:34.584] analytics: screen_view {screen: /deal}
[rescu 17:31:34.931] GET /deals/42
[rescu 17:31:34.941] analytics: deal_details_view {deal_id: 42, source: push}
```
Add to bag on the deep-linked page fires the availability re-check exactly once
for deal 42 — no duplicate subscription. (It also fires once for deal 1, viewed
earlier in the same session: that is RES-103 reproducing incidentally, and is
left alone here.)

Screenshots: `docs/res-107/03-cold-start-fixed.png`,
`docs/res-107/04-unknown-id-error-state.png`.
`fvm flutter analyze` clean, `fvm flutter test` 1/1.

*Where the platform route enters the app.* There is no deep-link code in this
repo at all — `MainActivity` is a bare `FlutterActivity`, and `grep -rn
"onNewIntent\|didPushRoute\|onGenerateRoute" lib/ android/` returns nothing.
Routing comes entirely from `flutter_deeplinking_enabled` in the manifest plus
the framework: `GetMaterialApp`'s default constructor sets `routerDelegate =
null` (`get_material_app.dart:127`) and builds a plain `MaterialApp` with
`onGenerateRoute: generator` (`:279`), so `WidgetsApp._usesRouterWithDelegates`
is false and `didPushRouteInformation` (`flutter/lib/src/widgets/app.dart:1549`)
falls through to `navigator.pushNamed(uri)`. That is why the platform route
reaches `/deal` with `id` and `source` intact as `Get.parameters`, and why
`Get.arguments` is null: the framework pushes a *name*, never an argument
object. Nothing on the platform side is misconfigured.

---

## Part B — features

## F-1 · Live flash-sale countdowns
**Status** not started

**Requirement** `mm:ss` / `hh:mm:ss` countdown in flash rail, feed cards and details; expiry disables the card and evicts it from the bag with a visible notice; per-second rebuilds scoped to the changing `Text` only, proven with Track Widget Builds.

**Design** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## F-2 · Impression tracking
**Status** not started

**Requirement** `deal_impression` at ≥50% visible for ≥1 continuous second, once per deal per app session across all screens, batched at 10 events or 15s since the first unsent event, no scroll regression.

**Design** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## F-3 · Stock reservations with optimistic UI
**Status** not started

**Requirement** Optimistic add with rollback on failure, per-line remaining hold, release/adjust on removal, reservation ids at checkout, graceful `410`.

**Deliberately underspecified — expiry while the user is in the app.** Options
will be laid out with a recommendation rather than one being chosen silently.

**Design** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

---

## AI usage log

Full running log: [`docs/ai-log.md`](docs/ai-log.md), appended to during the work.
The two strongest entries get lifted here once they exist.

**Tools used** — Claude Code (Opus 5) in the terminal, driving the repo and the
live device.

*(No entries yet — nothing has been suggested and rejected so far beyond
ordering decisions.)*

---

## Design questions

**Q1 — `GetxController` lifecycle vs widget `State` lifecycle; one Part A bug caused by confusing them.**
—

**Q2 — When does wrapping a large subtree in a single `Obx` hurt, and how do you scope reactivity?**
—

**Q3 — An automated test that would have caught RES-106, and what would have to change to make it possible.**
—

---

## Time spent

Running log in [`docs/ai-log.md`](docs/ai-log.md).

| Date | Span | On |
|---|---|---|
| 2026-09-12 | ~16:10– | Orientation, environment verification, baselines, scaffolding |

**Total so far** — ~0.3 h

**With one more day** — *(to be written at the end, honestly)*
