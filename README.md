# Xamarin to .NET MAUI Migration Advisor

[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue)](https://github.com/PowerShell/PowerShell)
[![Rule set](https://img.shields.io/badge/rule%20set-2026--08--11-lightgrey)](#rule-set-and-release-notes)
[![No network](https://img.shields.io/badge/network-none-success)](#privacy)

A single-file PowerShell scanner that reads a Xamarin.Forms solution, identifies what stands between it and .NET MAUI, and writes a self-contained HTML report you can hand to whoever approves the budget.

```powershell
.\Invoke-XamarinMigrationReadiness.ps1 -Path C:\src\MyApp
```

No install. No account. No upload. The script reads your files and writes one HTML file, then exits.

---

## Contents

- [Why now](#why-now)
- [What it finds](#what-it-finds)
- [Sample output](#sample-output)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Parameters](#parameters)
- [The readiness score](#the-readiness-score)
- [Privacy](#privacy)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Rule set and release notes](#rule-set-and-release-notes)
- [About](#about)
- [Licence](#licence)

---

## Why now

Two platform store deadlines have closed on Xamarin apps, and neither is a support-policy question:

- **Since 28 April 2026**, every App Store Connect upload must be built with **Xcode 26 and the iOS 26 SDK**. Xamarin.iOS has **no iOS 26 SDK target**, so a build cannot currently be produced for App Store Connect. ([Apple](https://developer.apple.com/news/upcoming-requirements/))
- **From 31 August 2026**, new apps and updates on Google Play must target **Android 16 (API 36)**, with an extension available to 1 November 2026. Xamarin.Android **tops out below API 36**. ([Google](https://developer.android.com/google/play/requirements/target-sdk))

A Xamarin app today is not merely unsupported. **It cannot ship updates to either store.**

Most teams know they have to move. What they don't know is what it will cost, and the parts that hurt most: UWP heads, iOS app extensions, binding projects, and an archived dependency with no migration path. These are the parts that the .NET Upgrade Assistant does not cover, and they are the focus of this tool: it finds them before you commit to a date.

A third, softer deadline applies further out: the `Microsoft.Maui.Controls.Compatibility` shim does not ship in .NET 11, which puts a hard date on legacy compatibility code. See [Known issues](#known-issues).

---

## What it finds

| | |
|---|---|
| **Custom renderers** | Every `[assembly: ExportRenderer]` and renderer class, with the file and line, and the recommended handler API to port to |
| **Platform effects** | `PlatformEffect` implementations and `ExportEffect` registrations |
| **Projects the Upgrade Assistant will not convert** | UWP, iOS app extensions, iOS and Android binding projects, Xamarin.Mac, tvOS, watchOS, Tizen |
| **Standard Xamarin heads** | Xamarin.iOS and Xamarin.Android (info-only — handled by the Upgrade Assistant) |
| **Dependencies with no MAUI path** | ~60 package rules covering absorbed, renamed, replaced, archived and blocked packages |
| **Removed and obsoleted APIs** | `Device.RuntimePlatform`, `Device.OpenUri`, `Device.Idiom`, `Application.Properties`, `MessagingCenter`, `DependencyService` (each member reported separately) |
| **.NET 11 blockers** | Anything depending on `Microsoft.Maui.Controls.Compatibility`, which stops shipping in .NET 11 |
| **XAML issues** | `RelativeLayout`, `Frame`, `TableView`, `ListView`, `StackLayout`, retired `OnPlatform` targets, the Xamarin.Forms XAML namespace |
| **Syncfusion control mapping** | Xamarin package → MAUI package, where Syncfusion Xamarin packages are present |
| **An effort estimate** | In developer-days, with every input, rate, and exclusion shown so you can substitute your own |

Each finding carries the file and line that produced it, so you can open it and check.

---

## Sample output

Console summary (`-SkipReport`):

```
Xamarin Migration Readiness
  version 1.0.0  |  rule set 2026-08-11
  scanning C:\src\MyApp

Result
  Readiness score      62 / 100  (Moderate)
  Findings             1 critical, 7 high, 12 medium, 4 low
  Estimated effort     18-42 developer-days
  Projects             6
  Packages evaluated   47

  Google Play API 36 deadline: 11 day(s) away (31 Aug 2026; extension to 1 Nov)
  App Store: since 28 Apr 2026 uploads require Xcode 26 / iOS 26 SDK. Xamarin cannot build these.

  Report written to C:\temp\report.html
```

The HTML report is a single file with a hero card (score, band, effort range), tabbed findings tables grouped by severity, the full project list, the full package list with status and MAUI path, the Syncfusion mapping table (when applicable), and the readiness-score and effort-model mathematics with the actual numbers substituted in.

---

## Prerequisites

| | |
|---|---|
| **PowerShell** | Windows PowerShell 5.1 (ships with Windows 10/11) **or** PowerShell 7+ on any OS |
| **Permissions** | Read access to the source tree; write access to the output folder |
| **Disk** | ~1 MB free for the report. The source tree is not modified. |
| **Network** | None. The tool makes no network calls. |

Verify your PowerShell version:

```powershell
$PSVersionTable.PSVersion
```

On Linux / macOS, install PowerShell 7+:

```bash
# macOS (Homebrew)
brew install --cask powershell

# Ubuntu / Debian
sudo apt-get install -y powershell
```

Then invoke the script with `pwsh` rather than `.\`:

```bash
pwsh ./Invoke-XamarinMigrationReadiness.ps1 -Path ~/src/MyApp
```

---

## Installation

There is nothing to install. The tool is one file.

```powershell
# Save the script to your solution root, or anywhere on $env:PATH
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/syncfusion/Xamarin-MAUI-Migration-Advisor/main/Invoke-XamarinMigrationReadiness.ps1' -OutFile .\Invoke-XamarinMigrationReadiness.ps1

# Or just download it from the repo and place it next to your .sln file
```

The only file it writes is the HTML report at `-OutputPath` (default `.\xamarin-migration-readiness.html`).

---

## Usage

```powershell
# Scan the current folder, write ./xamarin-migration-readiness.html
.\Invoke-XamarinMigrationReadiness.ps1

# Scan somewhere else, write somewhere else
.\Invoke-XamarinMigrationReadiness.ps1 -Path C:\src\MyApp -OutputPath C:\temp\report.html

# Console summary only; do not write the HTML file
.\Invoke-XamarinMigrationReadiness.ps1 -SkipReport

# Include test projects (excluded by default)
.\Invoke-XamarinMigrationReadiness.ps1 -IncludeTestProjects

# Use a larger file-size cap if you have generated files larger than 2 MB
.\Invoke-XamarinMigrationReadiness.ps1 -MaxFileSizeKB 8192
```

---

## Parameters

| Parameter | Default | |
|---|---|---|
| `-Path` | `.` | Root folder to scan |
| `-OutputPath` | `.\xamarin-migration-readiness.html` | Where to write the report |
| `-SkipReport` | off | Print the console summary only; the HTML report is not written. Errors are still printed to stderr. |
| `-IncludeTestProjects` | off | Include projects whose names look like test projects |
| `-MaxFileSizeKB` | `2048` | Skip source and project files larger than this. Guards against generated files. |

**Requires** Windows PowerShell 5.1 or PowerShell 7+. Runs on Windows, macOS and Linux. No modules, no dependencies.

Folders excluded from the scan: `bin`, `obj`, `packages`, `node_modules`, `.git`, `.vs`, `TestResults`, `artifacts`.
Generated files excluded: `*.g.cs`, `*.designer.cs`, `*.generated.cs`.

---

## The readiness score

A number between 1 and 100 measuring **blocker density**, so a large application is not penalised simply for being large. Higher is better; the score decreases monotonically as blocker density increases.

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

These constants are calibrated against the rule set in `$script:ScoreWeights` and can be tuned. The report prints the full calculation with your numbers substituted in, so you can adjust the weights to match your own team's experience. The same is true of the effort model: every rate is listed in the report, line by line.

**The readiness score excludes new features, redesign, QA cycles, store review and team ramp-up on MAUI.** Those need a separate conversation.

---

## Privacy

The tool makes **no network calls**. Nothing is uploaded, nothing is sent anywhere, and no telemetry is collected. The script is one file, and the only file it writes is the HTML report.

The report contains file paths and short code excerpts from your solution. Review the report before sharing it outside your team.

If you want to verify this yourself, there are greppable signs in the script: no `Invoke-WebRequest`, no `Invoke-RestMethod`, no reference to `System.Net.Http.HttpClient`, `System.Net.WebClient`, `System.Net.Sockets`, or any URL-shaped string outside the docstrings and this README.

---

## Limitations

This is static text analysis, not compilation. Specifically it **cannot** see:

- Runtime behaviour, reflection or dynamically constructed types
- Source generators, or anything behind conditional compilation symbols
- Whether a custom renderer is trivial or three weeks of work — the tool counts them but does not weigh them
- Transitive NuGet dependencies. Only packages declared in `packages.config` and `PackageReference` are evaluated
- F# and VB source files are listed (they appear in the project list) but **not scanned for API rules**. Only `*.cs` and `*.xaml` are scanned.
- Whether a package marked `Unknown` is fine. `Unknown` means *not in the rule set*, which is **not a judgement about the package**.

The effort estimate is a **planning input, not a quote**. It assumes the app currently builds, and it excludes new features, redesign, QA cycles, store review, and team ramp-up on MAUI.

Package guidance goes stale as community ports appear and are abandoned. Entries marked **verify** in the report are ones we would like a second pair of eyes on. If you find one that is wrong, please open an issue — that's the fastest way to make this better for the next team.

---

## Troubleshooting

**"No projects found"**
The path given does not contain any `*.csproj` or `*.fsproj` files. Point `-Path` at the folder that contains your `.sln` file — typically one level above the projects, not below them.

**The report is empty / everything is `Unknown`**
This usually means the rule set is older than the packages you depend on. The rule set date is printed in the console banner and in the HTML footer. Update the script, or open an issue with the package list and we'll add it.

**An entire file is missing from findings**
Likely too large (default 2 MB cap) or unreadable due to permissions. Increase `-MaxFileSizeKB`, or check file ACLs. The report lists unreadable files in the "Files that could not be read" section.

**The HTML report will not open / shows raw markup**
The file is UTF-8 with no BOM. Open it directly in a modern browser; do not open it from a tool that mangles encoding (some Markdown previewers and email clients).

**Score seems too low / too high**
Read the formula under [The readiness score](#the-readiness-score), substitute your own weights, and rebuild. The score is a planning input, not a verdict.

**Effort estimate much higher than expected**
Check the UWP / extension / binding project counts. These are the most commonly underestimated parts of a Xamarin migration and they dominate the total.

**A file path contains non-ASCII characters in the report**
PowerShell on older Windows builds may save the HTML in the system code page. Pass `-OutputPath` with an ASCII path, or open the HTML in a modern browser which re-decodes UTF-8 correctly.

---

## Contributing

The most valuable contribution is a package rule. **Everything the tool knows lives in one clearly marked section at the top of the script**, so corrections do not require understanding the scan logic.

### Add a package rule

```powershell
@{ Id='Some.Xamarin.Package'
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

### Add an API rule (C#)

Edit `$script:ApiRules`:

```powershell
@{ Pattern='class\s+\w+\s*:\s*(?:\w+\.)*EntryRenderer\b'
   Title='EntryRenderer subclass'
   Severity='High'
   Category='Renderer'
   Fix='Port to an EntryHandler. OnElementChanged becomes CreatePlatformView / ConnectHandler.' }
```

### Add a XAML rule

Edit `$script:XamlRules`:

```powershell
@{ Pattern='<\s*Frame\b'
   Title='Frame'
   Severity='Medium'
   Fix='Frame is obsolete from .NET 9. Replace with Border, which gives you StrokeShape and Shadow.' }
```

The `Severity` values are `Critical`, `High`, `Medium`, `Low`, `Info`. The `Category` is used for grouping in the report and for effort-model lookup (see `$script:EffortHours` in the script).

---

## Rule set and release notes

| | |
|---|---|
| **Tool version** | `1.0.0` (printed in console banner and HTML footer) |
| **Rule set date** | `2026-08-11` — visible in console banner and HTML footer |
| **Package rules** | ~60 unique entries across `$script:PackageRules` and `$script:PackagePrefixRules` |
| **API rules** | 14 entries in `$script:ApiRules` |
| **XAML rules** | 7 entries in `$script:XamlRules` |
| **Project signatures** | 10 kinds in `$script:ProjectSignatures` |

---

## About

Built by [Syncfusion](https://www.syncfusion.com).

Syncfusion actively contributes to the [.NET MAUI open-source project](https://github.com/dotnet/maui), helping improve the framework for the .NET developer community.

> "We are thrilled to welcome Syncfusion as active contributors to the .NET MAUI open-source project. Their commitment to the success of .NET MAUI is incredible and their expertise in this space invaluable."
>
> — [David Ortinau, Principal Product Manager, .NET MAUI, Microsoft](https://devblogs.microsoft.com/dotnet/dotnet-maui-welcomes-syncfusion-open-source-contributions/)

That work includes migrating .NET MAUI's own UI test suite from Xamarin.UITest to Appium, which is part of why this tool has opinions about what does and does not survive the move.

- [View Syncfusion's merged contributions to .NET MAUI](https://github.com/dotnet/maui/pulls?q=is%3Apr+is%3Amerged+label%3Apartner%2Fsyncfusion)
- [Syncfusion Toolkit for .NET MAUI](https://github.com/syncfusion/maui-toolkit) — free, MIT-licensed controls
- [Xamarin to .NET MAUI migration guides](https://help.syncfusion.com/maui/common/migration)

**This tool is useful whether or not you use Syncfusion controls.** It reports on your whole solution, not on ours.

---

## Licence

MIT © 2026 Syncfusion Inc. See [LICENSE](LICENSE).
