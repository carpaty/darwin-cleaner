# Darwin Cleaner

Darwin Cleaner is a small, transparent macOS cleaner built with SwiftUI. It scans a fixed allowlist of user-owned locations, shows every candidate before cleanup, skips symbolic links, and moves recoverable items to the macOS Trash.

## What it scans

- `~/Library/Caches` (items older than 7 days)
- `~/Library/Logs` (items older than 14 days)
- `~/.Trash` (items older than 30 days)
- Xcode `DerivedData` (older than 7 days)
- Xcode DeviceSupport, Archives, DocumentationCache, Products, downloaded packages, and CoreSimulator caches
- old `.dmg`, `.pkg`, `.zip`, and `.xip` files in Downloads, plus old `Install macOS*.app` applications
- local iPhone and iPad backups
- old Gradle caches and wrapper distributions
- possible third-party leftovers in Preferences, Saved Application State, HTTPStorages, WebKit, Application Support, and Cookies
- Homebrew, SwiftPM, CocoaPods, npm, Yarn, and Docker through fixed, tool-owned cleanup commands

It never cleans `/System`, never guesses whether personal documents are "junk", never requests administrator privileges, never deletes Time Machine snapshots or Docker volumes, and never silently deletes files. It reads installed application metadata under `/System/Applications` only to reduce false-positive app-leftover suggestions.

Each item has one of three safety levels:

- **Recommended** items are old, regenerable user cache or log data and are selected after a scan.
- **Review** items include installers, backups, archives, Gradle data, and possible app leftovers. They are never preselected and are moved to Trash.
- **Not recoverable** items include old Trash contents and tool-managed cleanup commands. They are never preselected and receive a stronger confirmation warning.

The sidebar includes three-state selection controls for Smart Scan and every category. The checkbox selects or deselects the whole category, while clicking the category name only filters the results; this prevents browsing a risky category from implicitly selecting it.

Results can be searched by name and sorted by name or size. Cleanup errors are summarized in a compact alert; the complete report is available through Copy Details.

Package manager paths are excluded from the general cache category to prevent duplicate cleanup. Commands are launched without a shell, from a fixed executable allowlist, with fixed arguments. Docker uses `docker system prune --force` without `--volumes`.

Apple-owned `com.apple.*`, `CloudKit`, and `familycircled` caches are left to macOS because privacy protections can deny moving them even when they appear under the user's cache directory. Recommended items also have to pass a deletability preflight before they are shown.

## Requirements and local development

- macOS 14 or newer
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```sh
brew install xcodegen
xcodegen generate
open DarwinCleaner.xcodeproj
```

Run tests from Xcode or with:

```sh
xcodebuild test -project DarwinCleaner.xcodeproj -scheme DarwinCleaner -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Some protected folders can require Full Disk Access in **System Settings → Privacy & Security**. The app works without it and reports inaccessible locations. App-leftover detection is intentionally conservative but cannot prove that data is unused—for example, an app may live on an external disk—so every candidate requires human review.

`~/Library/Containers` and Group Containers are intentionally not cleanup targets. macOS privacy protections restrict them, and extensions may remain valid even when their bundle identifiers do not match the host app exactly.

## CI and releases

`.github/workflows/ci.yml` builds and tests every pull request and push to `main`.

To publish a release, open **Actions → Release → Run workflow**, enter a version such as `v1.1.0`, and run it. The workflow validates the version, runs tests, builds the app, creates a compressed DMG and SHA-256 file, creates the annotated tag, and attaches both files to a GitHub Release.

The default public workflow produces an unsigned DMG. This is suitable for development, but public distribution should add Developer ID signing and Apple notarization; otherwise Gatekeeper warns users. See `docs/DISTRIBUTION.md`.

## Architecture and safety

`CleanerEngine` owns scanning and cleanup on an actor, `CleanerViewModel` exposes UI state on the main actor, and SwiftUI renders the main window, settings, and optional menu-bar item. Cleanup paths and action types are checked against the same allowlist both during scanning and immediately before deletion. A directory is eligible by age only when its newest nested file is old enough, preventing a stale directory timestamp from hiding recently used content.

Contributions should add tests for every new scan location and must never broaden cleanup to arbitrary paths without an explicit review UI and a path containment test.

## Cleanup providers

The app uses these fixed commands when the corresponding tool is installed:

```text
brew cleanup --prune=30
swift package purge-cache
pod cache clean --all
npm cache clean --force
yarn cache clean
docker system prune --force
xcrun simctl delete unavailable
```

Gradle already manages cache retention itself, so Darwin Cleaner only presents old Gradle cache directories for explicit, recoverable removal. Unavailable simulator devices are removed through `simctl`; installed simulator runtimes are not removed from their private storage, so use Xcode Settings → Components for those.
