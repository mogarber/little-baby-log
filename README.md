# Little Baby Log

A free, open-source iPhone baby tracker for sleep, feeding, diapers, and more, built for one-handed use at 3am.

<a href="https://www.buymeacoffee.com/mogarber" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="60" width="217"></a>

## Why

Baby trackers shouldn't cost a monthly subscription, and they shouldn't know everything about your family.

- **Free forever.** No paywall, no premium tier.
- **Open source.** Read it, fork it, fix it.
- **Private.** No servers, no accounts, no ads, no analytics. Your data stays on your device and in your own iCloud. Nobody else, including the developers, can see it.

## Features

- **Sleep timer** with a live clock, plus awake/asleep-for time on the dashboard
- **Nursing timer** with separate Left/Right clocks, pause and resume, and a "next side" hint
- **Bottle** feeds (formula, breast milk, or other) in ml or oz
- **Solids**
- **Diapers**: wet, dirty, both, or dry, with one-tap logging
- **Pumping** with per-side amounts
- **Growth**: weight, length, and head circumference
- **Medicine** log with name and dose
- **Today dashboard**: time since last feed, sleep, and diaper, plus a daily summary
- **History** grouped by day, with filters and edits
- **Trends** charts over 7, 14, or 30 days
- **Caregiver sharing via iCloud**: invite a partner or grandparent and timers sync live
- **CSV export** of all your data
- **Multiple babies**

## Building

Requirements: a recent Xcode (16 or newer) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open LittleBabyLog.xcodeproj
```

Pick an iPhone simulator and run. iCloud is off by default, so the app runs in the simulator with no paid Apple Developer account; data is stored locally.

The `.xcodeproj` is generated from `project.yml` and is not checked in. Re-run `xcodegen generate` after pulling changes.

## Enabling iCloud sync and sharing

CloudKit sync and caregiver sharing need a paid Apple Developer Program account and a real device (or a simulator signed in to iCloud).

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (it is git-ignored).
2. Set `DEVELOPMENT_TEAM` to your team ID and `BUNDLE_ID_PREFIX` to a reverse-DNS prefix you own, such as `com.yourname`.
3. Run `xcodegen generate` again.
4. Open the project. If Xcode complains under Signing & Capabilities, add or refresh the iCloud capability so the container (`iCloud.<prefix>.littlebabylog`) is registered for your team.
5. Run on a device signed in to iCloud.

Before releasing to the App Store, deploy the CloudKit schema to **Production** in the [CloudKit Console](https://icloud.developer.apple.com/). Until you do, sync works only in the development environment.

## Running tests

The model, persistence, and logic live in a Swift package that also builds on macOS, so tests run without Xcode or a simulator:

```sh
cd Packages/BabyLogKit && ./test.sh
```

`test.sh` runs plain `swift test` when Xcode is installed, and adds the search paths Swift Testing needs when only the Command Line Tools are present.

## Project structure

- `App/`: the iOS app (SwiftUI)
- `Packages/BabyLogKit/`: Core Data model, persistence, CloudKit sharing, and logic
- `Config/`: xcconfig files, entitlements, and Info.plist
- `scripts/`: helper scripts, such as the app icon generator
- `project.yml`: the XcodeGen project spec

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full layout, data model, and design notes.

## Contributing

Issues and pull requests are welcome. A few things to know:

- Core Data model changes must be **additive only** (new optional or defaulted attributes, never renames or removals). CloudKit schemas can't be changed destructively once deployed to production.
- Keep the privacy promise: no servers, no accounts, no ads, no analytics, no third-party SDKs that phone home.
- Add tests to `BabyLogKit` for logic changes.

## Roadmap

Ideas for after v1:

- Live Activities and Lock Screen timers
- Widgets
- Reminders ("feed due")
- Apple Watch app
- Siri and App Intents
- Localization
- Sleep-window predictions
- A photo for each baby
- iPad layout polish

## Support the project

Little Baby Log will always be free, with no ads or paid tier. Keeping it on the App Store still costs money (the Apple Developer Program fee, test devices, time). If it's made your nights a little easier, you can help cover that:

<a href="https://www.buymeacoffee.com/mogarber" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="60" width="217"></a>

## License

Little Baby Log is licensed under the [GNU General Public License v3.0](LICENSE). In short, you are free to use, study, modify, and share it, but if you distribute a modified version (including on the App Store), you must release your source under the same license.

## Disclaimer

Little Baby Log is not a medical device and does not provide medical advice. It is a personal logbook only. Do not rely on it for dosing decisions or to diagnose or monitor any condition. Talk to your pediatrician about your baby's health.
