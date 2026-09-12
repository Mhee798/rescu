# AI usage log

Appended to **during** the work, never reconstructed afterwards.

An entry goes in whenever an AI suggestion is rejected, corrected, or found
wrong — the useful ones are those that looked plausible and actually ran. The
two strongest entries get lifted into `solutions.md`.

Format:

```
### <date> · <ticket>
Suggested: …
Why it was wrong / insufficient: …
How it was caught: …
Done instead: …
```

**Tools in use:**
- Claude Code (Opus 5) in the terminal, with access to the repo and to the live
  app on the test device. Does all editing, reproduction and writing.
- A second Claude Code session (`rescu-a4`) was run read-only over the same
  checkout on 2026-09-12 as an independent cross-check. It produced a code-read
  triage of RES-101..106 and wrote nothing to the repo (verified: clean `git
  status`, no branches, no worktrees). It was offered the chance to implement
  RES-101/102/106 on a branch and that was declined, for two reasons: the real
  bottleneck is one physical test device that RES-102, RES-105 and RES-106 all
  need serially (RES-106 requires changing the device timezone, which would
  corrupt any concurrent measurement), and PROBLEM.md states the diff is
  questioned line by line in the follow-up interview, so every line should come
  from a session that was actually watched. Its one novel finding is credited
  under RES-104 below.

---

## Time log

Start and stop times as they happen, so the total in `solutions.md` is real
rather than remembered.

| Date | Start | Stop | On |
|---|---|---|---|
| 2026-09-12 | 16:10 | 16:30 | Orientation, environment verification, baselines, scaffolding |
| 2026-09-12 | 16:30 | 17:10 | Own repo + remote hygiene; read every controller; RES-107 repro |
| 2026-09-12 | 17:10 | 17:50 | RES-107 fix, peer review round, lifecycle measurement, follow-up fixes |
| 2026-09-12 | 19:40 | 21:00 | Code review pass, RES-106/103/102 fixes, commit split, RES-102 negative control |
| 2026-09-12 | 21:40 | 22:09 | F1 deep-link-over-open-deal confirmation, per-id tag fix, seven-case device verification |
| 2026-09-12 | 22:10 | 23:15 | Peer review round on the tag fix; RES-105 investigation and baselines on two devices |

---

## Entries

### 2026-09-12 · RES-106 (a test I believed in that covered nothing)
**Suggested:** Having written `pickup_window_test.dart`, I guarded the one
offset-dependent assertion with an early `return` at `TZ=UTC` and commented that
"the assertion above still covers the conversion". I then reported the suite as
the evidence for RES-106 and committed it.

**Why it was wrong:** At offset zero `toLocal()` is the identity, so the derived
expectation evaluates to `'23:00 – 02:30'` — byte-identical to what the unfixed
getter produced. The entire label group passes *against the bug* at UTC. My
comment asserted the opposite, in a document written to be graded on the
strength of its evidence. The early `return` made it worse than a gap: a blind
spot that reports as a green test.

**How it was caught:** A review pointed at the line; I checked it rather than
taking either the comment or the reviewer on trust, with a scratch test printing
the old label and the derived expectation side by side. `OLD_WOULD_PASS=true` at
offset zero, `false` at +07.

**Done instead:** `markTestSkipped` so a UTC run reports `~1` instead of a pass,
and the coverage characterised precisely in `solutions.md` rather than claimed:
the suite catches the calendar half of RES-106 at any offset and is blind to the
zone half at offset zero. The precise version is worth more than the coverage
would have been. General lesson, and it is the same one as the RES-107 entry
below: I keep confirming the half of a condition I can see. There I sampled one
end of a latency distribution; here I reasoned about the non-UTC case and
asserted the UTC case.

### 2026-09-12 · RES-107 (my own reasoning, caught by repeating the measurement)
**Suggested:** A review pointed out that my RES-107 fix had opened a window
where the uncancellable deep-link fetch completes after `onClose`, registering
the cart worker on a disposed controller. I added an `isClosed` guard, rebuilt,
re-ran the repro with a back press 250ms after the push — and the leak was still
there. I concluded, and wrote to the user, that the hazard was not real, that
what I had measured was plain RES-103, that my guard was "not load-bearing", and
that I would remove it.

**Why it was wrong:** Both behaviours are real; they are different points on the
same random distribution. `getDealById` sleeps 200-700ms
(`fake_api_service.dart:84`) and the route's disposal lands ~550ms after the
push. A back press at 250ms usually lets the response win, so `_adopt` runs on a
live controller and registering the worker is correct — the leak seen then is
RES-103's missing disposal. A back press at 100ms puts `onClose` first, which is
exactly the case the guard exists for. One sample from one end of the
distribution looked like proof that the other end does not exist.

**How it was caught:** Instrumenting the two lifecycle points instead of
inferring their order, and running the probe six times instead of once. All six
runs at 100ms showed `onClose` first and no worker registration at all — the
guard firing. Then the end-to-end check: after aborting a deep link to deal 42,
a later add-to-bag re-checks only the deal actually viewed.

**Done instead:** Guard kept, with the measured numbers in the comment rather
than a vague "just in case". Had I shipped the removal I would have deleted a
correct fix on the strength of a single sample, and written a confidently wrong
paragraph into `solutions.md` explaining why the reviewer was mistaken.

### 2026-09-12 · RES-104 (cross-check catch)
**Suggested:** My own first pass listed `_page--` in `loadMore`'s catch block as
part of the duplicate-cards sequence — but wrote it into a sequence that
contains no error at all, so the clause was incoherent where it sat. On review I
deleted it rather than relocating it.

**Why it was wrong:** Deleting lost a real second defect. `_page--`
(`home_controller.dart:80`) runs on whatever `_page` holds *after* a concurrent
`refreshDeals` has reset it to 1, so a failed in-flight `loadMore` leaves
`_page = 0`; the next `loadMore` increments to 1 and refetches page 1 on top of
the refreshed list. That is a distinct duplication path from the
refresh-lands-first ordering, not the same one told badly.

**How it was caught:** A second session reading the same file independently
split it out as its own sub-case instead of folding it into the first. Verified
against the source before accepting it.

**Done instead:** Both paths recorded separately in the working checklist, to be
confirmed by reproduction before either goes into this file's RES-104 section.
Lesson kept: when a detail does not fit the story being told, the first move is
to check whether the story is too narrow, not to drop the detail.

### 2026-09-12 · RES-107
**Suggested:** Before reproducing, the assistant predicted the two deep-link
entry points would behave like this: because `GetMaterialApp` is given an
explicit `initialRoute: Routes.home`, `WidgetsApp` would ignore the platform's
`defaultRouteName`, so an **adb cold start would silently drop the link and open
Home**, while an **adb warm start would route via `didPushRoute` and crash**. The
reasoning was specific and cited the right framework mechanism, which is what
made it convincing.

**Why it was wrong:** It was exactly backwards. Cold start *does* honour the
platform route — logcat shows `analytics: screen_view {screen: /deal}` before
the throw, and the device renders the red `ErrorWidget`. Warm start is the one
that silently does nothing: the platform reports `intent has been delivered to
currently running top-most instance`, but the app neither navigates nor
crashes.

**How it was caught:** By running both, rather than reasoning further. Two
`am start` invocations plus a screenshot after each. Total cost was a couple of
minutes; had the prediction been written into `solutions.md` first it would have
been a confidently wrong root cause in a graded document.

**Done instead:** Both paths recorded as observations in `solutions.md` under
RES-107 Evidence, with the warm-start behaviour flagged as a *separate* defect
that is not on the crash's causal path — rather than folding it into the same
root cause. A second-order lesson also applies: the first `am start` attempt
silently truncated the URL to `?id=42` because the local shell ate the `&`, so
the first "warm start does nothing" data point was measured against the wrong
input and had to be redone with the argument quoted for the device shell.

### 2026-09-12 · RES-107 (a logcat filter that made a real bug look fixed)
**Suggested:** To check whether the deep link had produced a fetch, I filtered
the run output with `grep -E "I/flutter"`, the shape Flutter's console logs take
in `flutter run`'s default brief format. Nothing matched, so I began writing up
"F1 does not reproduce", and spent several minutes suspecting my own RES-107
change had regressed routing.

**Why it was wrong:** The device was being read in logcat's threadtime format,
where the same lines appear as `I flutter :` — space, not slash. The filter
matched nothing because of its own syntax, not because nothing happened. The
failure mode is the dangerous direction: an empty result reads as evidence of
absence.

**How it was caught:** Dumping the unfiltered tail instead of trusting the empty
filter. Every expected line was there.

**Done instead:** Filter on the app's own log prefix, which is identical in both
formats: `grep -oE "\[rescu [0-9:.]+\] .*"`. Used for every measurement since.
Standing rule taken from this: before believing a negative from a filter, prove
the filter can produce a positive.

### 2026-09-12 · F1 / RES-107 (repeating a lesson already written down)
**Suggested:** Re-running the deep-link repro, I fired
`adb shell am start -d "rescu://open/deal?id=1&source=push"` — the exact mistake
already recorded at the bottom of the RES-107 entry above, where the local shell
eats the `&`. Analytics then logged `source: unknown` and I briefly read that as
the fix having lost the `source` parameter. The correction I reached for next,
backslash-escaping the `&`, was also wrong in a quieter way: the backslash
survived into the intent, so `id=1\` failed `int.tryParse` and the app showed
"This link does not point at a deal." — a plausible-looking result for a test of
deep links that was actually testing a malformed one.

**Why it was wrong:** Twice I changed what the app was being asked to do while
believing I was changing only how I asked. Both produced output consistent with
a story about the app, which is why neither was obviously a harness fault.

**How it was caught:** A screenshot. The error text named the id as unparseable,
which no version of the code under test could produce from a well-formed link.

**Done instead:** Quote for the device shell, not the local one:
`adb shell "am start -a android.intent.action.VIEW -d 'rescu://open/deal?id=7&source=push'"`.
`source: push` came back immediately. The lesson worth keeping is not about
quoting — I had already written that one down — but that writing a lesson down
is not the same as having a check that applies it. The check here is cheap:
every deep-link measurement now starts by confirming the *expected* id and
source appear in the log line, before reading anything else from the run.

### 2026-09-12 · RES-105 (a device spec I wrote without reading it)
**Suggested:** The baseline document opened with a comparison table of the two
test devices, listing the PTP N49 at **16 GB** of RAM, and the memory section
then reasoned from it — "not the runaway the ticket describes, on 16 GB of RAM
with a 100 MB image cache". Every other figure in that document came from a
command whose output is quoted; this one came from nowhere.

**Why it was wrong:** `/proc/meminfo` reports `MemTotal: 11502928 kB` — 12 GB.
The error is small and changes no conclusion, which is exactly what makes it
worth an entry: it sat in a table where every neighbouring cell was measured,
so it inherited their credibility. In a document whose whole argument is "here
are the numbers, run the commands yourself", one invented cell is the kind of
thing that makes a reader re-check the ones that matter.

**How it was caught:** The user knew the phone. I had not run `cat
/proc/meminfo` on that device at all — the ELE-L29's figure came from a real
command, and I filled the other column in by assumption while writing the table.

**Done instead:** Both cells now carry the raw `MemTotal` alongside the rounded
figure, so the number is checkable rather than assertable. Rule taken from it:
if a value is going into a table of measurements, it gets a command, even when
it is "just" a spec.

### 2026-09-12 · RES-105 (a malformed request that killed the app under test)
**Suggested:** To record a timeline over the VM Service HTTP interface I called
`setVMTimelineFlags?recordedStreams=Dart,Embedder`, having already had
`recordedStreams=["Dart","Embedder"]` rejected as invalid params.

**Why it was wrong:** The HTTP interface hands every query parameter to the RPC
as a string, and the VM expects a list. The unbracketed form did not return an
error — it segfaulted the Dart VM (`Fatal signal 11 (SIGSEGV)` in
`__strlen_aarch64` on a DartWorker thread), taking the app and the profiling
session with it. A measurement harness that can kill the thing being measured is
worse than one that refuses to run.

**How it was caught:** `curl` started returning nothing; the run log ended in a
native stack trace and `Lost connection to device`.

**Done instead:** The accepted form is `recordedStreams=[Dart,Embedder]` —
brackets, no quotes. Restarted and re-measured. The wider point is that the two
rejected forms failed very differently and only one of them said so; after this,
any VM Service call that has not returned a clean result is verified with
`getVersion` before the next one is sent.

### 2026-09-12 · RES-105 (a measurement window that contained none of the thing being measured)
**Suggested:** After capturing dropped frames on the ELE-L29 by having a person
flick the device hard, I ran the identical procedure on the PTP N49 and got
`Animator::BeginFrame` 0 frames over budget at a steady 121 fps. The obvious
reading — and the one I was about to write — is "the flagship absorbs it
completely", which also happens to be the conclusion I already expected.

**Why it was wrong:** The window contained almost no work. `BUILD` totalled
28 ms across six seconds, against 730 ms for the same gesture on the other
device. At 120 Hz the flagship's fling clears a 122-card feed in about a second,
and the VM timeline's ring buffer retains only the last few seconds — so what
was captured was the overscroll bounce at the bottom of the list, a screen doing
nothing. "Zero dropped frames" was true of a static screen.

**How it was caught:** The `BUILD` total, checked before reading anything else,
precisely because the first attempt on this device had already produced a
suspiciously quiet capture. Then confirmed instead of guessed: a scripted swipe
taken while parked at the bottom gives 0.041 ms of BUILD per frame, the same
swipe from the top of the feed gives 1.216 ms.

**Done instead:** Cross-device comparison moved to a scripted swipe from a known
scroll position with the feed loaded to the same depth — reproducible, and it
cannot silently measure a bottom bounce. The hand flick is kept only for the
ELE-L29, where the capture is verifiable. The wider lesson is the one this log
keeps relearning from a new angle: a quiet result needs the same scrutiny as a
loud one, and here it needed *more*, because it agreed with what I expected.

### 2026-09-12 · RES-105 (numbers inflated by the instrument that produced them)
**Suggested:** I reported `Obx` build durations of 3.38 ms and 1.37 ms as the
per-rebuild cost on the two devices, and wrote that "every scroll frame spends
3.38 ms of a 16.7 ms budget" into the baseline document.

**Why it was wrong:** Those came from timelines recorded with
`ext.flutter.profileWidgetBuilds` enabled, which wraps every widget build in a
timeline event. The spans nest, so a parent's duration includes its children's
and the totals double-count, and the instrumentation is itself overhead that
would not be present in the app as shipped. It is the measurement equivalent of
quoting a debug-mode frame time.

**How it was caught:** Re-running with tracking off to get a clean cross-device
comparison, and finding the phase-level `BUILD` cost was 1.22 ms per frame on
*both* devices — nothing like the 2.5× spread the instrumented per-widget
figures implied.

**Done instead:** Phase-level `BUILD` and `LAYOUT` with tracking off are now the
reported cost; the per-widget numbers are marked superseded in the document
rather than deleted, since they were the more dramatic ones and a reader
comparing revisions should see which way the correction went. Widget-build
tracking is still used, but only for *counting* rebuilds, which is what it is
reliable for.
