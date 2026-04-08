# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

- Use [GitHub's private vulnerability reporting](https://github.com/kemalandic/edgecontrol/security/advisories/new)
- Or open a [GitHub Issue](https://github.com/kemalandic/edgecontrol/issues) with the label `security`

I'll acknowledge your report within 48 hours and work on a fix as soon as possible.

## Scope

EdgeControl runs locally on your Mac and does not collect or transmit any personal data. It accesses:

- System metrics (CPU, memory, disk, network) — read-only
- Safari tabs via AppleScript — for media detection and control only
- Bluetooth device list — display only
- Location — for weather data via Open-Meteo (free, no API key required)
