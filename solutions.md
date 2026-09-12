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
**Status** fixed — reproduced, fixed, covered by a widget test, re-verified on device

**Symptom** `setState() called after dispose()` a couple of seconds after navigating back from My orders.

**Root cause** `_PickupCountdownState.initState` starts a
`Timer.periodic(const Duration(seconds: 1), …)` whose handle is discarded, and
the class has no `dispose()` at all. The timer therefore outlives the widget:
after the route pops, its callback keeps calling `setState` on a State that
Flutter has already marked defunct.

It is one timer **per card**, not one per screen. `orders_screen.dart:95` renders
a `PickupCountdown` for every *active* order, and the seed data has three
(`9001 READY`, `9002 CONFIRMED`, `9003 CONFIRMED`), so a single visit leaks three
timers and each one throws separately, once a second, for the rest of the
session.

**Fix** Keep the handle in a `Timer? _ticker` and cancel it in a `dispose()`
override. That is the whole fix: the cause is an uncancelled timer, so the fix
cancels the timer.

**Alternative rejected** *Guard the callback with `if (mounted) setState(…)`.*
This is the quickest edit and it does stop the exception, which is exactly why it
is worth naming: the timer still runs every second for the lifetime of the app,
still holds a reference to a dead `State`, and still wakes the isolate. It
converts a loud crash into a silent leak — the symptom disappears and the cause
is untouched. With three cards per visit and repeated navigation the leak
compounds.

**Edge cases**
- *A countdown that reaches zero* still renders "Pickup window is open" and keeps
  ticking. Stopping the timer at zero would be a small optimisation, but the
  window can also be entered while the screen is open and the label has to change
  then, so the timer has to keep running. Unchanged.
- *Only one `StatefulWidget` in the app.* Checked rather than assumed:
  `grep -rln StatefulWidget lib/` returns this file alone, and `Timer` appears
  nowhere else outside the fake backend. There is no sibling instance of this bug
  to chase.
- *Per-second `setState(() {})` rebuilds the whole countdown widget*, which is
  acceptable for a small row but is precisely what **F-1** must not do at feed
  scale. This widget is the template F-1 replaces, and the requirement there is
  that only the changing `Text` rebuilds.

**Evidence** Reproduced on PTP N49 over USB, 2026-09-12 20:25. Opened My orders
(three active cards, countdowns reading 17:49 / 46:49 / 2h 11m), pressed back,
and logcat produced **three** separate unhandled exceptions within seconds — one
per card, from three distinct State objects:

```
setState() called after dispose(): _PickupCountdownState#d0855 (defunct, not mounted)
setState() called after dispose(): _PickupCountdownState#f20d8 (defunct, not mounted)
setState() called after dispose(): _PickupCountdownState#84813 (defunct, not mounted)
  #2  _PickupCountdownState.initState.<anonymous closure> (pickup_countdown.dart:22:7)
  #3  _Timer._runTimers
```

`test/pickup_countdown_test.dart` covers it without a device.
`flutter_test` asserts its own invariant — *"A Timer is still pending even after
the widget tree was disposed"* — so the disposal test needs no assertion of its
own. Run against the unfixed widget, **all five cases fail**, because every test
that mounts this widget leaves a timer pending at teardown. After the fix the
suite is 15/15.

Re-verified on device: countdowns tick (16:54 → 16:50 and 45:54 → 45:50 across a
four-second sample, so the fix did not freeze the feature), and navigating in and
out of My orders five times — fifteen timers created and discarded — produced
**zero** `setState() called after dispose()` and zero unhandled exceptions.

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
**Status** fixed — reproduced by test and on device, fixed, re-verified

**Symptom** A bakery open 06:00–09:30 renders "Pick up 23:00 – 02:30"; stores with slots today are missed by the **Pickup today** filter.

**Root cause** The backend team is right: the API is correct.
`_pickupWindowFor` builds each window on the market wall clock
(`_marketUtcOffsetHours = 7`) and serialises the resulting **instants** as
ISO-8601 `Z` strings. The client then treats those instants as if they were
already wall-clock times. Two distinct consequences from one mistake, both in
`lib/model/pickup_window_model.dart`:

- **`label`** — `DateTime.parse` of a `Z` string returns a `DateTime` with
  `isUtc == true`, and `DateFormat.format` reads that object's `.hour`/`.minute`
  fields rather than converting zones. So the screen printed the UTC clock. 06:00
  market time is 23:00Z the previous day, which is exactly the string in the
  ticket.
- **`isToday`** — `start.day == DateTime.now().day` compared a **UTC** day
  number against a **local** one, and compared only `.day`, ignoring month and
  year. Both halves are wrong independently: the zone mismatch drops windows
  that straddle midnight UTC (precisely the morning windows users complained
  about), and the missing month/year means the same date one month apart counts
  as "today".

**Fix** `.toLocal()` before formatting, and a full year/month/day comparison for
the day check. The day check moved into `isTodayAt(DateTime now)` with `isToday`
delegating to it, because the model called `DateTime.now()` internally and so
could not be covered by a test at all — see Q3.

`label` and `isToday` both use the local zone now, **but for different reasons,
and they would diverge under a better API.** `label` answers "what time does
this store open?", a property of the store, ideally rendered in the store's own
zone. `isToday` answers "can I collect this today?", a property of the *user's*
calendar day, which stays device-local under any design. Treating them as one
fix would be the naive reading.

**Alternative rejected (test seam)** *Test `isToday` directly by building a
window relative to `DateTime.now()` and skipping the extra method.* Rejected
because the assertion would then straddle local midnight and go flaky for the
run that happens to cross it — a test that fails once a day at 00:00 gets
deleted, not fixed. Injecting a clock into the model was also rejected: GetX does
not inject into hand-written models here, and a static overridable `now` hook is
global mutable state that leaks between tests.

**Alternative rejected** *Hardcode `+7` in the client to match
`_marketUtcOffsetHours`.* It reproduces the backend's own conversion and is right
for the 27 Bangkok stores. Rejected because it copies a backend business constant
the API never sends — the contract is instants, and the only zone a client
legitimately owns is the device's. It is wrong for the 3 Hong Kong stores today
and silently wrong for any market added later, and it fails in the same "user
travelled" case that `.toLocal()` is accused of failing, while also failing when
they have not.

**Edge cases**
- *Not fixable from the client, and logged rather than worked around:* the
  catalog is **not single-market**. 27 of 30 stores are THB/Bangkok; stores 28,
  29 and 30 are HKD with Hong Kong addresses (Hennessy Road, lat ~22.3 / lng
  ~114.16). No store carries a timezone field, and `_pickupWindowFor` applies the
  `+7` market offset to those three as well, so their windows are constructed on
  the wrong market's wall clock before they ever reach the app. **No client-side
  choice renders them correctly** — the fix for those is a per-store zone in the
  API and a market offset that is not global, both of which live in
  `fake_api_service.dart`, which is out of bounds. `.toLocal()` is correct for the
  ticket's complaint and for 27 of 30 stores; for the other 3 it is wrong, and so
  is every alternative.
- *Deliberately not touched, having checked them:* `isOpenNow` and `untilStart`
  compare and subtract `DateTime`s, which operate on instants regardless of the
  UTC flag, so they were already correct. The same applies to
  `OrderModel.pickupStart/pickupEnd`, whose only consumer is `PickupCountdown`
  (`orders_screen.dart:95`) doing `.difference(DateTime.now())`. Patching those
  for symmetry would have been churn.
- *Overnight windows, logged not fixed.* A 22:00–01:00 window renders
  end-before-start. This is **9 of the 30 stores** — Chao Phraya Sushi
  22:00–01:00, Green Mango Deli 21:30–00:30, Siam Patisserie 23:00–02:00 and six
  more — so 30% of the catalog, not an edge case, and I should not have waved it
  through as one. The instants are right: `_pickupWindowFor` rolls the end past
  midnight deliberately (`endMarket.add(days: 1)`). What is ambiguous is the
  *rendering*, and the ticket's stated harm is "some users showed up at closed
  stores", which an ambiguous label could plausibly cause. It is still out of
  scope here, but for a better reason than "existing display": disambiguating it
  (`22:00 – 01:00 (next day)`, or a date qualifier) is a product decision about
  what the card should say, not a defect on this ticket's causal path — the
  ticket's complaint is a 7-hour offset, which is fixed.

**Evidence** The bug was pinned by a throwaway characterisation test written
**against the unfixed code**, so the fix could be shown to change behaviour
rather than merely to compile.

Against the original model, both of these passed:
```dart
expect(w.label, '23:00 – 02:30');                     // the ticket's string
expect(w.isToday, DateTime.now().day == 12);          // .day only
```
Against the fixed model, both fail:
```
Expected: '23:00 – 02:30'
  Actual: '06:00 – 09:30'      // the bakery's real opening hours
Expected: <true>
  Actual: <false>
```
The throwaway was then deleted and replaced by `test/pickup_window_test.dart`
(including the month-apart and year-apart cases the old `.day` comparison got
wrong, and one asserting `isToday` actually delegates to `isTodayAt` — without
it, `isToday => isTodayAt(DateTime.now().toUtc())` would pass everything else
while restoring the filter bug). Suite 10/10, green at `TZ=Asia/Bangkok`,
`TZ=UTC` and `TZ=America/New_York`.

**Characterised coverage, including where it is blind.** At `TZ=UTC` the label
assertions are worthless: `toLocal()` is the identity, so the derived expectation
evaluates to `'23:00 – 02:30'`, which is precisely what the unfixed getter
produced. Verified rather than assumed — a scratch test printing both strings
reported `OLD_WOULD_PASS=true` at offset zero and `false` at +07. The suite
therefore **catches the calendar half of RES-106 at any offset** (the old
day-only comparison still fails the month- and year-apart cases at UTC) and is
**blind to the zone half at offset zero**. That case now calls
`markTestSkipped`, so a UTC run reports `~1` rather than a silent pass.

On device (PTP N49, local +07), the same card moved from
`Pick up 22:30 – 01:00` to `Pick up 05:30 – 08:00` — a clean +7h shift.
With **Pickup today** on, deals now appear (e.g. *Surprise Sushi Box*,
22:00 – 01:00, genuinely later tonight). *Mystery Thai Feast* correctly drops
out of the filtered list: its 05:30–08:00 window has already passed today, so the
backend rolls it to tomorrow and it is not a today pickup.
Screenshots: `docs/res-106/01-home-before.png`, `02-home-after.png`,
`03-pickup-today-filter-after.png`.

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
- *Unparseable id* (`?id=abc`). No fetch is attempted and the failure message
  says the link does not point at a deal. The retry action is **not offered** in
  this case: re-running would hit the same branch and re-assign the identical
  message, and since `Rx` skips notifying when the value is unchanged
  (`rx_impl.dart:101`) the screen would not even flicker — a control that
  provably cannot change anything. Found by review; the inert button was
  reproduced on device (three taps, no log output, pixel-identical screen)
  before being removed, and the removal re-verified on device — see below.
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

**Failure-state re-verification** after the retry change, on PTP N49 over USB,
2026-09-12 20:04–20:06:

| Link | Result |
|---|---|
| `?id=abc` | "This link does not point at a deal." · **no retry action** · back arrow present |
| `?id=999` | "This deal is no longer available." · retry offered, and tapping it issues a second `GET /deals/999` (20:05:34 then 20:05:39) rather than doing nothing |
| `?id=42` | full page, cold start, unchanged |

Screenshots: `docs/res-107/03-cold-start-fixed.png`,
`docs/res-107/04-unknown-id-error-state.png`,
`docs/res-107/05-unparseable-id-no-retry.png`.
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

## Findings logged, not fixed

Defects found while working on something else. Recorded here rather than fixed,
per the working agreement on scope: a cause that lives on the ticket's path gets
followed across files, anything else gets written down.

### Stale `quantityLeft` lets the bag exceed real stock — *reproduced on device*

`DealDetailsController` holds the remaining-stock number **twice**, and only one
of them is refreshed:

| | used for | refreshed by `_recheckAvailability`? |
|---|---|---|
| `_quantityLeft` | the "N left" chip | yes |
| `_deal.value.quantityLeft` | the cap inside `CartService.add` | **no** |

`_recheckAvailability` has the fresh model in hand as `fresh` and writes only
`_quantityLeft`. `addToCart` then passes the stale `_deal.value`, and
`cart_service.dart:18` caps on `deal.quantityLeft` — the old number.

**Reproduced end to end**, 2026-09-12 19:37–19:42 on PTP N49: opened *Chef's Thai
Bundle* (id 2, 4 left), bought 2 — backend stock 4 → 2. Returned to the home
feed, which had not reloaded and still showed "4 left", and reopened the card so
the controller received the stale model as `Get.arguments`. Adding to the bag
triggered the re-check and the chip correctly updated to **2 left** — and the bag
still accepted items up to **4**, total ฿504, with
`cart: cannot add more of deal 2` only appearing at the fourth. Screenshot:
`docs/findings/stale-stock-cap.png`.

The sharp edge is not that the data is stale; it is that **the screen was
displaying the correct number, 2, at the moment it accepted the fourth item**.
The UI and the validation disagreed inside the same frame.

One line closes it — `_deal.value = fresh;` beside the existing write — and that
line sits inside the RES-107 diff, since `_recheckAvailability` was restructured
there. It is deliberately not taken: it is not on RES-107's causal path (the
deep-link null cast), and stock correctness is the subject of **F-3**, where
reservations replace this client-side cap entirely. If F-3 is not reached, this
should be fixed on its own.

### The cart worker is never disposed

`deal_details_controller.dart` stores the `Worker` from `ever(...)` but has no
`onClose()` override, and GetX 4.7.3 does not dispose workers for a controller
(nothing under `get_state_manager/` or `get_instance/` references `Worker`). Every
deal screen visited leaves a live listener on the session-long
`CartService.itemCount`, so one add-to-bag fires one `fetchById` per deal viewed
this session. Observed directly during the RES-107 and stale-stock runs: deal 2
logged `re-checking availability` **twice** after being opened twice.

This is **RES-103**, so it is that ticket's fix, not a finding to act on here.
Noted because RES-107 changed its shape: `onClose` can now run *before* the
worker is created on the deep-link path, so "store the `Worker`, dispose it in
`onClose`" would dispose null and leak unconditionally. The `isClosed` guard in
`_adopt` closes that from the other side, but RES-103 has to account for the
ordering rather than assume it.

### `refreshDeals` has no error handling

`home_controller.dart:58-64` has no `try`/`catch`. A failed refresh never reaches
`refreshController.refreshCompleted()`, so the pull-to-refresh spinner hangs
permanently, and `_page` has already been reset to 1 while `deals` still holds the
previous content. Adjacent to **RES-104** and left for it.

### Hong Kong stores are built on the wrong market clock

See RES-106 Edge cases. Out of bounds — the cause is in `fake_api_service.dart`.

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

The test is a unit test on `PickupWindowModel`, and the assertion is not "the
label is 06:00". It is: *a window the backend built from 06:00 market time
renders as 06:00 for a user in that market, and counts as today for them* —
exercised at a UTC offset where local and UTC disagree, because at offset zero
the bug is invisible. `test/pickup_window_test.dart` now does exactly this,
plus the `.day`-only cases (same date one month and one year apart) that the old
comparison got wrong.

What had to change to make it possible: the model called `DateTime.now()`
directly inside `isToday`, so its result depended on the wall clock at the moment
the test ran and could not be asserted. Splitting out `isTodayAt(DateTime now)`,
with `isToday` delegating, makes the comparison a pure function of its inputs.
That is the minimum; `isOpenNow` and `untilStart` still call `DateTime.now()`
internally and remain untestable for the same reason — they were correct, so I
left them, but the same seam would be the fix.

What is still not covered: `label` depends on the *process* timezone, which Dart
resolves at start-up and a test cannot change from inside, so honest coverage
means running the suite more than once in CI. The two values should be
`TZ=Asia/Bangkok` and `TZ=America/New_York`, not Bangkok and UTC — a positive
offset puts the local date *ahead* of the UTC date and a negative offset puts it
*behind*, which are mirror-image failures, and the fixture in this suite is
+07-shaped so the negative case would otherwise never be exercised. (It passes
at New York today; that is a claim I can make because I ran it, not because the
arithmetic looks symmetric.) `TZ=UTC` belongs in the matrix only as the
documented blind spot described under Evidence, never as one of the two real
values.

The test derives its expected label from the instant rather than hardcoding
`'06:00 – 09:30'`, which keeps it green at every offset. That is less
tautological than it looks: the expectation reads `.hour`/`.minute` directly
while production goes through `DateFormat('HH:mm')`, so it is an independent
path to the same answer rather than a copy of the implementation.

---

## Time spent

Running log in [`docs/ai-log.md`](docs/ai-log.md).

| Date | Span | On |
|---|---|---|
| 2026-09-12 | ~16:10– | Orientation, environment verification, baselines, scaffolding |

**Total so far** — ~0.3 h

**With one more day** — *(to be written at the end, honestly)*
