# Contributing to Little Baby Log

Thanks for helping make a free baby tracker better. Issues and pull requests are welcome.

## Before your first pull request: the CLA

Every contributor signs the [Contributor License Agreement](CLA.md) once. You keep the copyright to your work; the CLA gives the project the rights it needs to keep shipping the app for free through the App Store. It also promises that your contribution will always stay available as open source.

When you open your first pull request, a bot will comment and ask you to reply with:

> I have read the CLA Document and I hereby sign the CLA

That's it. The bot records your signature, and you won't be asked again.

## Licensing

Your contribution is released under the [GNU GPL v3](LICENSE) with the project's [App Store additional permission](APP_STORE_EXCEPTION.md). Please don't submit code copied from projects whose license isn't compatible with that (if you're unsure, ask in the pull request).

## Building and testing

See [Building](README.md#building) in the README. Run the package tests before opening a pull request:

```sh
cd Packages/BabyLogKit && swift test
```

Add tests to `BabyLogKit` for logic changes.

## Ground rules

- **Core Data model changes are additive only:** new optional or defaulted attributes, never renames or removals. CloudKit schemas can't be changed destructively once they're deployed to production.
- **Privacy:** the free app has no servers, no accounts, no ads, no analytics, and no third-party SDKs that phone home. Keep it that way.
- **Battery:** no polling, background fetch, location, or per-second timers outside the visible screen. Widgets and Live Activities update only when data changes. If a feature costs battery, it must be opt-in and say so with a `BatteryImpactNote`.
- **3am-friendly:** big tap targets, few taps, and it must look right in Dark and Night mode.
- See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit together.
