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
- Test on the XENEON EDGE if you have one, otherwise test on any display
- Follow the existing code style (Swift 6, SwiftUI, no third-party dependencies)

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

## Ideas & Feature Requests

Use [Discussions](https://github.com/kemalandic/edgecontrol/discussions) for feature ideas and general questions.
