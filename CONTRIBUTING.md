# Contributing to EdgeControl

Thanks for your interest in contributing! Here's how you can help.

## Getting Started

1. Fork the repo
2. Clone your fork
3. Run `xcodegen generate` (requires `brew install xcodegen`)
4. Open `EdgeControl.xcodeproj` in Xcode
5. Build and run with Cmd+R

## Making Changes

- Create a feature branch from `main`
- Keep changes focused — one feature or fix per PR
- Run the test suite before opening a PR (see below)
- Test on the XENEON EDGE if you have one, otherwise test on any display
- Follow the existing code style (Swift 6, SwiftUI, no third-party dependencies)

## Running the tests

```bash
xcodegen generate   # after adding or removing any file
xcodebuild test -project EdgeControl.xcodeproj -scheme EdgeControl \
  -destination 'platform=macOS'
```

Tests must not touch the network or the real Keychain. Inject `CITransport`
and `CISecretStore` instead — `StubTransport` and `InMemorySecretStore` exist
for exactly this. Recorded API responses live in
`Tests/EdgeControlTests/CI/Fixtures/`.

Passing tests are necessary but not sufficient: run the app and use what you
changed. Every defect found in the multi-provider CI/CD work after the suite
was green came from actually running it.

## Pull Requests

1. Push your branch to your fork
2. Open a PR against `main`
3. Describe what you changed and why
4. Include a screenshot if it's a UI change

## Reporting Issues

- Use GitHub Issues
- Include your macOS version
- Describe what you expected vs what happened
- Screenshots help a lot

## Code Style

- Swift 6 strict concurrency
- SwiftUI for all UI
- No third-party dependencies — keep it native
- Follow existing patterns in the codebase

## How the code is laid out

One type per file, named after it. Files that belong together live in a folder
named after what they make — `Widgets/Info/StickyNote/` holds the widget, its
view, the AppKit bridge, the editor and the checkbox it draws.

There is no line limit, but there is a signal. Once a file passes roughly four
hundred lines it is usually holding more than one idea, and it is worth asking
which type wants out. The average file here is under two hundred.

When a file does grow, prefer moving *logic* out over slicing a type into
extensions. Pulling a pure piece into its own type — the line parsing in
`StickyNoteMarkup`, the geometry in `StickyNoteLayout` — shrinks the file and
makes the piece testable at the same time. Splitting a cohesive class across
files only moves braces, and in Swift it costs real encapsulation, because
`private` members stop being private to their own type the moment the type
spans more than one file.

Anything that reads the system splits in two regardless of size: a testable
core taking plain values, and a thin shell that performs the syscall. That one
is not a preference; see `docs/testing.md`.

## Ideas & Feature Requests

Use [Discussions](https://github.com/kemalandic/edgecontrol/discussions) for feature ideas and general questions.

## Adding a CI provider

The CI/CD widget talks to any host through `CIProvider`
(`Sources/EdgeControl/Services/CI/CIProvider.swift`). Adding GitLab, Bitbucket,
or anything else means implementing one protocol — nothing else changes.

1. Add a case to `CIProviderKind` in `CIAccount.swift`, and teach
   `CIAccount.apiBaseURL(forKind:webURL:)` how to derive the API base from a
   web URL.
2. Create `Sources/EdgeControl/Services/CI/YourProvider.swift` implementing
   `validate()`, `discoverRepositories(activeSince:)` and
   `fetchRuns(repository:limit:)`. Take a `CITransport` in the initialiser —
   never call `URLSession` directly, or your provider cannot be tested.
3. Map the host's run states onto `CIRunState`. If a state has no obvious
   equivalent, map it to `.unknown` rather than guessing.
4. Add a fixture under `Tests/EdgeControlTests/CI/Fixtures/` with one real
   (redacted) response plus an entry per state your mapper handles.
5. Add a test class modelled on `ForgejoProviderTests`: every state, the field
   mapping, and one error response.
6. Add the case to `CICDService.makeProvider(_:token:)`.

Run `xcodegen generate` after adding files, then:

```bash
xcodebuild test -project EdgeControl.xcodeproj -scheme EdgeControl \
  -destination 'platform=macOS'
```
