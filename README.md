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
- **Night mode** for 3 a.m. feeds: a dim, warm, true-black theme (no white), on all the time or on a schedule (7 PM to 7 AM by default), with an optional lower screen brightness
- **Sleep and feed predictions**: an "Up next" card with the next nap window, bedtime, and feed, worked out on your phone from your baby's age and logs (no account, no cloud), with a note saying what each estimate is based on
- **Easy on the battery**: anything that costs battery, like keeping the screen on during the nursing timer, is opt-in and says so
- **Widgets and Live Activities**: Home Screen and Lock Screen widgets with one-tap buttons (start nursing on the next side, sleep or wake up, log a diaper), plus Lock Screen and Dynamic Island timers for running sleep and nursing
- **Reminders** on each phone: "feed every 3 hours" (counted from the start or end of the last feed, with optional quiet hours) that moves whenever a feed is logged, an opt-in nap window reminder ("Juniper's nap window opens in 10 min", 5 to 20 minutes ahead, from the on-device sleep estimate; bedtime optional), plus daily reminders for things like vitamin D drops. Feed reminders have Start Left, Start Right, and Snooze buttons, and feed and medicine reminders are Time Sensitive so they get through Focus
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

Pick an iPhone simulator and run. iCloud is off by default, so the app runs in the simulator with no paid Apple Developer account; data is stored locally. The widgets use an App Group (`group.<BUNDLE_ID_PREFIX>.littlebabylog`), which also works in the simulator without a team. To try them, touch and hold the Home Screen, tap Edit, then Add Widget, and pick Little Baby Log.

The `.xcodeproj` is generated from `project.yml` and is not checked in. Re-run `xcodegen generate` after pulling changes.

## Enabling iCloud sync and sharing

CloudKit sync and caregiver sharing need a paid Apple Developer Program account and a real device (or a simulator signed in to iCloud).

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (it is git-ignored).
2. Set `DEVELOPMENT_TEAM` to your team ID and `BUNDLE_ID_PREFIX` to a reverse-DNS prefix you own, such as `com.yourname`.
3. Run `xcodegen generate` again.
4. Open the project. If Xcode complains under Signing & Capabilities, add or refresh the iCloud capability so the container (`iCloud.<prefix>.littlebabylog`) is registered for your team.
5. Register the App Group `group.<prefix>.littlebabylog` for your team as well, for both the app and the widget extension (`<prefix>.littlebabylog.widgets`). Xcode does this under Signing & Capabilities > App Groups, or add it at developer.apple.com > Identifiers > App Groups. Without it the widgets can't read the app's data, and the app itself needs it because the Core Data store lives in this group container.
6. Run on a device signed in to iCloud.

Before releasing to the App Store, deploy the CloudKit schema to **Production** in the [CloudKit Console](https://icloud.developer.apple.com/). Until you do, sync works only in the development environment.

## Running tests

The model, persistence, and logic live in a Swift package that also builds on macOS, so tests run without Xcode or a simulator:

```sh
cd Packages/BabyLogKit && ./test.sh
```

`test.sh` runs plain `swift test` when Xcode is installed, and adds the search paths Swift Testing needs when only the Command Line Tools are present.

## Project structure

- `App/`: the iOS app (SwiftUI)
- `Widgets/`: the widget extension (Home Screen / Lock Screen widgets, Live Activities)
- `Shared/`: code compiled into both the app and the widget extension
- `Packages/BabyLogKit/`: Core Data model, persistence, CloudKit sharing, and logic
- `Config/`: xcconfig files, entitlements, and Info.plist
- `scripts/`: helper scripts, such as the app icon generator
- `project.yml`: the XcodeGen project spec

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full layout, data model, and design notes.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. Contributors sign a short [Contributor License Agreement](CLA.md) once, through a bot comment on their first pull request.

## Roadmap

Ideas for after v1:

- Apple Watch app
- Siri and App Intents
- Localization
- A photo for each baby
- iPad layout polish

## Support the project

Little Baby Log will always be free, with no ads or paid tier. Keeping it on the App Store still costs money (the Apple Developer Program fee, test devices, time). If it's made your nights a little easier, you can help cover that:

<a href="https://www.buymeacoffee.com/mogarber" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="60" width="217"></a>

## License

Little Baby Log is licensed under the [GNU General Public License v3.0](LICENSE), with an [additional permission](APP_STORE_EXCEPTION.md) that allows distribution through app stores such as the Apple App Store.

In short, you are free to use, study, modify, and share it. If you distribute a modified version, including through an app store, you must publish your source under the same terms. The app store permission exists because the App Store's terms conflict with the plain GPL; it lets the app, and forks of it, ship there as long as the source stays public.

## Disclaimer

Little Baby Log is not a medical device and does not provide medical advice. It is a personal logbook only. Do not rely on it for dosing decisions or to diagnose or monitor any condition. Talk to your pediatrician about your baby's health.
