# Xamarin MAUI Migration Advisor

A single PowerShell script that scans a Xamarin.Forms solution and reports what stands between it and .NET MAUI. No install, no account, no upload. It reads local files and writes one self-contained HTML report for engineering, product, and budget approvers.

## Privacy

- **No network calls, no uploads, no telemetry.** The script is a single file and writes only the HTML report.
- **The report contains file paths and short code excerpts** from your solution, so review it before sharing outside your team.

## Why now

A Xamarin app can no longer ship updates to either store:

- **App Store:** since 28 April 2026, uploads require Xcode 26 / iOS 26 SDK. Xamarin.iOS cannot produce them. ([Apple](https://developer.apple.com/news/upcoming-requirements/))
- **Google Play:** from 31 August 2026, apps must target Android 16 (API 36), with an extension to 1 November 2026. Xamarin.Android cannot reach it. ([Google](https://developer.android.com/google/play/requirements/target-sdk))

## Usage

```powershell
.\XamarinMAUIMigration.ps1                                        # scan current folder
.\XamarinMAUIMigration.ps1 -Path C:\src\MyApp                     # scan a specific path
.\XamarinMAUIMigration.ps1 -Path C:\src\MyApp -OutputPath C:\temp\report.html
.\XamarinMAUIMigration.ps1 -SkipReport                           # console summary only
.\XamarinMAUIMigration.ps1 -IncludeTestProjects                  # include test projects
```

Omit `-Path` to scan the current folder. The report is written to `.\xamarin-maui-migration-readiness.html` unless `-OutputPath` says otherwise.

| Parameter | Default | Description |
|---|---|---|
| `-Path` | `.` | Root folder to scan |
| `-OutputPath` | `.\xamarin-maui-migration-readiness.html` | HTML report path |
| `-SkipReport` | off | Console summary only |
| `-IncludeTestProjects` | off | Include projects that look like test projects |
| `-MaxFileSizeKB` | `2048` | Skip source files larger than this |

Runs on Windows, macOS, and Linux.
**Requires** Windows PowerShell 5.1 or PowerShell 7+. 
No modules or dependencies.

Skipped folders: `bin`, `obj`, `packages`, `node_modules`, `.git`, `.vs`, `TestResults`, `artifacts`.

Skipped files: `*.g.cs`, `*.designer.cs`, `*.generated.cs`.

## What it finds

| Area | Detail |
|---|---|
| Custom renderers | `ExportRenderer` registrations and renderer classes, with file and line |
| Platform effects | `PlatformEffect` implementations and `ExportEffect` registrations |
| Projects not auto-converted | UWP, iOS extensions, iOS/Android binding projects, Xamarin.Mac, tvOS, watchOS |
| NuGet dependencies | ~60 package rules: absorbed, renamed, replaced, archived, blocked |
| Removed/obsoleted APIs | `Device.*`, `Application.Properties`, `MessagingCenter`, `DependencyService` |
| .NET 11 blockers | `Microsoft.Maui.Controls.Compatibility` usage |
| XAML issues | `RelativeLayout`, `Frame`, `TableView`, retired `OnPlatform` targets |
| Syncfusion mapping | Xamarin → MAUI package mapping where Syncfusion packages are present |
| Effort estimate | Developer-days, with every rate shown so you can substitute your own |

Every finding cites the file and line it came from.

## Readiness score

A 1–100 number measuring **blocker density**, so a large app isn't penalised just for being large:

```
penalty = 10×critical + 4×high + 1×medium + 0.2×low
scale   = 40 + 8×projects + 0.4×sourceFiles
score   = 100 × e^(−penalty/scale)
```

| Score | Band |
|---|---|
| 70–100 | Straightforward |
| 45–69 | Moderate |
| 25–44 | Substantial |
| 1–24 | Major |

The constants are judgment, not measurement. The report prints the full calculation with your numbers substituted in, so you can disagree and recompute. The same applies to the effort model: every rate is listed line by line.

## Limitations

Static text analysis, not compilation. It **cannot** see:

- Runtime behaviour, reflection, or dynamically constructed types
- Source generators or code behind conditional compilation
- **Transitive** NuGet dependencies (only `packages.config` and `PackageReference` are read)
- Whether a renderer is trivial or weeks of work; it counts, it doesn't weigh

Also worth knowing:

- **The effort estimate is a planning input, not a quote.** It assumes the app currently builds and excludes new features, redesign, QA cycles, store review, and team ramp-up.
- **An `Unknown` package is not a verdict.** It means *not in the rule set*, so check it yourself.
- **Package guidance goes stale** as community ports appear and are abandoned. Entries marked **verify** in the report warrant a second pair of eyes.

Found something wrong? Open an issue. That's the fastest way to improve this for the next team.

## Contribute

Useful contributions: package, API, and XAML rule updates, plus corrections to migration guidance. Everything the tool knows lives in one marked section at the top of the script.

```powershell
@{
   Id='Some.Xamarin.Package'
   Status='Replaced'                    # Builtin | Renamed | Replaced | Blocked | Check | Ok
   Target='Some.Maui.Package'
   Note='What changes, and what to watch for.'
   Confidence='Verify'                  # omit if certain
}
```

| Status | Meaning |
|---|---|
| `Builtin` | Absorbed into .NET MAUI or .NET; remove the package |
| `Renamed` | Same library, new package id |
| `Replaced` | Different library, established successor |
| `Blocked` | No MAUI path; needs a decision, likely a rewrite |
| `Check` | Supports MAUI from some version; verify the version in use |
| `Ok` | Works unchanged |

Add API and XAML rules the same way in `$script:ApiRules` and `$script:XamlRules`.

## About

Built by [Syncfusion](https://www.syncfusion.com), an active contributor to the [.NET MAUI open-source project](https://github.com/dotnet/maui), including migrating MAUI's own UI test suite from Xamarin.UITest to Appium, which is a large part of why this tool has opinions about what does and does not survive the move.

> "We are thrilled to welcome Syncfusion as active contributors to the .NET MAUI open-source project. Their commitment to the success of .NET MAUI is incredible and their expertise in this space invaluable."
>
> — [David Ortinau, Principal Product Manager, .NET MAUI, Microsoft](https://devblogs.microsoft.com/dotnet/dotnet-maui-welcomes-syncfusion-open-source-contributions/)

- [Syncfusion's merged contributions to .NET MAUI](https://github.com/dotnet/maui/pulls?q=is%3Apr+is%3Amerged+label%3Apartner%2Fsyncfusion)
- [Syncfusion Toolkit for .NET MAUI](https://github.com/syncfusion/maui-toolkit): free, MIT-licensed controls
- [Xamarin to .NET MAUI migration guides](https://help.syncfusion.com/maui/common/migration)

This tool is useful whether or not you use Syncfusion controls. It reports on your whole solution, not on ours.

## License

MIT. See [LICENSE](LICENSE).
