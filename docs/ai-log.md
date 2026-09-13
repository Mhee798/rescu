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
| 2026-09-13 | 23:15 | 02:10 | RES-105 fixes, per-cause attribution, refresh-rate isolation, fling before/after, review round |
| 2026-09-13 | 02:10 | 03:40 | RES-105 review follow-ups, re-verification of every figure on the shipped build |
| 2026-09-13 | 15:40 | 18:00 | RES-104 investigation, scripted-ordering tests, ablation, failed device repro, write-up |
| 2026-09-13 | 18:00 | 19:30 | RES-104 review round: footer hang, harness traps, doc corrections |
| 2026-09-13 | 19:30 | 21:00 | RES-101 repro, design comparison, fix, ablation, device verification, write-up |

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

**Correction, 2026-09-13, after reproducing RES-104.** Calling `_page--` "a
real second defect" was too strong, and the deferral above is the only reason
it did not reach `solutions.md` that way. The rollback is unreachable in this
app: `getDeals` never throws, and `_rng` in `fake_api_service.dart` is used only
for latency and search breadth. It is a latent path, and the ticket's live cause
is the single one — a counter left describing a list it no longer matches. The
fix deletes the rollback anyway rather than leaving it armed, and the test that
covers it has to inject a failure through the scripted repo to reach it. Two
sessions agreeing on a mechanism is not the same as either of them checking
whether it can run.

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

### 2026-09-13 · RES-105 (an estimate sitting in a table of measurements)
**Suggested:** The RES-105 write-up stated that `ImageCache`'s 100 MB default
"holds ten images" before the fix and about twenty-six after, and put that row
in the same table as the decode sizes Flutter had reported directly. I also
wrote that the process memory figures showed a cache "saturated at its 100 MB
ceiling and evicting", and rested the ticket's second symptom on it.

**Why it was wrong:** Two numbers in that section could not both be true. Native
Heap peaked at 38 MB while the cache was described as holding 100 MB. Decoded
pixel buffers are Skia allocations and do not appear in that field, so the
`dumpsys meminfo` figures were measuring a pool the images are not in — the
memory half of the ticket was *unmeasured*, not "does not reproduce". The
image-count row was derived arithmetic surrounded by measured cells, which lent
it a credibility it had not earned, and it was also simply wrong: `ImageCache`
counts raw `w × h × 4`, while the `debugInvertOversizedImages` message I divided
by adds a mipmap third. Ten should have been thirteen.

**How it was caught:** A review pointed at the contradiction between the two
figures rather than at either one. Settled with the counter that defines the
thing — `imageCache.currentSize` and `.currentSizeBytes`, logged once a second
from a temporary probe in `main()`, removed afterwards. Control peaks at 13
images / 95.2 MB; fixed at 36 / 99.7 MB. Per image, 7,680,000 B = 1600×1200×4
and 2,904,768 B = 984×738×4 exactly.

**Done instead:** The conclusion survived — both builds saturate the ceiling, so
the cache evicts rather than growing without bound — but the evidence for it was
replaced wholesale, and what the fix buys is restated as 2.8× more images
resident rather than as any reduction in footprint. The rule taken from it: when
a document is mostly measurements, a derived number has to be labelled as one or
measured, because it will otherwise be read at the same weight as its
neighbours. The tell was available before the review — I had two numbers about
the same thing that disagreed by a factor of two and did not put them side by
side.

### 2026-09-13 · RES-105 (the fifth time, and the first time I caught it myself)
**Suggested:** Having written that the frames still dropping after the fix might
be image decode on the raster thread, I built a prefetching variant —
`precacheImage` four cards ahead — and measured 0, 1, 1 dropped frames against
the fixed build's 4, 4, 7. UI p90 6.11 against 8.89, raster p90 10.39 against
14.28. Every number moved the right way, the cache-key check passed exactly
(peak cache identical to the byte, so nothing was being decoded twice), and the
mechanism was one I had predicted in writing beforehand. It was ready to report.

**Why it was wrong:** The comparison was against a fixed-build measurement taken
an hour earlier. Re-running the *unmodified* fixed build immediately after the
experiment gave 2, 0, 6 and `BUILD` per frame of 0.428 ms against the earlier
sitting's 0.631 ms. The prefetch build's 0.424 ms is the same number. There was
no effect; there was drift between sittings, and the experiment had been
compared against a stale baseline.

**How it was caught:** By noticing a flaw in my own experiment before reading
the result as a win — the `_requested` set meant prefetching could only fire for
images never seen before, and the measurement runs came after sixty swipes
through the whole feed, so during the measured flings the prefetch code was
doing nothing but set lookups. A change that cannot act should not produce a 7×
improvement. That is what prompted the re-run rather than the write-up.

**Done instead:** Neither candidate adopted. The `RepaintBoundary` half was
settled by reading `scroll_delegate.dart:505` — the framework already adds one
per child — and the prefetch half is recorded as a failed experiment rather than
omitted. The headline for the ticket was loosened at the same time, from "26 →
15" to "a median of 9 dropped frames per run against 4", because the same
re-run showed the fixed side varies by 50 % between sittings while the control's
three runs agree to 5 %.

This is the fifth entry in this log with one shape: a result that agreed with
what I expected, produced by a measurement that had not been repeated. The
earlier four were caught by a reviewer or by the user. The rule I am taking
forward is narrower than "measure twice" — it is that a baseline is only valid
for the sitting it was taken in, so any A/B comparison has to include a fresh
control, and that a change which cannot mechanically act must never be credited
with an effect no matter how good the numbers look.

### 2026-09-13 · RES-105 (a test written to prove a fix, which proved something else)
**Suggested:** Narrowing the `Obx` around the FAB lost its scale-in animation. I
read `_FloatingActionButtonTransition.didUpdateWidget`, found an early return
when both children are non-null and their keys compare equal
(`scaffold.dart:1368`), gave the two branches distinct `ValueKey`s, and — because
I had just told the user that fixing something from source reading alone
violates our own §4 — wrote `test/home_fab_transition_test.dart` to prove it.
The test passed, with a second case as a control. I reported the item closed.

**Why it was wrong:** The keys change nothing. `didUpdateWidget` runs when the
**`Scaffold`** rebuilds; an `Obx` rebuilds itself and never its parent, so that
method is unreachable from this screen and the keys are never compared. The
`ScaleTransition` sits at 1.0 from mount, because `Obx` is non-null on the first
frame. The button had been popping in at full size the whole time.

The test passed because it toggled the branch with `pumpWidget`, which rebuilds
the `Scaffold` and therefore *does* reach `didUpdateWidget`. It asserted a true
property of `Scaffold` that the app never exercises. It even had a control — the
unkeyed case, reaching full size in one frame — and the control passed too,
because both cases were measuring the same irrelevant path. A control only
guards against the failure it is aimed at.

**How it was caught:** A code review, which reproduced the production shape in a
probe rather than re-reading the diff. I then wrote the same probe myself:
`Scaffold(floatingActionButton: Obx(...))`, flip the `Rx`, pump — scale reads
1.0 before, immediately after, and 380 ms later.

**Done instead:** `AnimatedScale` inside the `Obx`, with `IgnorePointer` because
a zero-scale `Transform` keeps its layout slot and stays tappable. The test now
mounts the production shape and drives it through the `Rx`. The lesson is not
"write a test" — I did — it is that a test written from the same mental model as
the fix inherits its error, and that the shape being pumped has to match the
shape that ships. The cheapest guard is the one the reviewer used: before
trusting a passing test, check that it fails against the unfixed code *in the
real tree*, not in the arrangement the test finds convenient.

The same review found a second defect in the same diff: the image decode hint
constrained the width whenever the box was not taller than wide, which is a 1:1
test where the source's 4:3 was meant, so the 64×64 thumbnails in the cart and
orders screens decoded 192×144 and were upscaled 1.33× — a blur I introduced on
two screens I had never opened. My comment said "all three call sites"; there
are five. Fixed and verified on device. The pattern there is plainer: I
enumerated the call sites from the ones I had been thinking about rather than
from `grep`.


### 2026-09-13 · RES-104 (three guards, and only one of them was doing anything)
**Suggested:** The RES-104 fix added a generation counter checked in both
writers, an `_isRefreshing` flag, and moved the page counter to advance only
after a successful response. Seven scripted-ordering tests passed, four of them
failing against the pre-fix controller. That is the shape of a finished ticket.

**Why it was wrong:** It was not wrong, but three quarters of it was unjustified.
Removing each guard in turn to check it was load-bearing — the habit taken from
the FAB `ValueKey`s that turned out to be decoration — showed that only
`_isRefreshing` broke anything. The two generation checks and the deferred
counter could all be deleted with the suite still green. I had written three
guards and tested one.

**How it was caught:** The ablation, run because of the previous entry rather
than because anything looked wrong. The reason the tests could not see the other
two is worth more than the finding: two responses for the same page are
identical, so a stale one being written over a newer one leaves no trace in the
list. There was nothing to assert on.

**Done instead:** The scripted repo now varies `totalPages` per response, which
makes "which response won" observable through `hasMore`, and two cases were
added for the orderings only the generation checks cover. A third injects a
failed request, which is the only way to reach the counter rollback. All four
guards then ablate to a failure. The rule: if a guard cannot be removed to make
a test fail, either it does not belong in the diff or the test cannot see what
it does — and the second is worth a few minutes before assuming the first.

### 2026-09-13 · RES-104 (a stash that silently staged a revert)
**Suggested:** To measure the test suite against the unfixed controller I used
`git stash push` on the one file, ran the suite, and `git stash pop`ped it back.
The suite behaved as expected and I moved on.

**Why it was wrong:** The pop left the index holding the *pre-fix* version:
`git status` read `MM`, staged showing "11 insertions, 38 deletions" — which is
the RES-104 fix being removed — on top of an unstaged debug probe. Any `git
commit` at that point, for any reason, would have quietly reverted the fix and
committed a temporary probe alongside it.

**How it was caught:** Answering "is RES-104 done" by running `git status`
rather than by recalling what I had done. The tests were green the whole time,
because they run against the working tree, not the index.

**Done instead:** `git restore --staged --worktree` on the file, then verified
by grepping the source for the probe marker (0) and the fix's own identifier
(6). Rule: use a throwaway copy for ablations, not the index; and when a file
has been temporarily replaced for measurement, check `git status` before the
next commit rather than after.
### 2026-09-13 · RES-104 (a guard that hangs the thing it guards)
**Suggested:** The `_isRefreshing` guard I added to `loadMore` returned early,
matching the `_isFetchingMore` return directly above it. I wrote in
`solutions.md` that the resulting footer-state problem "was true of the existing
`_isFetchingMore` guard before this change", filed it under deliberately not
handled, and moved on.

**Why it was wrong:** The two returns are not equivalent, and the difference is
the whole point. SmartRefresher puts the footer into `LoadStatus.loading` before
calling `onLoading`, and only `loadComplete`/`loadNoData`/`loadFailed` move it
out. The load that set `_isFetchingMore` reaches `loadComplete()` on its own way
out, so that return is self-healing. `refreshDeals` reaches only
`refreshCompleted()`, which touches the header
(`smart_refresher.dart:753`) — so my return left the spinner up for good, and
because `_dispatchModeByOffset` bails while the mode is `loading`
(`indicator_wrap.dart:466`), pull-up would have been dead for the rest of the
session. I introduced a hang and then documented it as pre-existing.

**How it was caught:** A code review, which read the package source rather than
the diff. The seven ordering tests could not have caught it: every assertion was
about `deals` and the page counter, and the refresh controller was a sink. A
guard that returns early is only correct if everything it skipped is either
unnecessary or done by someone else, and nothing in the suite could tell those
two apart.

**Done instead:** `loadComplete()` before the return, plus the first two tests
in that file to assert on `footerStatus`. Getting them to run took two more
mistakes worth keeping: `seed()` awaits a zero-duration `Future`, which never
resolves inside `testWidgets`'s FakeAsync, so the test *hung* — and I read the
suite's trailing line as a pass twice before noticing it never said "All tests
passed". Then, with that fixed, both cases still failed: `loadComplete()` defers
to a post-frame callback and `tester.pump()` produces no frame unless one is
already scheduled, so the callback never ran. `tester.binding.scheduleFrame()`
first. Both of those would have made the test lie in the safe direction — a
false failure — but the FakeAsync one cost twenty minutes because a hang reads
like a slow pass.

The lesson that generalises: an early return is a claim that the work being
skipped does not matter, and that claim needs its own assertion. The list was
tested exhaustively for orderings and the one thing the user actually looks at
was not tested at all.

### 2026-09-13 · RES-101 (an API shape I asserted without opening the file)
**Suggested:** Comparing designs for discarding stale search responses, I
recommended matching on the query the response carries — "เทียบ `query` ที่
response ถือกลับมากับคำล่าสุด ซึ่งอ่านง่ายกว่าเลขรุ่นและตรงกับความหมายจริง" —
and argued it was more readable than the generation counter used for RES-104
because it compares the thing that actually matters rather than a number.

**Why it was wrong:** `searchDeals` returns `List<Map<String, dynamic>>` and
nothing else (`fake_api_service.dart:95`); `DealRepo.search` maps it straight to
`List<DealModel>`. There is no query in the response to compare against. The
neighbouring `getDeals` *does* echo its `page`, which is probably where the
assumption came from, and it is the difference between the two that makes the
claim feel safe. CLAUDE.md's first working principle is NO MAGIC — "never invent
APIs, fields, files, or behaviour... grep or read it first" — and this is
exactly that, in a design recommendation rather than in code.

**How it was caught:** The user asked what the API actually returns, one turn
after the suggestion. I had not opened `searchDeals` before recommending a
design built on its return shape; I had only read the latency lines above it
while working out the timing.

**Done instead:** The comparison has to be held client-side — capture the query
in a local before awaiting and compare it against the latest one on the way
back. Nothing was built on the wrong claim, so the cost was one turn. It is
logged anyway because the failure is not the design, it is that I described a
function's output while looking at a different part of the same function, and
that the wrong version was the more persuasive one.


### 2026-09-13 · RES-101 (a harness too slow to show the bug)
**Suggested:** To reproduce the search race on device I typed "sushi" with
`adb shell "input text s; input text u; ..."`. The log came back in the order
the letters were typed — `q=s` finishing first, `q=sushi` last — which is the
*correct* ordering, and the screen showed the right results. Read at face value
that is "does not reproduce".

**Why it was wrong:** Each `input text` invocation costs about 300 ms on this
device, so the five requests were issued 1.2 s apart. The whole defect lives in
a window of a few hundred milliseconds: `q=s` takes 1100-1399 ms and `q=sushi`
takes 180-479 ms, so they only invert if the keystrokes are close together. The
harness was typing more slowly than a person can, and slowly enough to hide the
thing it was built to show.

**How it was caught:** Comparing the measured completion times against the
latency formula before writing anything down. The gap between the first and last
request was larger than the difference in their service times, which cannot
produce an inversion — so the result was a property of my typing, not of the
app.

**Done instead:** `adb shell input keyevent 47 49 47 36 37` — all five key
events in one process. The very next run inverted: `sush`, `sushi`, `sus`, `su`,
`s` at 320, 442, 555, 1001 and 1238 ms, with the box reading "sushi" and the
screen showing a match for "s". Written into `solutions.md` as part of the repro
steps, because the slow version produces a confident false negative and the
difference between the two is one flag.

### 2026-09-13 · RES-101 (reaching for the tool that worked last time)
**Suggested:** Having just finished RES-104 with a generation counter, I offered
it as the fix here too, then switched to comparing the query text on the grounds
that it reads better — arriving at both by analogy rather than by testing.

**Why it was insufficient:** The query-text version is wrong in a way that reads
as right. Type "sushi", backspace to "sush", type "i": two in-flight requests
now carry the same text, the guard lets both through, and the older one can land
last. Their payloads are not interchangeable, because `checkout` mutates
`quantityLeft` on the shared deal maps (`fake_api_service.dart:196`). The
counter would have handled it, but it has to be incremented and remembered in
the cleared-box branch, and it names nothing.

**How it was caught:** The user asked whether the query version could miss the
latest result by a fraction of a second. That is exactly the A-B-A case, and it
had not occurred to me while arguing that the text comparison was the more
readable option.

**Done instead:** The `Future` itself as the token, compared with `identical()`
— unique per request like a counter, and meaningful like the text. The
disagreement was then made falsifiable rather than argued: the query-text
variant was built, compiles, passes four of five cases and fails the A-B-A one
with `Expected: <3> Actual: <1>`. That case exists in the suite specifically to
keep the design decision testable. Both rejected options are in `solutions.md`
with that reasoning.
### 2026-09-13 · F-1 (a Worker that will not let go when asked)
**Suggested:** `ExpiryBuilder` subscribes to the clock and must stop once the
deal has expired, so the callback disposed its own `Worker` and then called
`setState`. That reads as obviously correct — finish, tidy up, notify — and the
widget's behaviour looked right on the first two ticks.

**Why it was wrong:** A `Worker` cannot be disposed from inside its own
callback, not immediately. `Worker.dispose` calls the subscription's `cancel`,
which calls `GetStream.removeSubscription`, which checks `_isBusy` and — when
the stream is mid-notification, which is precisely when a worker callback runs —
defers the removal behind `await Future.delayed(Duration.zero)`
(`get_stream.dart:21-27`). The listener survives at least one more tick. It also
leaves that zero-duration future outstanding, which `flutter_test` reports as a
pending timer, so the test fails for a second, unrelated-looking reason.

**How it was caught:** A test asserting the build count, which expected 2 and
got 3. Printing the clock at each build put the extra one six seconds past
expiry, which no amount of reading the widget would have suggested. The
`flutter_test` stack trace then named the line: `GetStream.removeSubscription`
creating a `FakeTimer` from inside my own callback.

**Done instead:** The callback does not dispose itself. Correctness rests on a
`_expired` flag checked first, so it no longer matters when the removal lands;
`dispose()` does the cleanup, where the stream is idle and removal is immediate.
The general point is one this log keeps circling: "dispose it when you are done
with it" is a statement about a library's timing, not a self-evident truth, and
the only way I found out was by counting something.

### 2026-09-13 · F-1 (the same clock lesson, twice)
**Suggested:** The countdown and the expiry check both read `DateTime.now()`.
The widget tests pumped a second at a time and asserted the text changed.

**Why it was wrong:** `flutter_test` fakes timers but not the wall clock. Pumping
fires the periodic ticker and then the callback assigns the *real* `DateTime.now()`,
which has barely moved, so the countdown stayed on `00:03` and nothing ever
expired. I had written this exact fact into `pickup_countdown_test.dart` during
RES-102 — "`tester.pump` advances FakeAsync's clock… but the widget derives
`remaining` from `DateTime.now()`, which flutter_test does not fake" — and then
built a new feature on top of the same assumption.

**How it was caught:** Four of the first six tests failed at once, all on
unchanged text.

**Done instead:** Both widgets read the time from `ClockService` rather than
calling `DateTime.now()`, and the tests drive the published value with a ticker
interval long enough that it never overwrites them. That is better in
production too, and the reason is not the test: the countdown on screen and the
decision that it has expired now come from the same instant, so a card cannot
read `00:01` while its own expiry has already fired.

Writing a lesson down is not the same as having somewhere it gets applied. The
note that would have caught this was one file away, in a test I wrote myself.
