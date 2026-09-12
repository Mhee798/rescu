# RES-105 · baseline measurements

Device: PTP N49 (SM8750), 1280×2800 @ density 560 (DPR 3.5), display supports
60/90/120 Hz. Build: `fvm flutter run --profile`, 2026-09-12 22:29–22:36.

This is a **high-end** device. The ticket describes the symptoms on *mid-range*
Android. Both halves of what follows matter: the structural counts reproduce the
ticket's description exactly, and the frame times say this particular phone
absorbs the cost. The numbers are recorded rather than summarised so the
after-figures can be compared against the same procedure.

## Widget rebuilds during one scroll

Method: VM Service over the `flutter run --profile` URI —
`setVMTimelineFlags?recordedStreams=[Dart,Embedder]`,
`ext.flutter.profileWidgetBuilds?enabled=true`, `clearVMTimeline`, one
`adb shell input swipe 640 2000 640 900 400`, then `getVMTimeline`.
32,679 events in the window; 83 `Animator::BeginFrame`.

| Widget | build events in one swipe |
|---|---|
| `Scaffold` / `AppBar` / `SmartRefresher` / `ListView` / `FlashDealsSection` | **26 each** |
| `Obx` | 26 |
| `FilterChip` | 27 |
| `DealCard` | 112 |
| `TheNetworkImage` / `CachedNetworkImage` / `OctoImage` / `Image` / `RawImage` | 216 each |

The whole `Scaffold` subtree rebuilding 26 times for a single swipe is the
ticket's "the entire feed rebuilding continuously during scroll", measured.

Note what the same data rules *out*: `DealCard` builds 112 times across 26
parent rebuilds — about 4.3 per rebuild, i.e. only the cards in the viewport
plus cache extent. `ListView(children: [...])` does not keep off-screen card
*elements* alive. Its cost is that the spread constructs one `DealCard` **widget
object** per deal — 100+ of them — on every one of those 26 rebuilds, together
with the fresh `List` that `visibleDeals` returns each time. Allocation churn,
not retention.

## Frame times — no jank on this device

From the same timeline (microseconds → ms):

| | n | p50 | p90 | p99 | max | >8.3 ms | >16.7 ms |
|---|---|---|---|---|---|---|---|
| `Animator::BeginFrame` (UI) | 83 | 0.60 | 4.03 | 6.00 | 6.00 | 0 | 0 |
| `Rasterizer::DoDraw` (raster) | 83 | 1.63 | 2.27 | 2.59 | 2.59 | 0 | 0 |

Zero frames over even the 120 Hz budget. **The jank half of RES-105 does not
reproduce on this hardware.**

## Memory — grows, but nothing like "until the OS kills the app"

`adb shell dumpsys meminfo dev.rescu.rescu`, fresh launch, then 20 swipes at a
time. Reached page 5 of 7 (`GET /deals?page=5` in logcat), so ~100 of the 122
deals were scrolled past.

| point | TOTAL PSS | Native Heap | Graphics |
|---|---|---|---|
| Home loaded, no scroll | 205,862 kB | 48,220 | 75,720 |
| after 20 swipes | 195,785 kB | 44,452 | 69,168 |
| after 40 swipes | 201,561 kB | 48,976 | 69,480 |
| after 60 swipes | 211,307 kB | 57,888 | 70,048 |

+5.4 MB PSS across ~100 deals, and it dips before it climbs. Not the runaway the
ticket describes — on 16 GB of RAM with a 100 MB image cache that is already
full at the first screen.

## Image sizing — arithmetic, not yet an isolated measurement

`fake_api_service.dart:267` serves every deal image as
`picsum.photos/seed/<seed>/1600/1200`, and `TheNetworkImage` passes no
`memCacheWidth`/`cacheWidth`. Decoded RGBA cost is fixed at 1600×1200×4 =
**7.68 MB per distinct image** regardless of the slot it lands in.

At this device's DPR of 3.5:

| slot | physical px | decode actually needed (cover) | served | waste |
|---|---|---|---|---|
| feed card, 160 dp tall × (365.7−32) dp wide | 1168 × 560 | 1168 × 876 → 4.09 MB | 7.68 MB | ×1.9 |
| flash rail, 90 dp × 200 dp | 700 × 315 | 700 × 525 → 1.47 MB | 7.68 MB | ×5.2 |
| details header, 240 dp × full width | 1280 × 840 | 1280 × 960 → 4.92 MB | 7.68 MB | ×1.6 |

So "1600×1200 into a 160 px slot" overstates it — the slot is 160 *logical* px
tall but 1168 physical px wide, and `BoxFit.cover` is width-bound. The real
multiplier on the feed is about 2×, and about 5× on the rail.

The sharper consequence is the cache, not the per-image waste: Flutter's
`ImageCache` defaults to 100 MB, which holds **13** images at 7.68 MB each. A
122-deal feed cannot keep even two screens' worth resident, so scrolling evicts
and re-decodes continuously. That is consistent with the `Graphics` figure
sitting flat at ~70 MB rather than climbing — the cache is not growing, it is
saturated.

**Not yet isolated.** No before/after decode measurement has been taken; the
above is arithmetic from the source and the device's density.
