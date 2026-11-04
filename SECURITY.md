# Security Policy

## Reporting a Vulnerability

Report privately through GitHub: **Security** tab → **Report a vulnerability**.

Include your macOS version, the Tinycast version and channel, reproduction steps, and the impact.
Please don't disclose publicly until it's fixed.

We'll respond as quickly as we can and keep you posted.

## Supported Versions

Current stable and beta only. Update (`brew upgrade --cask tinycast`) before reporting.

## Scope

Of particular interest:

- **Accessibility (TCC)** — anything that widens what the paste grant enables.
- **Clipboard history** — text and images cached on disk; unintended exposure or capture.
- **Network** — Tinycast is offline by default and every networked feature is consent-gated. A path
  that reaches the network without consent, or survives consent being withdrawn, is high severity.
- **Hotkeys** — the in-house hotkey stack and the Input Monitoring grant.
- **Signing and distribution** — the DMG and Homebrew cask chain.

Out of scope: anything needing existing code execution or admin rights on the machine.
