# Xamarin MAUI Migration Advisor.
Xamarin MAUI Migration Advisor is a single PowerShell script that scans a Xamarin solution and highlights what may block a move to .NET MAUI. It then generates a self-contained HTML report that can be shared with engineering, product, and budget approvers.

There is no install, no account, and no upload. The script reads local files only and writes one HTML report.

## Quick start

1. Open a PowerShell window.
2. Go to the folder that contains your solution, or choose the folder you want to scan.
3. Run the script.

```powershell
.\XamarinMAUIMigration.ps1 -Path C:\src\MyApp
```

If you omit `-Path`, the Samples folder is scanned.

## Why now

Two platform deadlines have closed on Xamarin apps, and neither is a support-policy question:

- **Since 28 April 2026**, every App Store Connect upload must be built with **Xcode 26 and the iOS 26 SDK**. Xamarin.iOS cannot produce such a build. ([Apple](https://developer.apple.com/news/upcoming-requirements/))
- **From 31 August 2026**, new apps and updates on Google Play must target **Android 16 (API 36)**, with an extension available to 1 November 2026. Xamarin.Android cannot reach it. ([Google](https://developer.android.com/google/play/requirements/target-sdk))

A Xamarin app today is not merely unsupported. It cannot ship updates.

Most teams know they have to move. What they do not always know is what it will cost, and which parts will be hardest to migrate. UWP heads, iOS app extensions, binding projects, and archived dependencies with no migration path are exactly the kinds of projects the .NET Upgrade Assistant leaves untouched. This tool identifies them before you commit to a migration date.

## What it finds

The report focuses on the items below and shows the file and line that produced each result.

| | |
|---|---|
| **Custom renderers** | Every `[assembly: ExportRenderer]` and renderer class, with the file and line, plus the handler equivalent where available |
| **Platform effects** | `PlatformEffect` implementations and `ExportEffect` registrations |
| **Projects the Upgrade Assistant will not convert** | UWP, iOS app extensions, iOS and Android binding projects, Xamarin.Mac, tvOS, and watchOS |
| **Dependencies with no MAUI path** | About 60 package rules covering absorbed, renamed, replaced, archived, and blocked packages |
| **Removed and obsoleted APIs** | `Device.*`, `Application.Properties`, `MessagingCenter`, and `DependencyService` |
| **.NET 11 blockers** | Anything depending on `Microsoft.Maui.Controls.Compatibility`, which is not supported in .NET 11 |
| **XAML issues** | `RelativeLayout`, `Frame`, `TableView`, retired `OnPlatform` targets, and the Xamarin.Forms namespace |
| **Syncfusion control mapping** | Xamarin package to MAUI package mapping where Syncfusion packages are present |
| **Effort estimate** | Estimated in developer-days, with every input and rate shown so you can substitute your own |

Each finding includes the file and line that produced it, so you can open it and verify the result.

## Usage

Use the following procedure to run the scan and review the output.

1. Choose the root folder to scan.
2. Run the script.
3. Review the console summary or the generated HTML report.
4. Share the report with the stakeholders who need migration visibility.

```powershell
# Scan the Samples folder
.\XamarinMAUIMigration.ps1

# Scan another folder and write to a specific output file
.\XamarinMAUIMigration.ps1 -Path C:\src\MyApp -OutputPath C:\temp\report.html

# Console summary only
.\XamarinMAUIMigration.ps1 -SkipReport

# Include test projects, which are excluded by default
.\XamarinMAUIMigration.ps1 -IncludeTestProjects
```

| Parameter | Default | Description |
|---|---|---|
| `-Path` | `.` | Root folder to scan |
| `-OutputPath` | `.\xamarin-maui-migration-readiness.html` | Path where the HTML report is written |
| `-SkipReport` | off | Console summary only |
| `-IncludeTestProjects` | off | Include projects that look like test projects |
| `-MaxFileSizeKB` | `2048` | Skip source files larger than this |

**Requires** Windows PowerShell 5.1 or PowerShell 7+. Runs on Windows, macOS, and Linux. No modules or dependencies are required.

The following folders and generated files are skipped: `bin`, `obj`, `packages`, `node_modules`, `.git`, `.vs`, `TestResults`, `*.g.cs`, and `*.designer.cs`.

## The readiness score

A number between 1 and 100 measuring **blocker density**, so a large application is not penalised simply for being large:

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

Those constants are judgment, not measurement. The report prints the full calculation with your numbers substituted in, so you can disagree with it and recompute. The same is true of the effort model: every rate is listed in the report, line by line.

## Privacy

The tool makes **no network calls**. Nothing is uploaded, nothing is sent anywhere, and no telemetry is collected. The script is a single file, and the only thing it writes is the HTML report.

The report does contain **file paths and short code excerpts from your solution**. Review it before sharing it outside your team.

## Limitations: read these before trusting the output

This is static text analysis, not compilation. Specifically it **cannot** see:

- Runtime behaviour, reflection or dynamically constructed types
- Source generators, or anything behind conditional compilation symbols
- Whether a custom renderer is trivial or three weeks of work, it counts them but does not weigh them
- Transitive NuGet dependencies. Only packages declared in `packages.config` and `PackageReference` are evaluated
- Whether a package marked `Unknown` is fine. `Unknown` means *not in the rule set*, which is not a judgement

The effort estimate is a **planning input, not a quote**. It assumes the app currently builds, and it excludes new features, redesign, QA cycles, store review, and team ramp-up on MAUI.

Package guidance goes stale as community ports appear and are abandoned. Entries marked **verify** in the report are ones we would like a second pair of eyes on. If you find one that is wrong, please open an issue. That is the fastest way to make this better for the next team.

## How to contribute

This is an open-source project, and contributions from users and other contributors are welcome.

The most useful contributions are:

- package rule updates
- API rule updates
- XAML rule updates
- corrections to the migration guidance itself

Everything the tool knows lives in one clearly marked section at the top of the script.

When adding or updating a rule, keep the category, target, note, and confidence consistent with the existing format.

```powershell
@{
Id='Some.Xamarin.Package'
   Status='Replaced'                    # Builtin | Renamed | Replaced | Blocked | Check | Ok
   Target='Some.Maui.Package'
   Note='What changes, and what to watch for.'
   Confidence='Verify' }                # omit if you are certain
```

| Status | Meaning |
|---|---|
| `Builtin` | The capability moved into .NET MAUI or .NET; remove the package |
| `Renamed` | Same library, new package id |
| `Replaced` | Different library, established successor |
| `Blocked` | No supported MAUI path; needs a decision, probably a rewrite |
| `Check` | Supports MAUI from some version; verify the version in use |
| `Ok` | Works unchanged |

Add API and XAML rules the same way, in `$script:ApiRules` and `$script:XamlRules`.

If you find a rule or recommendation that is outdated, please open an issue or submit a correction.

## About

Built by [Syncfusion](https://www.syncfusion.com).

Syncfusion actively contributes to the [.NET MAUI open-source project](https://github.com/dotnet/maui), helping improve the framework for the .NET developer community.

> "We are thrilled to welcome Syncfusion as active contributors to the .NET MAUI open-source project. Their commitment to the success of .NET MAUI is incredible and their expertise in this space invaluable."
>
> - [David Ortinau, Principal Product Manager, .NET MAUI, Microsoft](https://devblogs.microsoft.com/dotnet/dotnet-maui-welcomes-syncfusion-open-source-contributions/)

That work includes migrating .NET MAUI's own UI test suite from Xamarin.UITest to Appium, which is a large part of why this tool has opinions about what does and does not survive the move.

- [View Syncfusion's merged contributions to .NET MAUI](https://github.com/dotnet/maui/pulls?q=is%3Apr+is%3Amerged+label%3Apartner%2Fsyncfusion)
- [Syncfusion Toolkit for .NET MAUI](https://github.com/syncfusion/maui-toolkit) free, MIT-licensed controls
- [Xamarin to .NET MAUI migration guides](https://help.syncfusion.com/maui/common/migration)

This tool is useful whether or not you use Syncfusion controls. It reports on your whole solution, not on ours.

## License

MIT licensed. See [LICENSE](LICENSE).
