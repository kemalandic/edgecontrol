# CI/CD widget setup

The CI/CD widget shows workflow runs from every Git host you configure —
GitHub and Forgejo/Gitea today — in one list, with in-progress runs first.

## Adding an account

**Settings → CI/CD → Add account…**

1. Pick the host type: **GitHub** or **Forgejo / Gitea**.
2. Enter the server URL — the address you use in the browser, not an API path:
   - GitHub: `https://github.com` (or your GitHub Enterprise address)
   - Forgejo/Gitea: e.g. `https://git.example.dev`
3. Paste an access token.
4. Press **Validate**. EdgeControl confirms the token against the host and shows
   the account it belongs to. Nothing is stored until validation succeeds, so a
   dead token never reaches your Keychain.
5. Press **Save**.

Repeat for each host. The widget merges runs from all of them.

## Token scopes

The widget only reads. No write scope is needed for anything it does.

### GitHub

A classic personal access token with:

| Scope | Why |
| --- | --- |
| `repo` | Read private repositories and their workflow runs |
| `read:org` | List the organisations whose repositories should be discovered |

`repo` on its own also satisfies the organisation listing. If every repository
you care about is public, you can drop `repo` — but then only public
repositories appear.

These were measured against the four endpoints the app actually calls
(`/user`, `/user/repos`, `/user/orgs`, `/repos/{owner}/{repo}/actions/runs`);
only `/user/orgs` demands a scope beyond basic authentication.

### Forgejo / Gitea

**Settings → Applications → Generate Token**, with read access to your
repositories.

The app calls exactly three endpoints:

```
GET /api/v1/user
GET /api/v1/user/repos?order_by=recentupdate
GET /api/v1/repos/{owner}/{repo}/actions/runs
```

All three were verified working. The minimum scope set was not bisected — start
with read-only repository access and widen only if validation fails.

## Importing from `gh` or `tea`

If you already use the GitHub or Gitea CLI, EdgeControl can pick up those
logins: **Settings → CI/CD → Import from CLI**. On first launch after updating,
it also offers this once, before you have configured anything.

It reads:

- `gh auth token` for github.com
- `tea login list --output json` plus `tea login helper get` for each Forgejo or
  Gitea host

Neither CLI's configuration file is parsed — both interfaces are documented
commands. The button is hidden when neither CLI is installed.

Importing **copies** the token into your Keychain; it is not read live. If you
rotate a token with the CLI afterwards, EdgeControl notices the resulting 401
and re-imports once automatically before reporting the account as failed.

## Which repositories appear

A repository shows up when it has at least one workflow run **and** activity
within the discovery window (14 days by default, configurable in
**Settings → CI/CD → Discovery**).

Two overrides sit under the same section, both taking `owner/name`:

- **Pinned** — always shown, whatever the activity window says. Use this for a
  repository you watch but rarely push to.
- **Hidden** — never shown, and never polled.

Discovery refreshes hourly and is cached between refreshes. Changing the window
or either list clears that cache, so the change takes effect on the next poll
rather than up to an hour later.

Repositories where the host has Actions disabled answer `404` on the runs
endpoint. Those are skipped individually — one such repository does not affect
the rest of the account.

## How often it refreshes

**Settings → CI/CD → Refresh** sets the poll interval: 15, 30 (default), 60 or
120 seconds. Every setting on this tab is remembered across launches.

An account that starts failing backs off on its own — 30s, 1m, 2m, 5m, then
15m — and returns to your interval on its first success. Accounts back off
independently, so one unreachable host does not slow the others down.

Requests are conditional: EdgeControl remembers the `ETag` each host returns and
sends it back, so a repository with nothing new answers `304 Not Modified` with
no body. On GitHub a `304` does not count against your quota, which is what
keeps a 15-second interval across several accounts affordable. Hosts that send
no `ETag` — Forgejo currently does not on this endpoint — simply get ordinary
requests.

## Reading the widget

Each row is one run: a status dot, the repository name, the commit title, and
the outcome — `PASS`, `FAIL`, `RUNNING`, `QUEUED`, `CANCEL`, `SKIP`, or `—` for
a state the host reports that has no equivalent here. Runs still
in progress sort to the top, then newest first. Tapping a row opens that run on
its host.

The host name appears next to the repository only once you have more than one
account configured, since it is noise until then. The desktop widget follows the
same rule and omits it on the small size, where there is no room.

A `⚠ 2` in the header means two accounts are failing while others still work —
the runs you can see are real, the rest are missing. Tapping it opens Settings.

## Where the token is stored

macOS Keychain, service `ai.pakslab.edgecontrol.cicd`, one entry per account.
The account list itself (host, username, API URL) lives in UserDefaults and
never contains the token.

Building EdgeControl yourself with a different Apple Developer Team ID changes
the code signature, so macOS will ask for permission the first time the new
build reads those Keychain entries. That is expected.

## Troubleshooting

Each state the widget can show, and what it means:

| Widget shows | Meaning | What to do |
| --- | --- | --- |
| `NO ACCOUNTS` | Nothing configured | Settings → CI/CD → Add account |
| `… AUTHENTICATION FAILED` | Token expired, revoked, or lacking scope | Regenerate the token and re-add the account |
| `… RATE LIMITED` | The host's quota is exhausted | Increase the refresh interval; the app retries on its own |
| `… UNREACHABLE` | Network, DNS, or TLS failure | Check the server URL and your connection |
| `… SERVER ERROR 5xx` | The host returned an error | Usually transient; the app backs off and retries |
| `NO RECENT RUNS` | Accounts are healthy, nothing has run | Not an error |
| `⚠ 1` in the header | One account is failing while others work | Open Settings → CI/CD to see which |
| `Open EdgeControl to refresh` (desktop widget) | The snapshot was written by an older version | Launch the app once |

A failing account backs off on its own — 30s, 1m, 2m, 5m, then 15m — and
returns to the normal interval on its first success. Accounts back off
independently, so one unreachable host does not slow the others down.

Per-account status is listed in **Settings → CI/CD → Accounts**: the last
successful sync, the current error if any, and the remaining API quota for
hosts that publish one. GitHub reports `4831/5000 · resets in 42m`; Forgejo
publishes no quota headers, so no figure is shown there — an absent quota is
not an exhausted one.

The figure turns amber below 15% remaining, before requests start failing.
