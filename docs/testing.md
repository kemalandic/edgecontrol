# Testing

EdgeControl reads the machine it runs on — memory counters, sensors, the
trackpad, the media player. Most of that cannot be called from a test, so the
project is arranged to keep the part that *can* be tested apart from the part
that cannot.

## Running the suite

```bash
./Scripts/ci-local.sh          # generate, build, test, coverage — what CI runs
./Scripts/ci-local.sh test     # tests only
SKIP_CLEAN=1 ./Scripts/ci-local.sh   # incremental, while iterating
```

CI runs this same script, so a green run here means a green run on the pull
request. The build is clean and unsigned by default: a hosted runner has no
signing identity for this team and this machine does, so forcing the same
configuration locally stops "builds on my Mac" from hiding a CI failure.

## Pure core, thin shell

Any code that reads the system separates in two:

- a **core** — a struct or function taking plain values in and returning plain
  values out, with no imports beyond Foundation. Fully tested.
- a **shell** — the method that performs the syscall, reads the sensor or drives
  the Apple event, then hands its raw result to the core. Not tested.

`SystemMetricsService` is the worked example. The arithmetic that turns
`vm_statistics64` into a used figure lives in a struct a test can construct; the
`host_statistics64` call stays in the service. Before that split the memory gauge
counted the file cache as used and read 116 GB where Activity Monitor read 83,
and no test could have caught it.

When you add a service, ask where its core is. If the answer is "there isn't
one", that is the thing to fix first.

## Where a test goes

```
Tests/EdgeControlTests/
├── Support/     shared fakes and builders — no tests live here
├── Fixtures/    recorded inputs, copied into the test bundle
├── Models/      pure types: grid geometry, theme, layout, manifests
├── Services/    service cores and their seams
└── CI/          the CI/CD provider suite
```

One file per production type, named `<Type>Tests.swift`. Name the test after the
behaviour, not the method: `usedMemoryExcludesFileCache`, not
`testCurrentMemorySnapshot`.

## Swift Testing

New tests use Swift Testing — `import Testing`, `@Suite`, `@Test`, `#expect`.
The existing XCTest cases are not being migrated; both frameworks run in the same
bundle.

`@Test(arguments:)` is worth reaching for whenever a test would otherwise be
copy-pasted per case, and `#expect` reports the actual operand values on failure
where `XCTAssertEqual` reports two opaque descriptions.

One build setting makes this work: `ENABLE_TESTING_SEARCH_PATHS: YES` on the test
target. Without it `@Test` functions compile cleanly and then never run — the
suite reports success having skipped them. If you add a test target, set it.

## Fixtures are recorded, never invented

Test inputs come from real output captured once and committed: recorded API
responses, `vm_stat` page counts from a real machine, sensor dumps. Invented
inputs test the author's mental model of the system, which is the thing most
likely to be wrong. Note in a comment where and when a fixture was captured.

Resources are copied flat into the test bundle and loaded by bare filename, so
**fixture names must be unique across every subdirectory**. Prefix by area:
`github-runs.json`, `weather-current.json`.

## Untrusted input

The plugin manifest is the only place where data someone else authored crosses
into typed Swift. It is tested adversarially — missing fields, wrong types,
truncated files, absurd lengths, unexpected Unicode — because the question there
is not whether it works but whether it fails safely.

That habit found a real defect one layer down, in the path check that keeps a
plugin inside its own bundle. Carry it wherever third-party input lands.

## Warnings

The build reports its compiler-warning count against a budget and fails if the
count rises. The budget is not zero yet; it is a ratchet, so new work does not
add to the pile while the existing warnings are worked off.

A warning count from an incremental build is meaningless — it re-emits nothing
for files it did not recompile. That is why the script cleans by default.

## What is deliberately not tested

- **SwiftUI views.** The dashboard is tuned by eye against a specific panel;
  snapshot baselines would churn on every visual adjustment and fail for reasons
  that are not defects. Tests cover the data a widget renders, not the rendering.
- **UI automation.** The app is a kiosk on a secondary display.
- **A coverage percentage.** Coverage is measured and reported so a regression in
  it is visible. It does not gate a merge, because a number invites tests written
  to move the number.
