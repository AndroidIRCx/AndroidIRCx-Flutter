# AndroidIRCx Flutter

Flutter rewrite of AndroidIRCx, focused on preserving behavior, features, and UX parity with the
existing React Native application.

[![Build](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/AndroidIRCx/AndroidIRCx-Flutter)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/releases)
[![Downloads](https://img.shields.io/github/downloads/AndroidIRCx/AndroidIRCx-Flutter/total)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/releases)
[![GitHub License](https://img.shields.io/github/license/AndroidIRCx/AndroidIRCx-Flutter)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/blob/main/LICENSE)

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/11929/badge)](https://www.bestpractices.dev/projects/11929)
[![CodeQL](https://img.shields.io/github/actions/workflow/status/AndroidIRCx/AndroidIRCx-Flutter/codeql.yml?label=CodeQL&branch=main)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/security/code-scanning)
[![Dependabot](https://img.shields.io/badge/dependabot-enabled-brightgreen)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/security/dependabot)
[![Coverage](https://codecov.io/gh/AndroidIRCx/AndroidIRCx-Flutter/branch/main/graph/badge.svg)](https://app.codecov.io/gh/AndroidIRCx/AndroidIRCx-Flutter/)

[![GitHub Stars](https://img.shields.io/github/stars/AndroidIRCx/AndroidIRCx-Flutter?style=flat)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/stargazers)
[![Contributors](https://img.shields.io/github/contributors/AndroidIRCx/AndroidIRCx-Flutter)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/graphs/contributors)
[![GitHub Issues](https://img.shields.io/github/issues/AndroidIRCx/AndroidIRCx-Flutter)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/issues)
[![Last Commit](https://img.shields.io/github/last-commit/AndroidIRCx/AndroidIRCx-Flutter/main)](https://github.com/AndroidIRCx/AndroidIRCx-Flutter/commits/main)

[![Google Play](https://img.shields.io/badge/Google%20Play-Download-green)](https://play.google.com/store/apps/details?id=com.androidircx)

## Current Status

This repository is an active rewrite in progress.

Implemented in the current Flutter app:

- network list and add/edit flow
- basic IRC socket connection lifecycle
- server, channel, and query tabs
- basic message sending and receiving
- local persistence for networks, tabs, message history, and a small settings set
- reconnect banner and basic connection status UX

Not implemented yet in full parity:

- CAP/SASL full flow
- multi-network orchestration parity
- advanced numerics and command coverage
- notifications/background behavior
- encryption
- DCC/media
- monetization and security platform features

The feature list below describes the target AndroidIRCx parity scope, not the current Flutter
implementation status.

## 🔐 Security

- **TLS/SSL** -- full encrypted connection support
- **SASL** -- PLAIN, SCRAM-SHA-256, EXTERNAL (client certificates)
- **E2E Encryption** -- libsodium XChaCha20-Poly1305 with context-bound AAD
- **Secure Storage** -- device Keychain for secrets (AsyncStorage fallback with warning)
- **App Lock** -- PIN and biometric with auto-lock on background/launch
- **Kill Switch** -- emergency disconnect and optional data wipe
- **Play Integrity** -- Google Play Integrity verification


## 🤝 Contributing

AndroidIRCX is open source and contributions are welcome.

**Areas where you can help:**

- IRC protocol -- new IRCv3 capabilities, IRCd-specific features
- Testing -- more edge cases, integration tests
- Translations -- add or improve translations via Transifex
- UI/UX -- accessibility, new themes, layout improvements
- Documentation -- guides, tutorials, examples
- Security -- audit, improvements, new encryption features

- **Before submitting a PR:**

```bash
flutter analyze
flutter test      # Must pass all
```

## 📝 IRC Protocol Compliance

| Standard | Coverage                                       |
|----------|------------------------------------------------|
| RFC 1459 | Full compliance                                |
| RFC 2812 | Extended numeric support (390+ handlers)       |
| IRCv3    | 27 capabilities requested, full implementation |
| SASL     | PLAIN + SCRAM-SHA-256 (RFC 7677) + EXTERNAL    |
| DCC      | SEND, CHAT                                     |
| CTCP     | Full (VERSION, TIME, PING, ACTION, etc.)       |

---

## 🎨 Credits & Inspiration

**IRCap** (c) Carlos Esteve Cremades, 1997-2026 - the legendary mIRC script that inspired
AndroidIRCX's away system, protection features, writing styles, and the IRcap theme. If you used
mIRC in the 2000s, you probably know IRCap. Its futuristic design and complete feature set set the
bar for what an IRC experience should be.

**IRcap theme for AndroidIRCX** by ARGENTIN07, based on the original IRCap theme.

**Translations:** ARGENTIN07 and Cubanita83 (Spanish), Yusbastian Lemon (Indonesian). See the full
credits in the app's Credits screen.

As an open-source creator, I deeply respect the work of **Linus Torvalds** and **Richard Stallman**
for the free/open-source software movement. Their vision and persistence were a direct inspiration
for building this app as open source.

[![Linux](https://img.shields.io/badge/Linux-Tux-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![GNU](https://img.shields.io/badge/GNU-Project-A42E2B?logo=gnu&logoColor=white)](https://www.gnu.org/)

---

## 📄 License

**GNU General Public License v3.0 or later (GPL-3.0-or-later)**

Copyright (C) 2025-2026 Velimir Majstorov

This program is free software: you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See
the [GNU General Public License](LICENSE.md) for more details.

You should have received a copy of the GNU General Public License along with this program. If not,
see <https://www.gnu.org/licenses/>.

---

## 🤖 AI Usage Disclaimer

This project was built with modern tools, including AI-assisted development.

Like robotics in manufacturing, autopilot systems in agriculture, and autocomplete in software,
AI is a tool -- no more, no less.

**AI did not build this project on its own.**
Every decision, architectural choice, security consideration, and final line of code was reviewed,
validated, and maintained by a human engineer with more than 25 years of professional experience.

AI did not replace engineering judgment; it accelerated routine work so more time could be spent on
architecture, quality, and usability.

If you prefer software created without automation or AI assistance, that choice is fully respected.
At the same time, refusing tools has never stopped progress -- it has only determined who
participates in shaping it.

This project exists to contribute something real to open source, with practical value and
long-term maintenance. You are welcome to:

- use it or study it
- fork it or improve it
- or simply ignore it

All are valid choices.

Builders shape the future in silence. Spectators explain it when the work is already done.

In the end, technology moves forward with or without permission. The only question is who chose to
be part of it.

Some build loudly. Others build correctly.

Those who recognize the work will understand. Time will explain the rest.

🜂🜃🜂

---

<p align="center">
  <a href="https://AndroidIRCx.com">
    <img src="https://AndroidIRCx.com/android-icon-192x192.webp" width="64" height="64" alt="AndroidIRCx">
  </a>
</p>

<p align="center">
  <b><a href="https://androidircx.com">AndroidIRCx.com</a></b>
</p>

---
