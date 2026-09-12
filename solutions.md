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
**Status** not started

**Symptom** `rescu://open/deal?id=42&source=push` crashes with `type 'Null' is not a subtype of type 'DealModel'`. The same deal opens fine from the home feed. A fallback/error screen is explicitly not an acceptable resolution.

**Root cause** —
**Fix** —
**Alternative rejected** —
**Edge cases** —
**Evidence** —

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
