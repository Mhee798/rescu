Sittings are listed separately because the between-sitting spread is larger
than the within-sitting spread on the fixed side: 0.631, 0.428 and 0.645 ms of
`BUILD` per frame for identical code, against a control that reproduces to
within 5 % both times. An earlier revision of this file published "9 → 4" from
the first control sitting alone, which happened to be the worst of the two;
re-measuring the shipped build against a fresh control gave 7 against 5 in that
sitting, and pooling everything gives the figures above. Any single A/B here is
worth about a factor of two of confidence, and that is the resolution the
numbers are quoted at.

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
session. The count is exactly three rather than "up to three" because
`orders_screen.dart:23` is a plain `ListView(children: […])` rather than
`.builder`, so every tile mounts immediately regardless of viewport — which is
also why the reproduction is deterministic.

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
  `createState` appears once in `lib/`, at `pickup_countdown.dart:14`, and
  `Timer` appears nowhere else outside the fake backend. The one other
  subscription of this shape is `scrollController.addListener(_onScroll)` at
  `home_controller.dart:36`, and it is **not** a sibling instance:
  `HomeController.onClose` calls `scrollController.dispose()`, which drops its
  listeners. There is nothing else to chase.
- *What the per-second `setState(() {})` actually costs.* Not "rebuilds the whole
  widget": the `Icon` and the `SizedBox` are `const`
  (`pickup_countdown.dart:43-45`), so their elements are reused. Each tick costs
  one `build` call, a `Row` re-layout, and reconstruction of the single non-const
  `Text`. Acceptable for one row; precisely what **F-1** must not do at feed
  scale, where the requirement is that only the countdown `Text` rebuilds — not
  the card, not the list. Stated exactly because F-1's claim will be measured
  with Track Widget Builds and held against this one.
- **Not handled, deliberately:** *the timer also runs while the screen is merely
  covered.* Navigating My orders → a deal leaves the orders route in the stack
  with its tiles mounted, so three timers keep firing and rebuilding offscreen
  widgets until the route is popped. That is not the reported crash and not on
  its causal path — `dispose` is never called, so nothing is used after
  disposal — but it is the same resource question one step over, and it is
  exactly the problem F-1 has to solve at 100× scale. A `TickerMode` /
  route-aware pause belongs with F-1's central ticker, not here.

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

`test/pickup_countdown_test.dart` covers it without a device — with the
following honest limits, because the suite is weaker than its pass count
suggests.

*The disposal case has no assertion of its own.* It borrows `flutter_test`'s
*"A Timer is still pending even after the widget tree was disposed"* invariant.
That is a dependency rather than elegance: if the framework moves that check,
the case silently becomes one that always passes. There is no clean way to
assert a cancelled timer directly, so the trade is taken and recorded.

*"All five cases fail against the unfixed widget" is not the strength it looks
like.* Four of them fail on the same pending-timer invariant rather than on their
own assertions — they would fail identically whether the label logic were perfect
or completely broken. So the file holds **one** regression test for RES-102 and
four rendering characterisations that happen to trip the same wire. If someone
later reintroduces the leak *and* breaks the label, five failures all say the
same thing and none of them says the label broke.

*The countdown arithmetic is not unit-covered.* `tester.pump` advances
`FakeAsync`'s clock, which is what fires the periodic timer, but the widget
derives `remaining` from `DateTime.now()`, which `flutter_test` does not fake.
Measured, not assumed: the rendered string is byte-identical across six simulated
seconds. The tick test is therefore named for what it does — *rebuilding on each
tick does not throw* — and the arithmetic is verified only by the device
observation below. The rendered **format** is pinned exactly
(`^Opens in \d{2}:\d{2}$` and `^Opens in \d+h \d{1,2}m$`) so that F-1, which
replaces this widget, inherits a net for the format it must keep producing.

After the fix the suite is 15/15.

Re-verified on device: countdowns tick (16:54 → 16:50 and 45:54 → 45:50 across a
four-second sample, so the fix did not freeze the feature), and navigating in and
out of My orders five times — fifteen timers created and discarded — produced
**zero** `setState() called after dispose()` and zero unhandled exceptions.

*Negative control.* Zero exceptions could equally mean the procedure had stopped
detecting them, so the same run was repeated against a build with only
`pickup_countdown.dart` reverted to its pre-fix state — one file changed, same
device, same taps, `logcat -c` before each run:

| build | `setState() after dispose` | `Unhandled Exception` |
|---|---|---|
| reverted to the buggy version | **3** | **3** |
| fixed | **0** | **0** |

Then restored and re-run: 0 again. So the zero means the defect is gone, not
that the measurement went blind.

One number deliberately not claimed: the control logged three exceptions over a
ten-second wait, i.e. one per State rather than one per State per tick. Whether
that is Android's repeated-line suppression or Flutter collapsing identical
errors was not established, so nothing in this section rests on the throw
*frequency* — only on 3 versus 0.

## RES-103 · Requests pile up the longer you browse
**Status** fixed — reproduced, fixed, re-verified on device

**Symptom** Each "Add to bag" fires one `GET /deals/:id` per deal viewed earlier in the session.

**Root cause** The controller is disposed correctly — GetX does its job. What
outlives it is a **subscription to an observable owned by a `permanent: true`
service, registered by a screen-scoped object that never claimed ownership of
it.**

`DealDetailsController` calls `ever(cartService.itemCount, …)`. `CartService` is
put `permanent: true` in `main.dart`, so it and its `itemCount` live for the whole
session. `ever` returns a `Worker` — which is the API telling you that you own
the subscription — and the controller discarded it. GetX does not close it for
you: in `get` 4.7.3 nothing under `get_state_manager/` or `get_instance/`
references `Worker` at all. So every visit to a deal screen adds one permanent
listener, and one cart change wakes all of them, each calling
`dealRepo.fetchById` for its own captured deal.

**The null guard already in `_recheckAvailability` does not stop this**, and the
distinction matters because a reader will see it and assume the ticket was
half-fixed by RES-107. `if (deal == null) return;` never fires on a disposed
controller: `_deal.value` was populated before the pop and GetX 4 does not clear
a controller's `Rx` fields on dispose. The guard exists for the pre-adoption
window on the deep-link path, not for disposal.

**Fix** Dispose the `Worker` in `onClose`. Complete only in combination with the
`isClosed` guard in `_adopt` added for RES-107 — the worker's lifetime has to be
bounded by the controller's at **both** ends, and neither half does it alone:

- Without `onClose` disposal, a worker that was created outlives its controller.
- Without the `isClosed` guard, `onClose` can run *before* `_watchCart` on the
  deep-link path (measured for RES-107: with a back press ~100ms in, `onClose`
  precedes the fetch response in 6 runs out of 6). `onClose` would then dispose
  `null` and the later registration would leak unconditionally.

**Alternative rejected** *Widen the null guard into a disposal guard — check
`isClosed` inside `_recheckAvailability`, or null out `_deal` in `onClose`, so
the callback returns early on a dead controller.* This is CLAUDE.md §3's
`if (mounted)` entry wearing different clothes, and it is a sharper example than
RES-102's because the symptom-mask is **already sitting in the file**: widening
the existing early return would make the log lines disappear while every listener
stayed subscribed to a session-long service, still holding its controller, its
`DealModel` and its repository. The requests would stop; the retention would not.

**Edge cases**
- *One re-check still fires after the fix, and that is correct.* A live details
  screen is supposed to re-check its own stock when the cart changes — that is
  the feature. The number to expect is 1, not 0.
- *After the RES-107 tag change, the number to expect is one per deal page
  currently on the stack, not one full stop.* Tagging by route id means a deep
  link over an open deal page produces two live controllers, so two live
  workers. Measured 22:16: with deal 7 and deal 1 both on the stack, one Add to
  bag logged `re-checking availability for deal 7` **and** `... deal 1`;
  popping deal 1 and adding again logged one. That is bounded by the navigation
  stack and released on pop — the opposite of the unbounded growth this ticket
  is about — and each of those screens is live and supposed to refresh its own
  stock. Worth stating because a reader counting re-checks after a deep link
  will see 2 and reasonably suspect the leak is back.
- *Deep-link path where `onClose` precedes registration.* Covered by the
  `isClosed` guard rather than by disposal; see above.
- *`retry()` re-registering.* `_watchCart` returns early when `_cartWorker != null`
  and `Worker.dispose()` is itself idempotent (`rx_workers.dart:263` sets
  `_disposed` first), so neither a retry nor a double `onClose` can double-
  subscribe or double-cancel.
- **Not handled, deliberately:** `_recheckAvailability` still has no `try`/`catch`,
  so a failing `fetchById` on a *live* screen becomes an unhandled async error.
  That is a separate defect from the leak and is logged under "Findings logged,
  not fixed" rather than folded in here.

**Evidence** Counted `re-checking availability for deal X` — the `LogService.log`
at the top of `_recheckAvailability` — **not** the raw `GET /deals/:id` line,
because RES-107 made the deep-link path fetch by id for legitimate loads too, so
`GET` no longer isolates re-checks.

Same procedure both times on PTP N49 over USB: open the first feed card and press
back, three times, then open it a fourth time and tap Add to bag once.

*Before* (20:47) — four views, one tap, **four** re-checks in the same
millisecond, from one live controller and three dead ones:
```
analytics: deal_details_view {deal_id: 1, source: home}   ×4
[20:47:14.995] re-checking availability for deal 1
[20:47:14.996] re-checking availability for deal 1
[20:47:14.996] re-checking availability for deal 1
[20:47:14.996] re-checking availability for deal 1
```

*After* (20:54) — same four views, same single tap, **one** re-check:
```
analytics: deal_details_view {deal_id: 1, source: home}   ×4
[20:54:45.238] re-checking availability for deal 1
```

4 → 1, where 1 is the live screen doing its job — for a single deal route. The
general figure is **one per live deal route**, which since the RES-107 tag change
is two when a deep link is stacked over an open deal page; measured, and covered
under Edge cases above.

## RES-104 · Duplicate deals in the home feed
**Status** not started

**Symptom** Pull-to-refresh while the next page is still loading intermittently yields duplicate cards, or more items than the catalog holds.

**Root cause** —
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

## RES-105 · Home feed is janky and memory keeps climbing
**Status** three causes found and fixed, verified against a negative control on
a 2018 device: widget-build cost per frame falls about sixfold with no overlap
between the two sides, and dropped frames halve on the median with overlapping
ranges. One of the two symptoms in the ticket does not reproduce at
all, and the worst case I found did not improve — both stated below rather than
omitted.

**Symptom** Dropped frames while scrolling; memory grows until the OS kills the
app. The ticket states there is more than one contributing cause.

**Where the symptoms actually appear.** The first device used, an Honor Magic 7
Pro (Snapdragon 8 Elite, 120 Hz), shows zero frames over budget with the bug
present — it absorbs the whole defect. Everything below was therefore measured
on a Huawei P30 Pro (Kirin 980, 2018, 60 Hz, Android 10), which is the
"mid-range Android" the ticket is written about. Full baselines for both, and
the procedure, are in `docs/res-105/baseline.md`.

**The memory half of the ticket does not run away, and this is measured rather
than inferred.** An earlier draft argued this from `dumpsys meminfo` — Native
Heap 27.6 MB → 38.2 MB across all 122 deals, then *falling* to 37.3 MB — and
called the cache saturated at its 100 MB ceiling. Those two statements cannot
both be true: a process sitting at 38 MB cannot be holding a full 100 MB image
cache. The decoded pixel buffers are Skia allocations and do not appear in that
field, so the meminfo figures were measuring a pool the images are not in.

The authoritative number is `ImageCache` itself. Logged once a second from a
temporary probe in `main()` (removed afterwards; never committed), scrolling the
full 122-deal feed on the P30 Pro:

| | peak `currentSize` | peak `currentSizeBytes` | bytes per image |
|---|---|---|---|
| control | **13** images | 99,840,000 (95.2 MB) | 7,680,000 = 1600 × 1200 × 4 |
| fixed | **36** images | 104,571,648 (99.7 MB) | 2,904,768 = 984 × 738 × 4 |

Both sit at the 100 MB default ceiling, so the original claim survives the
correction: the cache saturates and evicts, it does not grow without bound, and
the ticket's "until the OS kills the app" does not reproduce. What the fix buys
is **2.8× more images resident for the same memory**, which is fewer evictions
and fewer re-decodes on the same scroll — not a smaller footprint. No reduction
in memory is claimed.

### Cause 1 — one `Obx` around the whole `Scaffold`, reading a value written every frame

`HomeScreen.build` wrapped the entire `Scaffold` in a single `Obx` whose first
statement was `controller.scrollOffset.value`, and `HomeController._onScroll`
assigned that offset on every scroll callback. So every scroll frame invalidated
the whole feed subtree. Measured with `ext.flutter.profileWidgetBuilds`: **23
`Scaffold` rebuilds across 23 rendered frames** — one per frame, not
"frequently".

Everything inside that scope was identical between frames except two things,
both threshold comparisons on the offset: `elevation: offset > 4 ? 2 : 0` and
`offset > 800` deciding whether the FAB exists.

*Fix.* The controller exposes the two thresholds as `RxBool` and no longer
publishes the raw offset. `Rx.value` skips notifying when the value is unchanged
(`rx_impl.dart:101`), so each flag wakes its own `Obx` twice per journey down
the feed instead of once per frame. The screen has three narrow scopes — AppBar,
body, FAB. The AppBar's sits inside a `PreferredSize` because `Scaffold.appBar`
requires a `PreferredSizeWidget` and `Obx` is not one.

### Cause 2 — the feed built every card on every rebuild

`ListView(children: [..., ...visibleDeals.map((d) => DealCard(deal: d)), ...])`.
The spread constructs one `DealCard` **object** per loaded deal each time the
enclosing scope runs, and `SliverChildListDelegate` holds the whole list.
Measured over one swipe: **385 `DealCard` objects constructed, 93 actually
built** — three quarters allocated and discarded without reaching `build()`,
alongside 24,509 `_List` allocations (1.27 MB) in 400 ms.

Worth stating what this is *not*: `ListView(children:)` does not keep off-screen
card elements alive. 93 builds across 23 parent rebuilds is the viewport plus
cache extent. The cost is allocation churn and the layout work that follows, not
retention — the worst UI frame of the scroll-to-top case spent 35.11 ms in
`LAYOUT`.

One cost of this scope change had to be paid back, and the first attempt at it
was wrong in a way worth keeping in the record. Narrowing the `Obx` costs the
FAB its scale-in: `Scaffold` animates the button in
`_FloatingActionButtonTransition.didUpdateWidget`, which runs only when the
**`Scaffold`** rebuilds with a different `floatingActionButton`. An `Obx`
rebuilds itself and never its parent, so that method is now unreachable from
this screen, and the `ScaleTransition` stays at the value it settled on at
mount — 1.0, because `Obx` is non-null from the first frame. The old code got
the animation for free precisely because the whole `Scaffold` sat inside the
`Obx`.

I first read this one level too low, concluded that the early return on equal
keys (`scaffold.dart:1368`) was the cause, gave the two branches distinct
`ValueKey`s, and wrote it up as fixed. It changed nothing — a probe pumping the
production shape reads `scale == 1.0` before the flip, after it and 380 ms
later. The animation is now done in the widget instead: `AnimatedScale` inside
the `Obx`, wrapped in `IgnorePointer` because a zero-scale `Transform` keeps its
layout slot and stays a live tap target.

`test/home_fab_transition_test.dart` pins it, and that file had to be rewritten
too. Its first version toggled the branch with `pumpWidget`, which rebuilds the
`Scaffold` and so exercised a path this screen never takes; it passed while the
button popped in at full size. It now mounts the `Obx` form and drives it by
writing to the `Rx`, with two controls — the un-animated shape reaching full
size in a single frame, and the hidden button refusing a tap.

*Fix.* `ListView.builder`, with the two headers kept in place by an index offset
rather than a second widget list. The horizontal flash rail was already a
`ListView.builder` (`flash_deals_section.dart:36`) and needed no change — this
cause is confined to the vertical feed.

### Cause 3 — every image decoded at 1600×1200 whatever slot it lands in

`fake_api_service.dart:267` serves `picsum.photos/seed/<seed>/1600/1200` for
every deal, and `TheNetworkImage` constrained nothing. Flutter reports the cost
itself once `debugInvertOversizedImages` is on:

```
Image null has a display size of 1168×560 but a decode size of 1600×1200,
which uses an additional 6593KB (assuming a device pixel ratio of 3.5).
```

By the framework's own accounting (`painting/debug.dart:93` — `w × h × 4 × 4/3`,
four bytes per pixel plus a third for mipmaps) that is 10,000 KB reported per
image against 3,406 KB needed. `ImageCache` itself counts the raw `w × h × 4`,
so what it actually holds is 7.68 MB apiece and, measured, **13** images before
its 100 MB default ceiling — a 122-deal feed evicts and re-decodes continuously.
The consequence shows in the raster thread: the worst frame of the scroll-to-top
case spent **73.16 ms in `UploadTextureToPrivate`**, the GPU upload of decoded
bitmaps.

*Fix.* A decode hint from a `LayoutBuilder`, since the call sites pass
`width: double.infinity` and the real slot size is only known after layout.
Exactly one dimension is hinted — `ResizeImage` preserves the aspect ratio from
one value and constraining both would stretch the image — and *which* one is not
free: `BoxFit.cover` is bound by whichever dimension is proportionally larger,
so the box's aspect is compared against the source's known 4:3.

A first version hinted the width unconditionally, guarded by
`slotHeight > slotWidth`, a 1:1 test standing in for a 4:3 one. There are
**five** call sites, not the three I had looked at: the 64×64 thumbnails in
`cart_screen.dart:33` and `orders_screen.dart:74` pass a 1:1 guard, so they took
`memCacheWidth` 192, decoded 192×144, and `cover` upscaled that 1.33× into a
192×192 box — a blur regression on two screens introduced by this fix. Verified
on device after the correction: both screens render sharp and Flutter reports no
oversized-image warning for them.

**Fix** Three separate commits, one per cause: `b367cde`, `1792087`, `2a87716`.

**Alternative rejected** *Wrap only the `AppBar`'s elevation and the FAB in
`Obx` but leave `scrollOffset` as a `double`.* Fewer moving parts and no new
controller fields. Rejected because the `Obx` would still be woken on every
scroll frame — the notification comes from the `Rx` changing, and the offset
changes continuously. It would rebuild an `AppBar` 60 times a second to produce
the same elevation 59 of those times. Moving the threshold into the `Rx` is what
makes the notification rare, not moving the `Obx`.

Also rejected: *raising `ImageCache.maximumSizeBytes` so the feed's images fit.*
It would cut the re-decoding, and on a 12 GB phone it would even look fine.
Rejected because it spends memory to avoid fixing the thing that wastes memory,
and it makes the app's footprint worse on exactly the devices the ticket is
about. The cache is not too small; the images are too large.

**Edge cases**
- *A slot narrower than the source's 4:3.* `BoxFit.cover` is then bound by
  height, so `_decodeSize` hints the height instead of the width. This is the
  live case, not a hypothetical: the 64×64 thumbnails in `cart_screen.dart:33`
  and `orders_screen.dart:74` take it and decode 256×192.
- *A dimension the widget does not know.* Each is read from the widget's own
  field first and the incoming constraints second, because the feed card and
  the flash rail sit in a `Column` and the height reaching the `LayoutBuilder`
  is infinite. With a finite width and no usable height the box is treated as
  width-bound, which is right: an unbounded parent lets the image size itself
  to its own aspect.
- *Neither dimension usable.* No hint, and the image decodes at the served
  1600×1200. None of the five call sites reaches this, but it is the safe
  direction — a missing hint costs memory, a wrong one costs sharpness.
- **Not fixed, deliberately:** `visibleDeals` still builds a new `List` on every
  read. With the `Obx` scoped, it is read when `deals` or `todayOnly` changes
  rather than once per frame, which was the part that mattered. Memoising it
  would add cache-invalidation state to a controller for a cost that is no
  longer on the hot path.

**Evidence** — profile mode, Huawei P30 Pro over Wi-Fi adb, 2026-09-12/13. The
fixed and control builds were measured alternately, the control produced by
checking the three files out at the pre-fix commit and rebuilding, so the
comparison is against the same device in the same session rather than against
figures from earlier in the day. Control build confirmed to be the old code by
its widget-build signature (`PreferredSize` absent, `Scaffold` rebuilding).

*Rebuild counts, one scripted swipe, `profileWidgetBuilds` on:*

| | control | fixed |
|---|---|---|
| frames in the window | 79 | 86 |
| `Scaffold` builds | 14 | **0** |
| `Obx` builds | 14 | 2 |
| `AppBar` builds | 14 | 2 |
| `DealCard` builds | 50 | 1 |

*Frame cost, three scripted swipes per side, tracking off so the measurement is
free-running (medians):*

| | control | fixed |
|---|---|---|
| `BUILD` per frame | 2.087 ms | **0.045 ms** |
| `LAYOUT` per frame | 1.359 ms | **0.240 ms** |
| UI p90 | 5.57 ms | **2.06 ms** |
| raster p50 | 8.61 ms | 9.36 ms |

*Image decode, debug build with `debugInvertOversizedImages`, P30 Pro at DPR 3.0:*

| | control | fixed |
|---|---|---|
| decode size | 1600 × 1200 | **984 × 738** |
| held per image | 10,000 KB | **3,781 KB** |
| overhead Flutter reports | 7,540 KB | **1,322 KB** |
| images the 100 MB cache holds (measured) | **13** | **36** |

The warning does not disappear — 36 lines still appear over fourteen swipes,
now reading `display size of 984×480 but a decode size of 984×738`. That
residual is the aspect overhang: the source is 4:3, the card slot is 2.05:1, and
`BoxFit.cover` crops the extra rows. A width-only hint cannot remove it, and
`cached_network_image` does not expose `ResizeImage`'s fit policy. 82 % of the
waste is gone; the rest is left, named.

Peak Native Heap across all 122 deals: 38,248 kB → 34,963 kB.

**Which of the three fixes actually did the work.** PROBLEM.md asks for an
improvement attributed to each cause, so the three were measured separately
rather than only together: five builds on the same device in one session, each
the same scripted swipe three times, tracking off, medians below.

| build | BUILD /frame | LAYOUT /frame | UI p90 | raster p50 |
|---|---|---|---|---|
| control | 2.682 ms | 1.943 ms | 7.14 ms | 8.27 ms |
| ① `Obx` scope only | **0.091** | **0.187** | **2.59** | 6.75 |
| ① + ② `ListView.builder` | 0.090 | 0.204 | 2.83 | 6.80 |
| ① + ② + ③ images | 0.040 | 0.168 | 1.50 | 7.66 |
| ③ images only | 3.289 | 2.366 | 7.66 | 7.37 |

**Cause ① is essentially the entire frame-time win.** On its own it takes
`BUILD` from 2.682 ms to 0.091 ms per frame — 97 % — and the two later fixes add
nothing to that column that is distinguishable from noise. The ③-only row is the
control within noise, which is the expected result and a useful check: the image
fix is raster-side and should not touch the UI thread.

*What ② is worth, measured where it can show.* With ① in place the `Obx` runs
roughly twice per swipe instead of once per frame, so the spread it feeds barely
runs during scrolling — which is why ② is invisible in the table above. The
gesture that exercises it is one that changes the list. Tapping "Pickup today"
twice with all 122 deals loaded:

| | ① only | ① + ② + ③ |
|---|---|---|
| `DealCard` objects constructed | **386** | **9** |
| `BUILD` total | 12.00 ms | 8.14 ms |
| `BUILD` worst frame | 4.46 ms | 2.56 ms |
| frames over 16.7 ms | 0 | 0 |

A 43× reduction in widget construction, and no dropped frame on either side.
So ② is a real improvement that this device never needed: it matters for a
longer list, a slower phone, or a feed that changes more often than this one
does. Stated that way rather than folded into the headline.

*The second device, and the refresh rate.* The same control/fixed pair was run
on the Honor Magic 7 Pro, then again with that device forced to 60 Hz, which
separates the display's refresh rate from the SoC. Pre-fix `BUILD` per frame is
2.682 ms on the P30 Pro against 1.495 ms on the Magic 7 Pro **at matched
60 Hz** — a 1.79× hardware difference. Running the Magic 7 Pro at its native
120 Hz instead costs 1.135 ms per frame but **128.2 ms of build work per second
of scrolling against 85.8 ms/s at 60 Hz**: the feed was rebuilt once per frame,
so a faster display ran the waste half again as often. After the fix the two
refresh rates collapse together at 2.0-2.3 ms/s. This also retires a claim made
earlier from one sample per device, that the churn cost the 120 Hz device a
larger *share* of its budget than the older phone — at 16.1 % against 13.62 % it
does not. The fix behaves the same way on both (`BUILD` 1.135 →
0.021 ms, UI p90 3.40 → 0.86 ms) but removes no dropped frames there, because
there were none: zero frames over 8.33 ms before or after. The baseline document
now carries the correction rather than the original claim.

*What ③ is worth.* Nothing measurable in frame time on these gestures — raster
p50 moves between 6.75 and 8.27 ms across all five builds with no ordering. Its
attributed improvement is the decode and cache figures above: 10,000 KB → 3,781
KB held per image, the 100 MB cache going from ten images to twenty-six, and
peak Native Heap 38,248 kB → 34,963 kB. The 73.16 ms `UploadTextureToPrivate`
frame that motivated it belongs to the scroll-to-top case, and that case is too
noisy to claim from — see below.

*The gesture that actually shows the symptom.* A 400 ms scripted swipe never
dropped a frame on either build — the dropped frames in the baseline came from a
person flicking the device, which is not reproducible. A fast scripted fling
(`input swipe 540 600 540 2200 60`, six in a row, no taps anywhere in the
script) reproduces it and is repeatable. Three runs per build, all 122 deals
loaded, P30 Pro:

Six control runs and nine fixed runs, across three sittings, all 122 deals
loaded, P30 Pro:

| | control | fixed |
|---|---|---|
| frames over 16.7 ms, per run | 9, 9, 8 · 7, 10, 5 | 4, 4, 7 · 2, 0, 6 · 5, 3, 9 |
| median · range | **8.5** · 5–10 | **4** · 0–9 |
| `BUILD` per frame, per sitting | 3.717 · 3.903 ms | 0.631 · 0.428 · **0.645** ms |
| UI p90 | 9.84 · 10.12 ms | 8.89 · 6.25 · 9.16 ms |
| raster p90 | 12.30 · 9.86 ms | 14.28 · 11.25 · 11.60 ms |

**`BUILD` per frame falls about sixfold and the two sides do not overlap at
all** — every control sitting is above 3.7 ms, every fixed sitting below 0.65.
That is the claim this fix can carry.

**Dropped frames halve on the median, 8.5 to 4, but the ranges overlap** — the
worst fixed run dropped nine frames, more than four of the six control runs.
With three runs per sitting the honest statement is a factor of about two on
typical behaviour, not a reliable ceiling.

Sittings are listed separately because the between-sitting spread is larger
than the within-sitting spread on the fixed side: 0.631, 0.428 and 0.645 ms of
`BUILD` per frame for identical code. An earlier revision of this file published
"9 → 4" from the first control sitting alone, which happened to be the worse of
the two; re-measuring the shipped build against a fresh control gave 7 against 5
in that sitting, and pooling everything gives the figures above. Any single A/B
here is worth about a factor of two of confidence, and that is the resolution
these numbers are quoted at.

Two honest qualifications. Raster p90 does not improve and in two of the three
fixed sittings is worse — the UI thread keeping up means more frames reach the
rasteriser, so that thread gets busier. And `BUILD` per frame is around 0.6 ms
here against 0.045 ms on the gentle swipe, because a fast fling pulls far more
cards into the viewport and that build work is real rather than redundant. The
fix removes the waste; it does not make a fling free, and a typical fling still
drops about four frames.

*What is left.* Two candidates were considered for the frames that still drop,
and both were checked rather than left as speculation.

*`RepaintBoundary` on `DealCard`* — already there.
`SliverChildBuilderDelegate.build` wraps every child in one when
`addRepaintBoundaries` is true, which is the default
(`widgets/scroll_delegate.dart:505`). Adding another would be a no-op. Settled
by reading the framework, not by measuring.

*Prefetching images ahead of the viewport with `precacheImage`* — built and
measured, **and it does not hold up**. A variant that precaches four cards ahead
using `ResizeImage.resizeIfNeeded(w, null, CachedNetworkImageProvider(url))`,
the same key `cached_network_image` builds internally (verified: peak cache
stayed at exactly 36 images / 104,571,648 bytes, so nothing was decoded twice),
dropped 0, 1, 1 frames against the fixed build's 4, 4, 7 — an apparently large
win. Re-running the *unmodified* fixed build in the same conditions immediately
afterwards gave 2, 0, 6. The difference was session drift, not prefetching.
Recorded because it is the more interesting result: the experiment was sound,
the cache-key check passed, and the number was still meaningless without a
same-sitting control.

So the honest position is that I do not know what the remaining frames are. The
raster thread is the busier of the two after the fix, and
`UploadTextureToPrivate` is the largest item in the slowest raster frames
measured, which points at decode and upload — but that is where the evidence
stops.

**What did not improve, and I could not make it.** The worst case found is the
scroll-to-top FAB — `animateTo(0, 400ms)` from the end of a loaded feed, which
drives the viewport through every card in the list. Four runs per side:

| | control | fixed |
|---|---|---|
| frames over 16.7 ms | 14, 16, 15, 9 (median 14.5) | 9, 12, 13, 11 (median 11.5) |
| raster max | 51.1, 30.0, 30.5, 22.2 | 18.6, 60.8, 18.0, 87.1 |

The distributions overlap and the variance swamps the difference; the largest
single raster frame of the whole exercise, 99.5 ms, came from a *fixed* run.
**No improvement is claimed for this case.** The reason it resists the fix is
that the work is real: the animation genuinely puts a hundred new cards through
build, layout and image upload in four tenths of a second, and none of the three
causes was what made that expensive. Removing it properly means not animating
through the whole list — `jumpTo` with a short fade, or Flutter's own
`ScrollController.animateTo` replaced by a jump past the cache extent — which is
a behaviour change to a working feature and outside this ticket.
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


**A fourth entry path, found after the above was signed off.** The three cases
verified above all start with no deal page on the stack. The one that does not —
a deal page already open, the app backgrounded, a push for a *different* deal —
was still broken, and nothing about it is exotic: a push about a second deal
arriving while the user is reading a first one. On device: deal 1 open, HOME, `rescu://open/deal?id=7&source=push` →
`screen_view {screen: /deal}` logged, but **no `GET /deals/7`, no
`deal_details_view`**, and the screen still showing Mystery Thai Feast. No
crash, no error — the wrong deal, silently. That fails the ticket's own
requirement as squarely as the original crash did.

*Cause.* GetX keys an instance by `type.toString() + tag`
(`get_instance.dart:312`). Both pushes register `DealDetailsController` with no
tag, so they are the same key; `_insert` no-ops when the key already exists and
is not dirty, and `_initDependencies` runs `onInit` only when `!isInit`. The
second route therefore gets the first route's controller, fully initialised,
holding deal 1. Nothing runs that would notice the new id.

*Fix.* Tag the registration with the route's id, in the binding and on the
`GetView` that reads it back:

```dart
Get.lazyPut(() => DealDetailsController(...), tag: Get.parameters['id']);
page: () => DealDetailsScreen(tag: Get.parameters['id']),
```

Three source facts this depends on, checked rather than assumed:

- `Get.parameters = match.parameters` is assigned during route resolution
  (`route_middleware.dart:259`, `:288`), before bindings run — so it is the
  *incoming* route's id at both call sites.
- `RouterReportManager._routesKey` is `Map<Route?, List<String>>`
  (`router_report.dart:10`) — keyed by the Route *object*, not by name. Two
  `/deal` routes are distinct keys, so popping deal 7 disposes only deal 7's
  controller and leaves the covered page working.
- `GetView.tag` is a `final String? tag = null` field, so supplying a tag means
  shadowing it (`// ignore: overridden_fields`) — the pattern GetView's own doc
  comment demonstrates.

*Why reading global state inside a page builder is safe here, which is the first
thing worth attacking about this design.* Flutter does invalidate a route's page
widget on ordinary events: `_ModalScopeState.didChangeDependencies` sets
`_page = null` (`flutter/lib/src/widgets/routes.dart:996`) and
`changedExternalState` calls `_forceRebuildPage()` (`:2044`) — a rotation, a
keyboard, a theme change. If `page()` re-ran, deal 1's covered route would
rebuild with whatever `Get.parameters` held at that moment — `'7'` — and resolve
deal 7's controller. The bug back, triggered by turning the phone.

It cannot, because `GetPageRoute` caches: `_getChild()` opens with
`if (_child != null) return _child!;` (`default_route.dart:94-95`), runs the
bindings and `page()` inside that guard, and `buildContent` returns the cache
(`:114-117`). Flutter's re-entry into `buildPage` hits the cached widget, so
`page()` and the bindings run exactly once per route instance and the tag is
frozen at that route's own resolution. The binding and the builder also read
`Get.parameters` inside the same `_getChild()` call, which is why they cannot
disagree with each other.

**Known residual, not closed.** That single read happens at first content build,
not at route resolution where `Get.parameters` was assigned. If a second route
resolution lands in between — two navigations inside one frame — both reads pick
up the later id. They stay consistent with each other, so there is no tag
mismatch and no crash; the controller is simply keyed to, and fetches, the wrong
deal. Not reproduced, and no cheap close: `page: () =>` is handed no access to
its own route's `settings`, only the global. Naming it is worth more than
presenting the design as airtight.

`_DealBody` had to stop extending `GetView<DealDetailsController>`. It reads
`controller.quantityLeft` through the untagged `Get.find`, which after this
change throws "Instance not found" at runtime; `flutter analyze` does not catch
it, because the type is right and only the tag is missing. It now takes the
controller as a constructor parameter from the screen that already resolved it.

The RES-107 change that captures `_routeDealId` and `_source` in `onInit` is
what makes a *covered* deal-1 route safe to rebuild while deal 7 sits on top of
it: neither value is re-read from the global `Get.parameters` after `onInit`.

**Alternative rejected** *`Get.delete<DealDetailsController>()` before the
`lazyPut`, so each push starts clean.* Two lines, no tags, no screen change.
Rejected because it moves the symptom rather than removing it: the deal-1 route
is still on the stack and its `GetView.controller` resolves through the same
untagged key, so after deal 7 pops that page reads deal 7's disposed instance or
throws. "Wrong deal on push" becomes "wrong deal on pop", which is harder to
notice.

*`Get.create` + `GetWidget` instead of `lazyPut` + `GetView`.* This is the GetX
answer for genuinely multiple instances of one controller, and it needs no tag.
Rejected on two counts: `GetWidget` ties the instance to the widget rather than
the route, so `onClose` no longer runs via `RouterReportManager` on pop — which
is exactly the disposal RES-103 depends on — and it changes the DI convention
every other screen in the app follows, which CLAUDE.md §1 rules out.

*Re-read `Get.parameters` on the existing controller when the route changes,
and refetch.* One controller, no new instances. Rejected because one controller
cannot hold two deals: whatever the covered deal-1 page rebuilt from after the
refresh would be deal 7's data, unless it refetched on pop as well. That is
state being reassigned until the visible case looks right, which §3 names.

**Deliberately not fixed:** two pushes for the *same* id share a tag, so the
second reuses the first controller and inherits its `_source`. Sharing one
instance across two live routes does not risk the obvious thing — the second
route popping and deleting a controller the first still needs.
`reportDependencyLinkedToRoute` runs inside `_initDependencies` and only when
`!isInit` (`get_instance.dart:204-211`), so the instance is linked to the first
route alone. The second route's entry in `_routesKey` does not exist, its
disposal iterates nothing (`router_report.dart:91`), and the only reachable pop
order is second-then-first. The user sees the
correct deal, which is the requirement; the cost is analytics attribution on a
repeat link. Fixing it would mean a per-push identity (a counter or the Route
itself in the tag), which buys a second controller and a second fetch for a page
that is already correct on screen. A deep link carrying *no* parsable id has
tag `null`; two of those share one controller and both show the same "does not
point at a deal" message, which is also correct.

**Evidence** — PTP_N49 over USB, 2026-09-12 22:00–22:03, debug build.

| Step | Observed |
|---|---|
| deal 1 open → HOME → link `id=7` | `GET /deals/7`, `deal_details_view {deal_id: 7, source: push}`, screen renders **Surprise Bakery Box** (deals.json id 7, 3 left) |
| back | deal 1 renders in full — no crash, no "Instance not found" |
| Add to bag on deal 1 | `re-checking availability for deal 1` **×1** — RES-103 unaffected |
| deal 1 open → HOME → link `id=1` | still deal 1, no crash, no second fetch |
| tap from home feed | `deal_details_view {deal_id: 1, source: home}`, no `GET`, quantity chip renders — the check that would have caught the `_DealBody` regression |
| in-app dialog, `id=42` | `GET /deals/42`, renders Mystery Japanese Basket |
| Home open → HOME → link `id=7` | `GET /deals/7`, `deal_details_view {deal_id: 7, source: push}`, renders Surprise Bakery Box — the original warm-start path, re-checked after the tag change |

Screenshots: `docs/res-107/06-deeplink-over-open-deal-fixed.png`,
`docs/res-107/07-back-returns-to-working-deal-1.png`,
`docs/res-107/08-warm-start-from-home-recheck.png`.
`fvm flutter analyze` clean, `fvm flutter test` 15/15.

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

### The cart worker is never disposed — *resolved, this became RES-103's fix*

`deal_details_controller.dart` stores the `Worker` from `ever(...)` but has no
`onClose()` override, and GetX 4.7.3 does not dispose workers for a controller
(nothing under `get_state_manager/` or `get_instance/` references `Worker`). Every
deal screen visited leaves a live listener on the session-long
`CartService.itemCount`, so one add-to-bag fires one `fetchById` per deal viewed
this session. Observed directly during the RES-107 and stale-stock runs: deal 2
logged `re-checking availability` **twice** after being opened twice.

This is **RES-103**, so it became that ticket's fix rather than a finding acted
on here — kept in this list because it was found during the RES-107 work, not
by reading RES-103's ticket. Noted at the time because RES-107 changed its
shape: `onClose` can now run *before* the
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

A widget `State` is owned by the element tree. Flutter creates it, calls
`initState`, and calls `dispose` when the element leaves the tree; the lifecycle
is positional and the framework drives every step. A `GetxController` is owned by
GetX's service locator, not by any widget. Its `onInit`/`onClose` are driven by
registration and deletion — under the default `SmartManagement.full`
(`get_interface.dart:10`) a route's `Bindings` registers it and popping the route
deletes it — so its life is tied to a *route*, not to a subtree, and the same
instance can outlive or be shared across widgets that a `State` never would.

The crucial asymmetry is what each one cleans up. `State.dispose` is a hook the
framework guarantees will run; `GetxController.onClose` is the same guarantee, but
GetX does **not** clean up the things a controller creates. In `get` 4.7.3 nothing
under `get_state_manager/` or `get_instance/` so much as references `Worker`.

**RES-103** is the bug that exists because of that confusion. The controller calls
`ever(cartService.itemCount, …)` and discards the returned `Worker`, as if
registering the listener inside `onInit` bound it to the controller the way
`initState` work is bound to a `State`. It does not. `CartService` is
`permanent: true`, so the subscription outlives every screen, and each deal page
visited leaves another listener behind — four views produced four re-check
requests from one cart change. GetX disposed the controller correctly; the
subscription was never its to dispose, and `ever` returning a `Worker` is the API
saying so.

RES-102 is the mirror image and *not* the answer here: no controller is involved
at all, just a `State` that never implemented `dispose`. Naming it would be
guessing at the author's habits; RES-103's mechanism names itself.

**Q2 — When does wrapping a large subtree in a single `Obx` hurt, and how do you scope reactivity?**

A wide `Obx` is free until something inside it observes a value that changes
often. The cost is not the size of the subtree, it is the product of that size
and the notification rate of the *most frequently changing* thing read inside
it. RES-105 is the clean example: `HomeScreen` wrapped its whole `Scaffold` in
one `Obx`, which would have been harmless — the deal list changes on refresh and
paging, a handful of times a minute — except that its first statement read
`scrollOffset.value`, written on every scroll callback. That single line
promoted the entire feed to rebuilding once per rendered frame. Measured: 23
`Scaffold` builds in 23 frames, 385 `DealCard` objects constructed for 93 real
builds, `BUILD` costing 2.09 ms of a 16.7 ms budget on a 2018 device.

So the question to ask of any `Obx` is not "is this subtree big?" but "what is
the fastest-changing observable read anywhere inside it, and is the whole subtree
worth rebuilding at that rate?" One high-frequency value drags everything else
along with it.

Scoping it has two halves, and only doing the second is the common mistake:

1. **Narrow the scope to what the value actually affects.** Here that meant
   three `Obx` — AppBar, body, FAB — instead of one. Where the reactive value
   feeds a non-widget property, as with `AppBar.elevation`, the scope has to go
   somewhere the type system allows: `Scaffold.appBar` demands a
   `PreferredSizeWidget`, so the `Obx` moved inside a `PreferredSize`.

2. **Lower the notification rate at the source.** This is the half that
   mattered more. Narrowing alone would still have woken the AppBar's `Obx` 60
   to 120 times a second to produce the same elevation almost every time,
   because the notification comes from the `Rx` changing and a scroll offset
   changes continuously. The controller now publishes `isScrolled` and
   `showScrollToTop` as `RxBool` rather than the offset, and `Rx.value` skips
   notifying when the value is unchanged (`rx_impl.dart:101`), so each flag
   fires twice per journey down the feed. After: `Scaffold` builds **0** times
   across 86 frames, `BUILD` 0.045 ms per frame.

The general shape: put the derivation in the controller so the observable only
changes when the rendered output would change, then scope the `Obx` to the
widget that consumes it. Deriving `RxBool`s from a continuous value is cheap
precisely because GetX compares before notifying — the same property that makes
`.obs` on a raw offset so expensive is what makes the threshold flag free.

A caveat from the same ticket, because it cuts against over-applying this: the
`Obx` fix removed almost all UI-thread work during ordinary scrolling and did
**nothing** for the scroll-to-top animation, where the build work is real rather
than redundant. Reactivity scoping removes waste; it does not make genuine work
cheaper, and it is worth measuring which of the two you have before assuming.

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
