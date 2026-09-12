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

**Tool in use:** Claude Code (Opus 5) in the terminal, with access to the repo
and to the live app on the test device.

---

## Time log

Start and stop times as they happen, so the total in `solutions.md` is real
rather than remembered.

| Date | Start | Stop | On |
|---|---|---|---|
| 2026-09-12 | 16:10 | 16:30 | Orientation, environment verification, baselines, scaffolding |
| 2026-09-12 | 16:30 | 17:10 | Own repo + remote hygiene; read every controller; RES-107 repro |

---

## Entries

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
