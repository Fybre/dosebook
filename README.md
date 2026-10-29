# Dosebook

[![CI](https://github.com/Fybre/dosebook/actions/workflows/ci.yml/badge.svg)](https://github.com/Fybre/dosebook/actions/workflows/ci.yml)

Website: **[dosebook.app](https://dosebook.app)**

A private tracker for protocols, vials and doses, for iPhone, iPad and Mac. Dosebook is a native
Swift port of [Bench](https://github.com/ArunNGun/Bench) by Arun, with the same library, arithmetic
and backup format, so a backup moves between the two.

It holds what you are running (protocols), what you have (vials, water and what is left) and
what you did (doses), with a calculator for reconstitution, estimated levels from published
half-lives, missed-dose handling, reminders you can log from, bloodwork, weight and how you feel.

**There is no account, no server and no analytics.** Records live on your device and, when you are
signed in to iCloud, in your own private iCloud database. Apple Health is read-only. Nothing is
sent anywhere else.

> Dosebook is not medical advice and cannot check what is in your vial. The figures are estimates
> from a simple model and published half-lives, not blood tests. Talk to whoever looks after your health.

## Building

You need a recent Xcode (iOS 18 and macOS 15 SDKs or later; the author builds with Xcode 27), [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an Apple Developer
team to sign for a device.

```sh
brew install xcodegen
xcodegen generate          # makes Bench.xcodeproj from project.yml (it is not committed)
open Bench.xcodeproj
```

`project.yml` carries the author's team id and bundle ids (`me.fybre.dosebook`). To build your own copy,
change `DEVELOPMENT_TEAM`, the bundle ids and the iCloud container to ones in your account.

| Scheme | What it is |
| --- | --- |
| `Bench` | The iPhone and iPad app, with iCloud. |
| `BenchMac` | The Mac app: sandboxed, signed, same iCloud container. |
| `BenchTest`, `BenchTestMac` | Local-only test builds: no iCloud, nothing in your Apple account beyond the app id. |

The Swift sources are in `Bench/` (screens), `BenchCore/` (a Swift package: the calculations, the
library, and the SwiftData/CloudKit store), `Shared/` and `Widgets/`. Widgets and Shortcuts are written
but switched off until an App Group is registered; see `docs/PLAN.md`.

## Tests

```sh
tools/test.sh              # the BenchCore suite, in four time zones
```

The dose maths is local-time, so it is tested across zones and daylight saving.

## Documentation

`docs/PLAN.md` records the design, what is deliberately different from Bench, and how sync works.
`docs/RELEASING.md` covers building and notarising the Mac download. The website is in
[dosebook-web](https://github.com/Fybre/dosebook-web).

## Licence

MIT. See `LICENSE`. The library, translations and logic come from Bench, also MIT; its notice is in
`THIRD_PARTY_LICENSES.txt`.
