# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

- Use [GitHub's private vulnerability reporting](https://github.com/kemalandic/edgecontrol/security/advisories/new)
- Or open a [GitHub Issue](https://github.com/kemalandic/edgecontrol/issues) with the label `security`

I'll acknowledge your report within 48 hours and work on a fix as soon as possible.

## Scope

EdgeControl runs locally on your Mac. It sends nothing to me and has no backend
of its own. It accesses:

- System metrics (CPU, memory, disk, network) — read-only
- Safari tabs via AppleScript — for media detection and control only
- Bluetooth device list — display only
- Location — for weather data via Open-Meteo (free, no API key required)

If you configure the CI/CD widget, it additionally:

- **Talks to the Git hosts you add** — GitHub, or any Forgejo/Gitea server you
  configure. Read-only API calls; no write scope is needed or requested.
- **Stores an access token per account in your macOS Keychain**, under the
  service `ai.pakslab.edgecontrol.cicd`. Tokens are never written to disk in
  plain text and never leave your machine except to the host they belong to.
- **Can read your existing `gh` and `tea` logins**, if you ask it to. This runs
  `gh auth token` and `tea login helper get` as child processes; neither CLI's
  configuration file is read. Importing copies the token into your Keychain.

The widget is display-only: it never triggers, cancels, or modifies anything on
your CI hosts. See [CI/CD setup](docs/cicd-setup.md) for the exact endpoints and
token scopes involved.

The plugin system runs third-party HTML/JS in a `WKWebView` restricted to the
plugin's own bundle, with each native capability gated behind a permission
declared in the plugin's manifest. See
[plugin permissions](docs/plugins/permissions.md).
