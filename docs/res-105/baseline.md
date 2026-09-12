# RES-105 · baseline measurements

Measured on **two** devices, because the first one was too fast to show the
symptom the ticket describes:

| | PTP N49 | ELE-L29 |
|---|---|---|
| SoC | Snapdragon 8 Elite (SM8750), 2024 | Kirin 980, 2018 |
| OS | Android 16 (API 36) | Android 10 (API 29) |
| Screen | 1280×2800, density 560 (DPR 3.5) | 1080×2340, density 480 (DPR 3.0) |
| Refresh | 60/90/120 Hz | 60 Hz |
| RAM | 12 GB (`MemTotal` 11,502,928 kB) | 8 GB (`MemTotal` 7,789,116 kB) |

Build: `fvm flutter run --profile`, 2026-09-12 22:29–23:10. The ELE-L29 is the
"mid-range Android" the ticket is written about; the PTP N49 is not. Both sets
of numbers are kept, because the difference between them is itself the finding:
the *structural* defects are identical on both, and only the second device turns
them into a frame-time cost.

## Widget rebuilds during one scroll

Method: VM Service over the `flutter run --profile` URI —
`setVMTimelineFlags?recordedStreams=[Dart,Embedder]`,
`ext.flutter.profileWidgetBuilds?enabled=true`, `getAllocationProfile?reset=true`,
`clearVMTimeline`, one `adb shell input swipe 640 2000 640 900 400`, then
`getVMTimeline` and `getAllocationProfile` over the same window.

| | count in one swipe |
|---|---|
| `Animator::BeginFrame` (frames) | **23** |
| `Obx` builds | **23** |
| `Scaffold` builds | **23** |
| `AppBar` builds | 23 |
| `DealCard` builds | 93 |
| `TheNetworkImage` builds | 93 |

**One full `Scaffold` rebuild per rendered frame — 23 out of 23.** Not "often
during scroll": every single scroll frame rebuilds the entire feed subtree. That
is the ticket's "the entire feed rebuilding continuously during scroll", and it
is the one symptom that reproduces exactly as written on this device.

Allocation over the identical window (`instancesAccumulated`):

| class | instances | bytes |
|---|---|---|
| `_List` | 24,509 | 1,270,432 |
| `_GrowableList` | 5,607 | 179,424 |
| `DealCard` | 385 | 12,320 |
| `InkWell` | 95 | 15,200 |
| `CachedNetworkImage` | 41 | 4,592 |
| `DealModel` | 54 | 4,320 |

`DealCard`: 385 objects constructed, 93 of them actually built. The gap is the
cost of `...visibleDeals.map((deal) => DealCard(deal: deal))` inside the `Obx` —
the spread constructs one widget per loaded deal on every one of the 23
rebuilds, while the sliver only calls `build()` on the four or so in the
viewport. 1.27 MB of `_List` churn in 400 ms comes from the same place, together
with the fresh list `visibleDeals` returns each time.

Note what the same data rules *out*: `ListView(children: [...])` does **not**
keep off-screen card elements alive — 93 builds across 23 parent rebuilds is
roughly the viewport plus cache extent. The cost here is allocation churn, not
retention.

## Cross-device comparison — identical procedure, no human variance

Both devices: feed loaded to `page=4`, scrolled back to the top with the FAB,
one `input swipe` of 400 ms, `profileWidgetBuilds` **off** so the measurement is
free-running rather than instrumented.

| | BUILD /frame | LAYOUT /frame | UI p50 | UI p90 | raster p50 | raster p90 | raster max | frames over budget |
|---|---|---|---|---|---|---|---|---|
| ELE-L29 · 60 Hz, budget 16.67 ms | **1.223 ms** | 0.942 ms | 1.94 | 5.60 | **10.15** | **14.02** | **34.01** | 2 (raster) |
| PTP N49 · 120 Hz, budget 8.33 ms | **1.216 ms** | 0.892 ms | 1.72 | 3.45 | 1.68 | 2.57 | 3.33 | 0 |

Two things fall out of this that were not obvious before.

**The widget-build cost is the same on both devices — 1.22 ms per frame.** The
Dart work does not care how fast the phone is to anything like the degree the
raster work does. As a *fraction of the frame budget* it is therefore **worse on
the flagship**: 1.22 ms of 8.33 ms at 120 Hz is 15 %, against 7 % of the
ELE-L29's 16.67 ms. Causes ① and ② are not a "slow phone" problem.

**Raster is where the older device dies — 6× slower at p50** (10.15 ms against
1.68 ms), sitting at 61 % of its budget before anything unusual happens, with a
34.01 ms outlier in an 87-frame window. Raster is where oversized image textures
are encoded and uploaded, which is cause ③.

So the three causes do not hurt the same device: the rebuild churn is
proportionally worst at 120 Hz, and the image decode is what actually drops
frames at 60 Hz.

### Superseded: the per-widget durations reported earlier

An earlier pass reported `Obx` build durations of 3.38 ms (ELE-L29) and 1.37 ms
(PTP N49). Those were captured with `ext.flutter.profileWidgetBuilds` **enabled**,
which wraps every widget build in a timeline event, and the spans nest, so the
numbers double-count and are not free-running frame cost. The phase-level
`BUILD` figures in the table above replace them. Keeping the retraction visible
because the superseded numbers were the more dramatic ones.

## Frame times — the ticket's symptom needs the older device

### ELE-L29 (Kirin 980, 60 Hz, budget 16.7 ms)

Single swipe, 97 frames:

| | n | p50 | p90 | p99 | max | >8.3 ms | >16.7 ms |
|---|---|---|---|---|---|---|---|
| `Animator::BeginFrame` (UI) | 97 | 2.20 | 9.51 | 11.49 | 11.49 | 14 | 0 |
| `Rasterizer::DoDraw` (raster) | 97 | 9.96 | 12.76 | 15.68 | 15.68 | 65 | 0 |

Raster sits at **76 % of the frame budget at p90** and two thirds of frames are
over half the budget. A longer eight-swipe run pushed one raster frame to
19.88 ms — over budget, i.e. a dropped frame. So under a scripted swipe the
headroom is thin rather than gone.

#### Flicked by hand, it drops frames

`adb shell input swipe` is a slow, even drag; it does not produce the velocity a
thumb does. Repeated with a person flicking the device hard for several seconds
(adb over Wi-Fi, so holding the phone could not disturb the connection — the
first attempt over USB lost the cable mid-flick and the capture with it). The
ring buffer retained the last 3.98 s, 231 frames:

| | n | p50 | p90 | p99 | max | >16.7 ms | >33.3 ms |
|---|---|---|---|---|---|---|---|
| `Animator::BeginFrame` (UI) | 231 | 6.00 | 9.49 | 23.91 | **28.80** | 4 | 0 |
| `Rasterizer::DoDraw` (raster) | 229 | 8.04 | 13.59 | 32.23 | **36.99** | 11 | 1 |

**15 frames over budget in four seconds** — against zero for the scripted swipe
on the same device. The worst raster frame took 36.99 ms, more than two vsync
periods. This is the ticket's symptom, and it needed both the older device and a
real flick to appear.

What is inside the frames that dropped:

| frame | dominant child |
|---|---|
| UI, 28.80 ms | `BUILD` **24.78 ms** |
| UI, 23.91 ms | `FINALIZE TREE` 16.52 ms |
| raster, 36.99 ms | `SurfaceFrame::Encode` 33.52 ms |
| raster, 32.23 ms | `SurfaceFrame::Encode` 29.26 ms |

**The same flick could not be captured on the PTP N49.** Two attempts returned
BUILD totals of 37.4 ms and 28.1 ms over ~6 s windows, against the ELE-L29's
730 ms — not a fast phone, an empty measurement. The cause: at 120 Hz with that
fling velocity the flagship reaches the end of a 122-card feed inside the
captured window, and the VM timeline's ring buffer only retains the *last* few
seconds, which is the bottom overscroll bounce. Confirmed rather than assumed —
a scripted swipe taken while parked at the bottom gives BUILD 0.041 ms/frame,
and the identical swipe from the top gives 1.216 ms/frame. The cross-device
table above uses the scripted procedure for exactly this reason.

The worst UI frame is 86 % widget building — the `Obx` closure reconstructing
the `Scaffold` and every loaded `DealCard`. `FINALIZE TREE` at 16.52 ms in
another is the element tree churning behind the same rebuild. The raster frames
are texture encode and upload, which is where the 1600×1200 decodes land.

Phase totals across the 3.98 s window:

| phase | n | p50 | p90 | max | total |
|---|---|---|---|---|---|
| `BUILD` | 507 | 1.45 | 2.54 | 21.96 | **730.3 ms** |
| `LAYOUT (root)` | 230 | 2.43 | 5.01 | 19.34 | 561.7 ms |
| `PAINT (root)` | 230 | 1.42 | 1.97 | 4.50 | 325.6 ms |
| `FINALIZE TREE` | 230 | 0.01 | 0.46 | 16.52 | 43.5 ms |
| `SurfaceFrame::Encode` | 230 | 5.20 | 8.37 | 33.52 | **1392.2 ms** |

`BUILD` consumes **18.3 %** of wall-clock time during the flick. Not all of that
is waste — some rebuilding is real — but on this screen the `Obx` scope means
every one of those builds reconstructs the entire feed subtree.

Caveat on reading these: `BUILD` appears 507 times against 230 frames, so the
spans nest and the per-event percentiles are not per-frame figures. The totals
and the per-frame breakdowns above are the trustworthy parts. The flick duration
was also not controlled — the window is whatever the ring buffer still held.

### PTP N49 — no jank at all

| | n | p50 | p90 | p99 | max | >8.3 ms | >16.7 ms |
|---|---|---|---|---|---|---|---|
| `Animator::BeginFrame` (UI) | 83 | 0.60 | 4.03 | 6.00 | 6.00 | 0 | 0 |
| `Rasterizer::DoDraw` (raster) | 83 | 1.63 | 2.27 | 2.59 | 2.59 | 0 | 0 |

Zero frames over even the 120 Hz budget; raster p90 is **5.6× faster** than the
ELE-L29's. The jank half of RES-105 does not reproduce on this hardware at all,
which is why the second device was brought in.

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

+5.4 MB PSS across ~100 deals, and it dips before it climbs.

ELE-L29, same procedure, and this run reached `GET /deals?page=7` — **all 122
deals**. This device reports image memory under Native Heap rather than
Graphics (`GL mtrack` stays at 684 kB throughout):

| point | Native Heap |
|---|---|
| Home loaded, no scroll | 27,580 kB |
| after 20 swipes | 32,664 kB |
| after 40 swipes | 38,248 kB |
| after 60 swipes | 37,332 kB |

+10 MB, then it **plateaus and dips** — the third reading is lower than the
second. Total PSS at the end: 93,872 kB.

**The "memory keeps climbing until the OS kills the app" symptom does not
reproduce on either device**, including the one that does show the frame cost.
That is what an `ImageCache` doing its job looks like: it is not leaking, it is
saturated at its 100 MB ceiling and evicting. The cost lands on decode work —
frame time — not on retention. Stated plainly because it contradicts the
ticket's wording, and the write-up should not claim a memory improvement it
cannot measure.

## Image sizing — measured, and worse than my own arithmetic said

`fake_api_service.dart:267` serves every deal image as
`picsum.photos/seed/<seed>/1600/1200`, and `TheNetworkImage` passes no
`memCacheWidth`/`cacheWidth`, so the decode size is fixed regardless of the slot.

Measured rather than derived: a debug run with
`ext.flutter.invertOversizedImages` enabled over the VM Service, then twelve
swipes through the feed. Flutter reports, once per painted card image:

```
Image null has a display size of 1168×560 but a decode size of 1600×1200,
which uses an additional 6593KB (assuming a device pixel ratio of 3.5).
```

That is the framework's own accounting, not an estimate of mine, and its formula
is `w × h × 4 × 4/3` (`painting/debug.dart:93-97` — four bytes per pixel plus a
third for mipmaps):

| | pixels | bytes by that formula |
|---|---|---|
| decoded | 1600 × 1200 | 10,240,000 (10,000 KB) |
| needed for the slot | 1168 × 560 | 3,488,426 (3,406 KB) |
| **overhead per image** | | **6,751,573 (6,593 KB)** |

So each feed card costs **2.94×** the memory it needs, and the fix Flutter itself
names in the same message is `cacheWidth: 1168`.

My earlier note in this file put the multiplier at about 1.9× by assuming four
bytes per pixel and comparing against a `BoxFit.cover` crop. Both were wrong:
the framework counts the mipmap third, and it compares against the destination
rectangle, not the cropped source. The measured figure supersedes it.

The consequence is the cache, not the per-image waste. Flutter's `ImageCache`
defaults to 100 MB, which holds **ten** images at 10 MB each. A 122-deal feed
cannot keep two screens resident, so scrolling evicts and re-decodes
continuously — consistent with `Graphics` sitting flat at ~70 MB rather than
climbing: the cache is not growing, it is saturated.

The flash rail (90 dp × 200 dp) and the details header (240 dp, full width) load
the same 1600×1200 asset and were not separately measured.
