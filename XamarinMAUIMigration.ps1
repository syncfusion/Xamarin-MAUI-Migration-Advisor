<#
.SYNOPSIS
    Scans a Xamarin.Forms solution and reports what stands between it and .NET MAUI.

.DESCRIPTION
    Static analysis only. Nothing is uploaded, nothing is executed, no source leaves the machine.
    The script reads project files, C# source and XAML, and produces a self-contained HTML report
    covering:

      * Custom renderers and platform effects that need rewriting as handlers
      * NuGet dependencies with no MAUI path, plus their known replacements
      * Project types the .NET Upgrade Assistant will not convert (UWP, iOS extensions,
        binding projects, Xamarin.Mac, tvOS, watchOS)
      * Xamarin.Forms APIs that were removed or obsoleted in .NET MAUI
      * Code that depends on Microsoft.Maui.Controls.Compatibility, which stops shipping in .NET 11
      * A control-by-control Syncfusion mapping where Syncfusion Xamarin packages are found
      * An effort estimate with the method stated in full

    Two platform deadlines make this urgent, and neither is a Xamarin support-policy question:

      * Since 28 April 2026, App Store Connect requires builds made with Xcode 26 and the
        iOS 26 SDK. Xamarin.iOS cannot produce them.
      * From 31 August 2026, new apps and updates on Google Play must target Android 16
        (API 36), with an extension available to 1 November 2026. Xamarin.Android cannot
        reach it.

    A Xamarin app is therefore not merely unsupported. It cannot ship updates.

.PARAMETER Path
    Root folder of the solution to scan. Defaults to the current directory.

.PARAMETER OutputPath
    Where to write the HTML report. Defaults to .\xamarin-maui-migration-readiness.html

.PARAMETER SkipReport
    Print the console summary only; do not write the HTML file.

.PARAMETER IncludeTestProjects
    Include projects whose names look like test projects. Excluded by default.

.PARAMETER MaxFileSizeKB
    Skip source files larger than this. Defaults to 2048 (2 MB). Guards against generated files.

.EXAMPLE
    .\XamarinMAUIMigration.ps1

.EXAMPLE
    .\XamarinMAUIMigration.ps1 -Path C:\src\MyApp -OutputPath C:\temp\report.html

.NOTES
    Licence : MIT
    Requires: Windows PowerShell 5.1 or PowerShell 7+
    Repo    : https://github.com/syncfusion/Xamarin-MAUI-Migration-Advisor

    Syncfusion actively contributes to the .NET MAUI open-source project.
    https://devblogs.microsoft.com/dotnet/dotnet-maui-welcomes-syncfusion-open-source-contributions/
#>

[CmdletBinding()]
param(
    [string] $Path = ".",
    [string] $OutputPath,
    [switch] $SkipReport,
    [switch] $IncludeTestProjects,
    [int]    $MaxFileSizeKB = 2048
)

$ErrorActionPreference = 'Stop'
$script:ToolVersion = '1.0.0'
$script:RuleSetDate = '2026-08-11'

# ==============================================================================================
#  KNOWLEDGE BASE
#  ---------------------------------------------------------------------------------------------
#  Everything the tool "knows" lives in this section so it can be reviewed and corrected in one
#  place. Syncfusion product team: please verify the mapping tables against the current docs at
#  https://help.syncfusion.com/maui/common/migration before each release. Entries marked
#  Confidence = 'Verify' are ones a maintainer should confirm rather than trust.
# ==============================================================================================

# ---- NuGet packages -------------------------------------------------------------------------
# Status values:
#   Builtin  - the capability moved into .NET MAUI or .NET itself; remove the package
#   Renamed  - same library, new package id
#   Replaced - different library, established successor
#   Blocked  - no supported MAUI path; needs a decision and probably a rewrite
#   Check    - supports MAUI from a given version; verify the version in use
#   Ok       - works unchanged
$script:PackageRules = @(
    # --- Absorbed into MAUI / .NET -----------------------------------------------------------
    @{ Id='Xamarin.Essentials';                Status='Builtin';  Target='Microsoft.Maui.Essentials (built in)'; Note='Namespaces change to Microsoft.Maui.*. Most APIs keep their names.' }
    @{ Id='Xamarin.Forms';                     Status='Builtin';  Target='.NET MAUI framework';                  Note='Remove the package reference; MAUI is an SDK workload.' }
    @{ Id='Xamarin.Forms.Visual.Material';     Status='Builtin';  Target='MAUI handlers';                        Note='Material visual was removed. Style with handlers or the Material 3 Android defaults.' }
    @{ Id='CarouselView.FormsPlugin';          Status='Builtin';  Target='CarouselView';                         Note='CarouselView ships in MAUI.' }
    @{ Id='Xamarin.Forms.Maps';                Status='Renamed';  Target='Microsoft.Maui.Controls.Maps';         Note='API is close; map initialisation moves to MauiProgram.' }

    # --- Straight renames ---------------------------------------------------------------------
    @{ Id='Xamarin.CommunityToolkit';          Status='Renamed';  Target='CommunityToolkit.Maui';                Note='Not a drop-in: several behaviours and converters were dropped or renamed.' }
    @{ Id='Xamarin.CommunityToolkit.Markup';   Status='Renamed';  Target='CommunityToolkit.Maui.Markup' }
    @{ Id='SkiaSharp.Views.Forms';             Status='Renamed';  Target='SkiaSharp.Views.Maui.Controls' }
    @{ Id='ZXing.Net.Mobile';                  Status='Replaced'; Target='ZXing.Net.Maui';                       Note='Rewritten for MAUI; the API is not source-compatible.' }
    @{ Id='ZXing.Net.Mobile.Forms';            Status='Replaced'; Target='ZXing.Net.Maui.Controls' }
    @{ Id='Rg.Plugins.Popup';                  Status='Replaced'; Target='Mopups';                               Note='Community successor by the same lineage. API is close but namespaces change.' }
    @{ Id='Syncfusion.Xamarin.SfPopupLayout';  Status='Replaced'; Target='Syncfusion.Maui.Popup' }

    # --- Superseded by Essentials APIs --------------------------------------------------------
    @{ Id='Plugin.Media';                      Status='Replaced'; Target='MediaPicker (Essentials)' }
    @{ Id='Xam.Plugin.Media';                  Status='Replaced'; Target='MediaPicker (Essentials)' }
    @{ Id='Plugin.Permissions';                Status='Replaced'; Target='Permissions (Essentials)' }
    @{ Id='Plugin.Connectivity';               Status='Replaced'; Target='Connectivity (Essentials)' }
    @{ Id='Plugin.Geolocator';                 Status='Replaced'; Target='Geolocation (Essentials)' }
    @{ Id='Plugin.DeviceInfo';                 Status='Replaced'; Target='DeviceInfo (Essentials)' }
    @{ Id='Plugin.Settings';                   Status='Replaced'; Target='Preferences (Essentials)' }
    @{ Id='Plugin.FilePicker';                 Status='Replaced'; Target='FilePicker (Essentials)' }
    @{ Id='Plugin.Share';                      Status='Replaced'; Target='Share (Essentials)' }
    @{ Id='Plugin.TextToSpeech';               Status='Replaced'; Target='TextToSpeech (Essentials)' }
    @{ Id='Plugin.SecureStorage';              Status='Replaced'; Target='SecureStorage (Essentials)' }
    @{ Id='Xamarin.Auth';                      Status='Replaced'; Target='WebAuthenticator (Essentials)';        Note='Xamarin.Auth is archived. WebAuthenticator covers the common OAuth flow.' }

    # --- Supports MAUI from a given version ---------------------------------------------------
    @{ Id='MvvmCross';                         Status='Check';    Target='MvvmCross 9+';                         Note='MAUI is supported from MvvmCross 9. Confirm the version in use.' }
    @{ Id='Prism.Forms';                       Status='Replaced'; Target='Prism.Maui';                           Note='Prism 9 targets MAUI. Navigation registration changes.' }
    @{ Id='Prism.DryIoc.Forms';                Status='Replaced'; Target='Prism.DryIoc.Maui' }
    @{ Id='Prism.Unity.Forms';                 Status='Replaced'; Target='Prism.DryIoc.Maui';                    Note='The Unity container flavour was not carried forward; DryIoc is the maintained path.'; Confidence='Verify' }
    @{ Id='ReactiveUI.XamForms';               Status='Renamed';  Target='ReactiveUI.Maui' }
    @{ Id='Plugin.Fingerprint';                Status='Check';    Target='Plugin.Fingerprint (MAUI-capable)' }
    @{ Id='Plugin.InAppBilling';               Status='Check';    Target='Plugin.InAppBilling (MAUI-capable)' }
    @{ Id='Xamarin.Forms.InputKit';            Status='Renamed';  Target='InputKit.Maui'; Confidence='Verify' }

    # --- Unmaintained: community fork exists, maintenance status must be checked ---------------
    @{ Id='Xamarin.FFImageLoading.Forms';      Status='Blocked';  Target='FFImageLoading.Maui (community fork)'; Note='The original is archived. A community MAUI fork exists; check its maintenance status before depending on it. MAUI Image plus a caching handler covers many cases.'; Confidence='Verify' }
    @{ Id='Xamarin.FFImageLoading';            Status='Blocked';  Target='FFImageLoading.Maui (community fork)'; Note='See FFImageLoading.Forms.'; Confidence='Verify' }
    @{ Id='Acr.UserDialogs';                   Status='Blocked';  Target='CommunityToolkit.Maui popups + alerts'; Note='Acr.UserDialogs is archived with no official MAUI release. Budget a rewrite of every dialog call site.' }
    @{ Id='FreshMvvm';                         Status='Blocked';  Target='Community port, or move to Shell + DI'; Note='No official MAUI release. Most teams take this as the moment to adopt Shell navigation.'; Confidence='Verify' }
    @{ Id='Xamarin.Forms.PancakeView';         Status='Blocked';  Target='Border, or a community port';          Note='MAUI Border covers corner radius, shadow and gradient stroke for most PancakeView usage.'; Confidence='Verify' }
    @{ Id='Lottie.Forms';                      Status='Replaced'; Target='SkiaSharp.Extended.UI.Maui (SKLottieView)' }
    @{ Id='Com.Airbnb.Xamarin.Forms.Lottie';   Status='Replaced'; Target='SkiaSharp.Extended.UI.Maui (SKLottieView)' }
    @{ Id='Xamarin.Forms.GoogleMaps';          Status='Blocked';  Target='Microsoft.Maui.Controls.Maps, or a community port'; Note='Feature parity is not guaranteed; check the specific map features you use.'; Confidence='Verify' }

    # --- No MAUI target at all ------------------------------------------------------------------
    @{ Id='Xamarin.Forms.Platform.UAP';        Status='Blocked';  Target='WinUI 3 (net-windows target)';         Note='UWP is not a .NET MAUI target platform. This is a rewrite, not a migration.' }
    @{ Id='Xamarin.Forms.Platform.WPF';        Status='Blocked';  Target='None';                                 Note='The WPF backend was never carried to MAUI.' }
    @{ Id='Xamarin.Forms.Platform.GTK';        Status='Blocked';  Target='None';                                 Note='The GTK backend was never carried to MAUI.' }
    @{ Id='Xamarin.Forms.Pages';               Status='Blocked';  Target='None';                                 Note='Removed. Rebuild these pages with standard MAUI layouts.' }
    @{ Id='Xamarin.Forms.Theme.Base';          Status='Blocked';  Target='MAUI Styles / AppThemeBinding' }
    @{ Id='Xamarin.Forms.Theme.Light';         Status='Blocked';  Target='MAUI Styles / AppThemeBinding' }
    @{ Id='Xamarin.Forms.Theme.Dark';          Status='Blocked';  Target='MAUI Styles / AppThemeBinding' }

    # --- Known-good ------------------------------------------------------------------------------
    @{ Id='Newtonsoft.Json';                   Status='Ok' }
    @{ Id='sqlite-net-pcl';                    Status='Ok' }
    @{ Id='SQLitePCLRaw.bundle_green';         Status='Ok' }
    @{ Id='Refit';                             Status='Ok' }
    @{ Id='Polly';                             Status='Ok' }
    @{ Id='AutoMapper';                        Status='Ok' }
    @{ Id='CommunityToolkit.Mvvm';             Status='Ok' }
    @{ Id='Microsoft.Extensions.Http';         Status='Ok' }
    @{ Id='Serilog';                           Status='Ok' }
)

# Prefix rules, evaluated when no exact id match is found.
$script:PackagePrefixRules = @(
    @{ Prefix='Syncfusion.Xamarin.';   Status='Renamed'; TargetFn='Syncfusion'; Note='Syncfusion ships a MAUI equivalent for this control. See the mapping table in this report.' }
    @{ Prefix='Telerik.UI.for.Xamarin';Status='Renamed'; Target='Telerik.UI.for.Maui'; Note='Vendor migration required; check licensing terms for the MAUI product.' }
    @{ Prefix='Xamarin.Android.Support.'; Status='Blocked'; Target='AndroidX'; Note='The Android Support Libraries are end of life. MAUI requires AndroidX equivalents.' }
    @{ Prefix='Xamarin.Forms.Platform.'; Status='Blocked'; Target='None'; Note='Platform backend package with no MAUI equivalent.' }
    @{ Prefix='Xamarin.Forms.';        Status='Check';   Target='Verify MAUI support'; Note='Xamarin.Forms-specific package. Check whether the author shipped a MAUI version.' }
    @{ Prefix='Xam.Plugin.';           Status='Check';   Target='Verify MAUI support'; Note='Classic Xamarin plugin. Many have Essentials equivalents; check before porting.' }
    @{ Prefix='Plugin.';               Status='Check';   Target='Verify MAUI support'; Note='Classic Xamarin plugin. Many have Essentials equivalents; check before porting.' }
)

# ---- Syncfusion Xamarin -> MAUI control mapping ------------------------------------------------
# MAINTAINERS: verify against https://help.syncfusion.com/maui/common/migration before release.
$script:SyncfusionMap = [ordered]@{
    'Syncfusion.Xamarin.Core'              = 'Syncfusion.Maui.Core'
    'Syncfusion.Xamarin.SfDataGrid'        = 'Syncfusion.Maui.DataGrid'
    'Syncfusion.Xamarin.SfChart'           = 'Syncfusion.Maui.Charts'
    'Syncfusion.Xamarin.SfListView'        = 'Syncfusion.Maui.ListView'
    'Syncfusion.Xamarin.SfSchedule'        = 'Syncfusion.Maui.Scheduler'
    'Syncfusion.Xamarin.SfCalendar'        = 'Syncfusion.Maui.Calendar'
    'Syncfusion.Xamarin.SfTreeView'        = 'Syncfusion.Maui.TreeView'
    'Syncfusion.Xamarin.SfPdfViewer'       = 'Syncfusion.Maui.PdfViewer'
    'Syncfusion.Xamarin.SfImageEditor'     = 'Syncfusion.Maui.ImageEditor'
    'Syncfusion.Xamarin.SfPopupLayout'     = 'Syncfusion.Maui.Popup'
    'Syncfusion.Xamarin.SfMaps'            = 'Syncfusion.Maui.Maps'
    'Syncfusion.Xamarin.SfGauge'           = 'Syncfusion.Maui.Gauges'
    'Syncfusion.Xamarin.SfCircularGauge'   = 'Syncfusion.Maui.Gauges'
    'Syncfusion.Xamarin.SfLinearGauge'     = 'Syncfusion.Maui.Gauges'
    'Syncfusion.Xamarin.SfNavigationDrawer'= 'Syncfusion.Maui.NavigationDrawer'
    'Syncfusion.Xamarin.SfTabView'         = 'Syncfusion.Maui.TabView'
    'Syncfusion.Xamarin.SfCarousel'        = 'Syncfusion.Maui.Carousel'
    'Syncfusion.Xamarin.SfPicker'          = 'Syncfusion.Maui.Picker'
    'Syncfusion.Xamarin.SfAutoComplete'    = 'Syncfusion.Maui.Inputs'
    'Syncfusion.Xamarin.SfComboBox'        = 'Syncfusion.Maui.Inputs'
    'Syncfusion.Xamarin.SfNumericTextBox'  = 'Syncfusion.Maui.Inputs'
    'Syncfusion.Xamarin.SfNumericUpDown'   = 'Syncfusion.Maui.Inputs'
    'Syncfusion.Xamarin.SfRating'          = 'Syncfusion.Maui.Inputs'
    'Syncfusion.Xamarin.SfTextInputLayout' = 'Syncfusion.Maui.Core'
    'Syncfusion.Xamarin.Buttons'           = 'Syncfusion.Maui.Buttons'
    'Syncfusion.Xamarin.SfBadgeView'       = 'Syncfusion.Maui.Core'
    'Syncfusion.Xamarin.SfBusyIndicator'   = 'Syncfusion.Maui.Core'
    'Syncfusion.Xamarin.SfProgressBar'     = 'Syncfusion.Maui.ProgressBar'
    'Syncfusion.Xamarin.SfBarcode'         = 'Syncfusion.Maui.Barcode'
}

# ---- Source-code API rules --------------------------------------------------------------------
# Each rule: Pattern (regex), Title, Severity, Fix, Category
$script:ApiRules = @(
    @{ Pattern='\[assembly\s*:\s*ExportRenderer\s*\('; Title='Custom renderer registration'; Severity='High'; Category='Renderer'
       Fix='Renderers do not exist in .NET MAUI. Rewrite as a handler and register it in MauiProgram with ConfigureMauiHandlers, or use a handler mapping if the change is cosmetic.' }
    @{ Pattern='class\s+\w+\s*:\s*(?:\w+\.)*(ViewRenderer|PageRenderer|ListViewRenderer|EntryRenderer|ButtonRenderer|LabelRenderer|ImageRenderer|EditorRenderer|PickerRenderer|SwitchRenderer|SliderRenderer|WebViewRenderer|FrameRenderer|ScrollViewRenderer|TabbedRenderer|NavigationRenderer|CellRenderer|VisualElementRenderer)\b'
       Title='Renderer class'; Severity='High'; Category='Renderer'
       Fix='Port to a handler. The nearest equivalent of OnElementChanged is CreatePlatformView / ConnectHandler.' }
    @{ Pattern='\[assembly\s*:\s*ExportEffect\s*\('; Title='Platform effect registration'; Severity='Medium'; Category='Effect'
       Fix='Effects still work in MAUI but are legacy. Prefer a handler mapping; if you keep the effect, the registration attribute stays but namespaces change.' }
    @{ Pattern='class\s+\w+\s*:\s*(?:\w+\.)*PlatformEffect\b'; Title='PlatformEffect implementation'; Severity='Medium'; Category='Effect'
       Fix='Consider a handler property mapper instead, which is the maintained path in MAUI.' }
    @{ Pattern='\[assembly\s*:\s*Dependency\s*\('; Title='DependencyService registration'; Severity='Medium'; Category='DI'
       Fix='DependencyService is obsolete. Register the implementation in MauiProgram via builder.Services and inject it.' }
    @{ Pattern='DependencyService\s*\.\s*(Get|Resolve)\s*<'; Title='DependencyService resolution'; Severity='Medium'; Category='DI'
       Fix='Replace with constructor injection from the MAUI service container.' }
    @{ Pattern='\bMessagingCenter\s*\.'; Title='MessagingCenter usage'; Severity='Medium'; Category='API'
       Fix='MessagingCenter is obsolete in .NET 9 and later. Move to WeakReferenceMessenger from CommunityToolkit.Mvvm.' }
    @{ Pattern='\bDevice\s*\.\s*RuntimePlatform\b'; Title='Device.RuntimePlatform'; Severity='Medium'; Category='API'
       Fix='The Device class was removed. Use DeviceInfo.Current.Platform.' }
    @{ Pattern='\bDevice\s*\.\s*BeginInvokeOnMainThread\b'; Title='Device.BeginInvokeOnMainThread'; Severity='Low'; Category='API'
       Fix='Use MainThread.BeginInvokeOnMainThread.' }
    @{ Pattern='\bDevice\s*\.\s*StartTimer\b'; Title='Device.StartTimer'; Severity='Medium'; Category='API'
       Fix='Use Application.Current.Dispatcher.StartTimer, or a PeriodicTimer.' }
    @{ Pattern='\bDevice\s*\.\s*(OpenUri|Idiom|Info|GetNamedSize|Styles)\b'; Title='Device class member'; Severity='Medium'; Category='API'
       Fix='The Device class was removed. OpenUri becomes Launcher.OpenAsync; Idiom becomes DeviceInfo.Current.Idiom.' }
    @{ Pattern='Application\s*\.\s*Current\s*\.\s*Properties\b'; Title='Application.Properties dictionary'; Severity='High'; Category='API'
       Fix='Removed in MAUI. Migrate stored values to Preferences, and write a one-time upgrade path for existing installs or users lose their data.' }
    @{ Pattern='\bMicrosoft\.Maui\.Controls\.Compatibility\b'; Title='Compatibility namespace'; Severity='High'; Category='NET11'
       Fix='Microsoft.Maui.Controls.Compatibility does not ship in .NET 11. Anything relying on it must be ported before you can move to .NET 11.' }
    @{ Pattern='using\s+Xamarin\.Forms\s*;'; Title='Xamarin.Forms namespace import'; Severity='Low'; Category='Namespace'
       Fix='Becomes Microsoft.Maui.Controls. Largely mechanical; the Upgrade Assistant handles most of these.' }
    @{ Pattern='\bExportFont\b|\bExportRendererAttribute\b'; Title='Assembly-level Xamarin attribute'; Severity='Low'; Category='Namespace'
       Fix='Fonts are registered in MauiProgram with ConfigureFonts.' }
)

$script:XamlRules = @(
    @{ Pattern='xmlns\s*=\s*"http://xamarin\.com/schemas/2014/forms"'; Title='Xamarin.Forms XAML namespace'; Severity='Low'
       Fix='Change to http://schemas.microsoft.com/dotnet/2021/maui.' }
    @{ Pattern='<\s*RelativeLayout\b'; Title='RelativeLayout'; Severity='High'
       Fix='RelativeLayout lives only in the compatibility namespace, which does not ship in .NET 11. Rebuild with Grid or a custom layout before then.' }
    @{ Pattern='<\s*Frame\b'; Title='Frame'; Severity='Medium'
       Fix='Frame is obsolete from .NET 9. Replace with Border, which gives you StrokeShape and Shadow.' }
    @{ Pattern='<\s*StackLayout\b'; Title='StackLayout'; Severity='Low'
       Fix='Still supported, but VerticalStackLayout and HorizontalStackLayout are faster and are the recommended default. Note that default spacing differs from Xamarin.Forms.' }
    @{ Pattern='<\s*TableView\b'; Title='TableView'; Severity='Medium'
       Fix='Supported but lightly maintained. A CollectionView with grouping is usually a better target.' }
    @{ Pattern='<\s*ListView\b'; Title='ListView'; Severity='Low'
       Fix='Supported, but CollectionView performs better and is where the investment goes.' }
    @{ Pattern='On\s+Platform\s*=|<\s*On\s+Platform\s*=\s*"(UWP|WinPhone|macOS)"'; Title='OnPlatform with a retired platform'; Severity='Medium'
       Fix='UWP and WinPhone are not MAUI platforms. Use WinUI for Windows and MacCatalyst for macOS.' }
)

$script:ProjectSignatures = @(
    @{ Kind='UWP';            Severity='Critical'; Match={ param($t,$f) $t -match '<TargetPlatformIdentifier>\s*UAP' -or $t -match 'Microsoft\.NET\.Native' -or $f -match '\.appxmanifest' }
       Note='The .NET Upgrade Assistant does not convert UWP projects. UWP is not a .NET MAUI target platform; the Windows head must be rebuilt on WinUI 3. Treat this as a rewrite with its own estimate.' }
    @{ Kind='iOS binding';    Severity='Critical'; Match={ param($t,$f) $t -match 'Xamarin\.iOS\.ObjCBinding' -or $t -match '<ObjcBindingApiDefinition' }
       Note='Binding projects are not converted by the Upgrade Assistant. They must be recreated as .NET for iOS binding projects, and any bound native library needs rebuilding against the current SDK.' }
    @{ Kind='Android binding';Severity='High';     Match={ param($t,$f) $t -match 'Xamarin\.Android\.Bindings' -or $t -match '<AndroidLibrary\b[^>]*Bind' }
       Note='Recreate as a .NET for Android binding library. AndroidX migration usually lands here at the same time.' }
    @{ Kind='iOS extension';  Severity='Critical'; Match={ param($t,$f) $t -match '<IsAppExtension>\s*true' -or $t -match 'NSExtension' }
       Note='App extensions are not handled by the Upgrade Assistant and must be recreated by hand. Share code with the main app through a class library.' }
    @{ Kind='Xamarin.Mac';    Severity='High';     Match={ param($t,$f) $t -match 'Xamarin\.Mac\.CSharp\.targets' }
       Note='Xamarin.Mac has no MAUI equivalent. Mac Catalyst is the MAUI path and behaves differently from AppKit.' }
    @{ Kind='tvOS';           Severity='High';     Match={ param($t,$f) $t -match 'Xamarin\.TVOS' -or $t -match '<TargetFrameworkIdentifier>\s*Xamarin\.TVOS' }
       Note='.NET MAUI does not target tvOS. .NET for tvOS exists, but without MAUI UI on top.' }
    @{ Kind='watchOS';        Severity='High';     Match={ param($t,$f) $t -match 'Xamarin\.WatchOS' }
       Note='.NET MAUI does not target watchOS. The watch app must be maintained separately.' }
    @{ Kind='Tizen';          Severity='Medium';   Match={ param($t,$f) $t -match 'Tizen\.NET' }
       Note='MAUI Tizen support is community-maintained by Samsung and is not part of the core supported matrix.' }
    @{ Kind='Xamarin.Android';Severity='Info';     Match={ param($t,$f) $t -match 'Xamarin\.Android\.CSharp\.targets' -or $t -match '<AndroidApplication>\s*true' }
       Note='Standard Android head. The Upgrade Assistant handles the project conversion; platform code still needs review.' }
    @{ Kind='Xamarin.iOS';    Severity='Info';     Match={ param($t,$f) $t -match 'Xamarin\.iOS\.CSharp\.targets' -or $t -match '<MtouchArch' }
       Note='Standard iOS head. Since 28 April 2026 this project cannot produce an App Store build.' }
)

# ---- Effort model ------------------------------------------------------------------------------
# Hours per finding. These are medians from published migration write-ups and are deliberately
# conservative. The report shows the method so a reader can substitute their own numbers.
$script:EffortHours = @{
    'BaseSetup'        = 16
    'Renderer'         = 4
    'Effect'           = 2
    'DI'               = 0.5
    'API'              = 0.5
    'NET11'            = 2
    'Namespace'        = 0.1
    'XamlFileHigh'     = 2
    'XamlFileMedium'   = 1
    'XamlFileLow'      = 0.25
    'PackageBlocked'   = 8
    'PackageReplaced'  = 2
    'PackageRenamed'   = 1
    'PackageCheck'     = 1
    'PackageBuiltin'   = 0.5
    'ProjectUWP'       = 40
    'ProjectExtension' = 12
    'ProjectBinding'   = 8
    'ProjectOther'     = 16
    'ProjectHead'      = 4
}

# ==============================================================================================
#  HELPERS
# ==============================================================================================

function Write-Step { param([string]$Message) Write-Host "  $Message" -ForegroundColor DarkGray }

function Get-RelativePath {
    param([string]$FullName, [string]$Root)
    $r = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\','/')
    if ($FullName.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($r.Length).TrimStart('\','/')
    }
    return $FullName
}

function Test-Excluded {
    param([string]$FullName)
    # Directory separators are normalised so one pattern set covers Windows and Unix.
    $p = $FullName -replace '\\','/'
    foreach ($seg in @('/bin/','/obj/','/packages/','/node_modules/','/.git/','/.vs/','/TestResults/','/artifacts/')) {
        if ($p -like "*$seg*") { return $true }
    }
    return $false
}

function Test-TestProject {
    param([string]$Name)
    return ($Name -match '(?i)\.(tests?|unittests?|specs?|uitests?)(\.|$)' -or $Name -match '(?i)^(tests?|unittests?)$')
}

function Get-SafeContent {
    param([System.IO.FileInfo]$File, [int]$MaxKB)
    if ($File.Length -gt ($MaxKB * 1KB)) { return $null }
    try { return Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop }
    catch { return $null }
}

function Get-LineNumber {
    param([string]$Text, [int]$Index)
    if ($Index -le 0) { return 1 }
    $prefix = $Text.Substring(0, [Math]::Min($Index, $Text.Length))
    return ([regex]::Matches($prefix, "`n")).Count + 1
}

function New-Finding {
    param($Title, $Severity, $Category, $File, $Line, $Fix, $Evidence)
    return [pscustomobject]@{
        Title = $Title; Severity = $Severity; Category = $Category
        File = $File; Line = $Line; Fix = $Fix; Evidence = $Evidence
    }
}

function ConvertTo-HtmlText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

# ==============================================================================================
#  SCAN
# ==============================================================================================

$root = (Resolve-Path -LiteralPath $Path).Path
Write-Host ""
Write-Host "Xamarin Migration Readiness" -ForegroundColor Cyan
Write-Host "  version $script:ToolVersion  |  rule set $script:RuleSetDate" -ForegroundColor DarkGray
Write-Host "  scanning $root" -ForegroundColor DarkGray
Write-Host ""

$findings   = New-Object System.Collections.ArrayList
$projects   = New-Object System.Collections.ArrayList
$packages   = @{}   # id -> @{ Version, Projects[] }
$scanErrors = New-Object System.Collections.ArrayList

# ---- Projects ---------------------------------------------------------------------------------
Write-Step "Enumerating projects..."
$projFiles = @(Get-ChildItem -LiteralPath $root -Recurse -Include *.csproj,*.fsproj -File -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-Excluded $_.FullName) })

$solutionFiles = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.sln -File -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-Excluded $_.FullName) })

foreach ($pf in $projFiles) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($pf.Name)
    $isTest = Test-TestProject $name
    if ($isTest -and -not $IncludeTestProjects) { continue }

    $text = Get-SafeContent -File $pf -MaxKB $MaxFileSizeKB
    if ($null -eq $text) { [void]$scanErrors.Add("Could not read $($pf.FullName)"); continue }

    $siblingNames = ''
    try {
        $siblingNames = (Get-ChildItem -LiteralPath $pf.DirectoryName -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name) -join ';'
        $plist = Join-Path $pf.DirectoryName 'Info.plist'
        if (Test-Path -LiteralPath $plist) {
            $plistText = Get-Content -LiteralPath $plist -Raw -ErrorAction SilentlyContinue
            if ($plistText) { $text = $text + "`n<!--INFOPLIST-->`n" + $plistText }
        }
    } catch { }

    $kinds = New-Object System.Collections.ArrayList
    foreach ($sig in $script:ProjectSignatures) {
        if (& $sig.Match $text $siblingNames) { [void]$kinds.Add($sig) }
    }

    $tfm = ''
    if ($text -match '<TargetFrameworkVersion>\s*([^<]+)</TargetFrameworkVersion>') { $tfm = $Matches[1].Trim() }
    elseif ($text -match '<TargetFramework(?:s)?>\s*([^<]+)</TargetFramework(?:s)?>') { $tfm = $Matches[1].Trim() }

    $rel = Get-RelativePath -FullName $pf.FullName -Root $root
    $kindNames = if ($kinds.Count) { ($kinds | ForEach-Object { $_.Kind }) -join ', ' } else { 'Library / shared' }

    [void]$projects.Add([pscustomobject]@{
        Name = $name; Path = $rel; Kinds = $kindNames; Tfm = $tfm; IsTest = $isTest
        Blocking = @($kinds | Where-Object { $_.Severity -in @('Critical','High') }).Count
    })

    foreach ($k in $kinds) {
        if ($k.Severity -eq 'Info') { continue }
        [void]$findings.Add((New-Finding -Title "$($k.Kind) project: $name" -Severity $k.Severity `
            -Category 'Project' -File $rel -Line 1 -Fix $k.Note -Evidence $name))
    }

    # ---- packages: PackageReference ----
    foreach ($m in [regex]::Matches($text, '<PackageReference\s+[^>]*Include\s*=\s*"([^"]+)"[^>]*?(?:Version\s*=\s*"([^"]+)")?')) {
        $id = $m.Groups[1].Value; $ver = $m.Groups[2].Value
        if (-not $packages.ContainsKey($id)) { $packages[$id] = @{ Version = $ver; Projects = @() } }
        elseif ($ver -and -not $packages[$id].Version) { $packages[$id].Version = $ver }
        $packages[$id].Projects += $name
    }

    # ---- packages: packages.config ----
    $pc = Join-Path $pf.DirectoryName 'packages.config'
    if (Test-Path -LiteralPath $pc) {
        try {
            $pcText = Get-Content -LiteralPath $pc -Raw -ErrorAction Stop
            foreach ($m in [regex]::Matches($pcText, '<package\s+id\s*=\s*"([^"]+)"\s+version\s*=\s*"([^"]*)"')) {
                $id = $m.Groups[1].Value; $ver = $m.Groups[2].Value
                if (-not $packages.ContainsKey($id)) { $packages[$id] = @{ Version = $ver; Projects = @() } }
                $packages[$id].Projects += $name
            }
        } catch { [void]$scanErrors.Add("Could not read $pc") }
    }
}
Write-Step "$($projects.Count) project(s), $($solutionFiles.Count) solution file(s)"

# ---- Source files -----------------------------------------------------------------------------
Write-Step "Scanning C# source..."
$csFiles = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-Excluded $_.FullName) -and $_.Name -notmatch '\.(g|designer|generated)\.cs$' })

foreach ($f in $csFiles) {
    if ((Test-TestProject ([System.IO.Path]::GetFileName($f.DirectoryName))) -and -not $IncludeTestProjects) { continue }
    $text = Get-SafeContent -File $f -MaxKB $MaxFileSizeKB
    if ($null -eq $text) { continue }
    $rel = Get-RelativePath -FullName $f.FullName -Root $root

    foreach ($rule in $script:ApiRules) {
        foreach ($m in [regex]::Matches($text, $rule.Pattern)) {
            $line = Get-LineNumber -Text $text -Index $m.Index
            $ev = ($m.Value -replace '\s+',' ').Trim()
            if ($ev.Length -gt 120) { $ev = $ev.Substring(0,120) + '...' }
            [void]$findings.Add((New-Finding -Title $rule.Title -Severity $rule.Severity `
                -Category $rule.Category -File $rel -Line $line -Fix $rule.Fix -Evidence $ev))
        }
    }
}
Write-Step "$($csFiles.Count) C# file(s)"

# ---- XAML -------------------------------------------------------------------------------------
Write-Step "Scanning XAML..."
$xamlFiles = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.xaml -File -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-Excluded $_.FullName) })

foreach ($f in $xamlFiles) {
    $text = Get-SafeContent -File $f -MaxKB $MaxFileSizeKB
    if ($null -eq $text) { continue }
    $rel = Get-RelativePath -FullName $f.FullName -Root $root
    foreach ($rule in $script:XamlRules) {
        $ms = [regex]::Matches($text, $rule.Pattern)
        if ($ms.Count -eq 0) { continue }
        # One finding per rule per file, with the count, rather than one per occurrence.
        $line = Get-LineNumber -Text $text -Index $ms[0].Index
        $ev = "$($ms.Count) occurrence(s)"
        [void]$findings.Add((New-Finding -Title $rule.Title -Severity $rule.Severity `
            -Category 'XAML' -File $rel -Line $line -Fix $rule.Fix -Evidence $ev))
    }
}
Write-Step "$($xamlFiles.Count) XAML file(s)"

# ---- Packages ---------------------------------------------------------------------------------
Write-Step "Evaluating $($packages.Count) NuGet package(s)..."
$packageResults = New-Object System.Collections.ArrayList
$syncfusionFound = New-Object System.Collections.ArrayList

foreach ($id in ($packages.Keys | Sort-Object)) {
    $info = $packages[$id]
    $rule = $script:PackageRules | Where-Object { $_.Id -eq $id } | Select-Object -First 1

    if (-not $rule) {
        foreach ($pr in $script:PackagePrefixRules) {
            if ($id.StartsWith($pr.Prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $target = $pr.Target
                if ($pr.TargetFn -eq 'Syncfusion') {
                    if ($script:SyncfusionMap.Contains($id)) { $target = $script:SyncfusionMap[$id] }
                    else { $target = 'See help.syncfusion.com/maui/common/migration' }
                    [void]$syncfusionFound.Add([pscustomobject]@{ From=$id; To=$target; Version=$info.Version })
                }
                $rule = @{ Id=$id; Status=$pr.Status; Target=$target; Note=$pr.Note }
                break
            }
        }
    }
    if (-not $rule) { $rule = @{ Id=$id; Status='Unknown'; Target=''; Note='' } }

    $sev = switch ($rule.Status) {
        'Blocked'  { 'Critical' }
        'Replaced' { 'High' }
        'Check'    { 'Medium' }
        'Renamed'  { 'Medium' }
        'Builtin'  { 'Low' }
        default    { 'Info' }
    }

    [void]$packageResults.Add([pscustomobject]@{
        Id = $id; Version = $info.Version; Status = $rule.Status; Target = $rule.Target
        Note = $rule.Note; Severity = $sev; Confidence = $rule.Confidence
        Projects = (($info.Projects | Select-Object -Unique) -join ', ')
    })

    if ($rule.Status -in @('Blocked','Replaced','Check','Renamed')) {
        $fix = if ($rule.Target) { "Replace with: $($rule.Target). $($rule.Note)" } else { $rule.Note }
        [void]$findings.Add((New-Finding -Title "Package: $id" -Severity $sev -Category 'Package' `
            -File 'NuGet dependencies' -Line 0 -Fix $fix.Trim() -Evidence "$id $($info.Version)"))
    }
}

# ==============================================================================================
#  SCORE AND EFFORT
# ==============================================================================================

$sevOrder = @{ 'Critical'=0; 'High'=1; 'Medium'=2; 'Low'=3; 'Info'=4 }
$byCat = $findings | Group-Object Category
function Get-CatCount { param($Name) $g = $byCat | Where-Object { $_.Name -eq $Name }; if ($g) { return $g.Count } else { return 0 } }

$counts = [ordered]@{
    Critical = @($findings | Where-Object Severity -eq 'Critical').Count
    High     = @($findings | Where-Object Severity -eq 'High').Count
    Medium   = @($findings | Where-Object Severity -eq 'Medium').Count
    Low      = @($findings | Where-Object Severity -eq 'Low').Count
}

# Effort, built up so each contribution is visible in the report.
$effortLines = New-Object System.Collections.ArrayList
function Add-Effort {
    param($Label, $Count, $Rate)
    if ($Count -le 0) { return }
    [void]$effortLines.Add([pscustomobject]@{ Label=$Label; Count=$Count; Rate=$Rate; Hours=[math]::Round($Count*$Rate,1) })
}

# A single renderer usually produces two findings (the [assembly: ExportRenderer] registration and
# the class declaration). Effort is therefore counted per distinct FILE, not per finding, or a
# three-renderer app reads as a six-renderer app. The findings list still shows both, because both
# are real evidence a reader may want to click through to.
$rendererFiles = @($findings | Where-Object Category -eq 'Renderer' | Select-Object -ExpandProperty File -Unique).Count
$effectFiles   = @($findings | Where-Object Category -eq 'Effect'   | Select-Object -ExpandProperty File -Unique).Count

# An iOS extension project also matches the generic Xamarin.iOS signature. Count it once, as the
# more expensive of the two.
$headProjects = @($projects | Where-Object {
    $_.Kinds -match 'Xamarin\.(Android|iOS)' -and $_.Kinds -notmatch 'extension|binding'
}).Count

Add-Effort 'Project and build setup'          1 $script:EffortHours.BaseSetup
Add-Effort 'Platform heads to convert'        $headProjects $script:EffortHours.ProjectHead
Add-Effort 'UWP project rewrite (WinUI 3)'    (@($projects | Where-Object { $_.Kinds -match 'UWP' }).Count) $script:EffortHours.ProjectUWP
Add-Effort 'iOS app extensions to recreate'   (@($projects | Where-Object { $_.Kinds -match 'iOS extension' }).Count) $script:EffortHours.ProjectExtension
Add-Effort 'Binding projects to recreate'     (@($projects | Where-Object { $_.Kinds -match 'binding' }).Count) $script:EffortHours.ProjectBinding
Add-Effort 'Other unsupported project types'  (@($projects | Where-Object { $_.Kinds -match 'Xamarin\.Mac|tvOS|watchOS' }).Count) $script:EffortHours.ProjectOther
Add-Effort 'Custom renderers to port'         $rendererFiles $script:EffortHours.Renderer
Add-Effort 'Platform effects to review'       $effectFiles   $script:EffortHours.Effect
Add-Effort 'DependencyService call sites'     (Get-CatCount 'DI')       $script:EffortHours.DI
Add-Effort 'Removed or obsoleted APIs'        (Get-CatCount 'API')      $script:EffortHours.API
Add-Effort 'Compatibility-namespace work'     (Get-CatCount 'NET11')    $script:EffortHours.NET11
Add-Effort 'Namespace updates'                (Get-CatCount 'Namespace') $script:EffortHours.Namespace

$xamlHigh   = @($findings | Where-Object { $_.Category -eq 'XAML' -and $_.Severity -eq 'High' }).Count
$xamlMed    = @($findings | Where-Object { $_.Category -eq 'XAML' -and $_.Severity -eq 'Medium' }).Count
$xamlLow    = @($findings | Where-Object { $_.Category -eq 'XAML' -and $_.Severity -eq 'Low' }).Count
Add-Effort 'XAML: high-severity changes'   $xamlHigh $script:EffortHours.XamlFileHigh
Add-Effort 'XAML: medium-severity changes' $xamlMed  $script:EffortHours.XamlFileMedium
Add-Effort 'XAML: low-severity changes'    $xamlLow  $script:EffortHours.XamlFileLow

Add-Effort 'Packages with no MAUI path'    (@($packageResults | Where-Object Status -eq 'Blocked').Count)  $script:EffortHours.PackageBlocked
Add-Effort 'Packages to swap'              (@($packageResults | Where-Object Status -eq 'Replaced').Count) $script:EffortHours.PackageReplaced
Add-Effort 'Packages to rename'            (@($packageResults | Where-Object Status -eq 'Renamed').Count)  $script:EffortHours.PackageRenamed
Add-Effort 'Packages to verify'            (@($packageResults | Where-Object Status -eq 'Check').Count)    $script:EffortHours.PackageCheck
Add-Effort 'Packages to remove'            (@($packageResults | Where-Object Status -eq 'Builtin').Count)  $script:EffortHours.PackageBuiltin

$nothingFound = ($projects.Count -eq 0)
if ($nothingFound) {
    # No projects at all almost always means the wrong folder was scanned, not a clean codebase.
    # Reporting "100 / 100, ready to migrate" here would be actively misleading.
    $effortLines.Clear()
}

$totalHours = ($effortLines | Measure-Object -Property Hours -Sum).Sum
if (-not $totalHours) { $totalHours = 0 }
$lowDays  = [math]::Max(1, [math]::Round(($totalHours * 0.6) / 8, 0))
$highDays = [math]::Max(2, [math]::Round(($totalHours * 1.4) / 8, 0))

# Readiness score.
#
# A flat "100 minus penalties" scale bottoms out at zero for any real application, which tells the
# reader nothing and makes every messy codebase look identical. Instead the penalty is normalised
# by codebase size and passed through an exponential decay, so the score always differentiates and
# never quite reaches zero. A large app with many findings is not automatically worse off than a
# small app with a few — what matters is blocker density.
#
#   penalty = 10*critical + 4*high + 1*medium + 0.2*low
#   scale   = 40 + 8*projects + 0.4*sourceFiles
#   score   = 100 * e^(-penalty/scale)
#
# The constants are judgement, not measurement. They are exposed here so a reader can disagree
# with them and recompute.
$penalty   = ($counts.Critical * 10) + ($counts.High * 4) + ($counts.Medium * 1) + ($counts.Low * 0.2)
$sizeScale = 40 + (8 * $projects.Count) + (0.4 * ($csFiles.Count + $xamlFiles.Count))
if ($sizeScale -le 0) { $sizeScale = 40 }
$score = [math]::Round(100 * [math]::Exp(-1 * $penalty / $sizeScale), 0)
$score = [math]::Max(1, [math]::Min(100, $score))
$band = if ($score -ge 70) { 'Straightforward' } elseif ($score -ge 45) { 'Moderate' } elseif ($score -ge 25) { 'Substantial' } else { 'Major' }

# Deadline maths
$playDeadline = Get-Date '2026-08-31'
$playExt      = Get-Date '2026-11-01'
$daysToPlay   = [math]::Ceiling(($playDeadline - (Get-Date)).TotalDays)
$daysToExt    = [math]::Ceiling(($playExt - (Get-Date)).TotalDays)

# ==============================================================================================
#  CONSOLE SUMMARY
# ==============================================================================================
Write-Host ""
if ($nothingFound) {
    Write-Host "No projects found" -ForegroundColor Yellow
    Write-Host "  No .csproj or .fsproj files were found under the path given. That usually means" -ForegroundColor DarkGray
    Write-Host "  the wrong folder was scanned rather than a codebase with nothing to fix." -ForegroundColor DarkGray
    Write-Host "  Point -Path at the folder containing your .sln file and run it again." -ForegroundColor DarkGray
    Write-Host ""
    if ($SkipReport) { return }
}
else {
    Write-Host "Result" -ForegroundColor Cyan
    Write-Host "  Readiness score      $score / 100  ($band)"
    Write-Host ("  Findings             {0} critical, {1} high, {2} medium, {3} low" -f $counts.Critical,$counts.High,$counts.Medium,$counts.Low)
    Write-Host ("  Estimated effort     {0}-{1} developer-days" -f $lowDays,$highDays)
    Write-Host ("  Projects             {0}" -f $projects.Count)
    Write-Host ("  Packages evaluated   {0}" -f $packageResults.Count)
    Write-Host ""
}
if ($daysToPlay -gt 0) {
    Write-Host ("  Google Play API 36 deadline: {0} day(s) away (31 Aug 2026; extension to 1 Nov)" -f $daysToPlay) -ForegroundColor Yellow
} elseif ($daysToExt -gt 0) {
    Write-Host ("  Google Play extension deadline: {0} day(s) away (1 Nov 2026)" -f $daysToExt) -ForegroundColor Red
} else {
    Write-Host "  Both Google Play deadlines have passed." -ForegroundColor Red
}
Write-Host "  App Store: since 28 Apr 2026 uploads require Xcode 26 / iOS 26 SDK. Xamarin cannot build these." -ForegroundColor Yellow
Write-Host ""
if ($scanErrors.Count) { Write-Host "  $($scanErrors.Count) file(s) could not be read; see the report." -ForegroundColor DarkYellow }

if ($SkipReport) { return }

# ==============================================================================================
#  HTML REPORT
# ==============================================================================================
if (-not $OutputPath) { $OutputPath = Join-Path (Get-Location) 'xamarin-maui-migration-readiness.html' }

$sevColour = @{ 'Critical'='#c0392b'; 'High'='#d35400'; 'Medium'='#b7950b'; 'Low'='#5d6d7e'; 'Info'='#7f8c8d' }
$generated = (Get-Date).ToString('d MMMM yyyy, HH:mm')
$solName = if ($solutionFiles.Count -ge 1) { $solutionFiles[0].BaseName } else { Split-Path $root -Leaf }

$sb = New-Object System.Text.StringBuilder
function Add-Html { param([string]$s) [void]$sb.AppendLine($s) }

Add-Html @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Xamarin Migration Readiness - $(ConvertTo-HtmlText $solName)</title>
<style>
*{box-sizing:border-box}
body{margin:0;background:#f4f6f8;color:#1c2530;font:14px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:1080px;margin:0 auto;padding:32px 24px 80px}
h1{font-size:24px;margin:0 0 4px;letter-spacing:-.3px}
.sub{color:#61707f;font-size:13px;margin-bottom:24px}
.card{background:#fff;border:1px solid #dfe5ea;border-radius:10px;padding:20px;margin-bottom:18px}
h2{font-size:15px;margin:0 0 14px;text-transform:uppercase;letter-spacing:.7px;color:#61707f}
h3{font-size:14px;margin:20px 0 8px}
.hero{display:flex;gap:26px;align-items:center;flex-wrap:wrap}
.score{width:112px;height:112px;border-radius:50%;display:flex;flex-direction:column;align-items:center;
  justify-content:center;color:#fff;flex-shrink:0}
.score .n{font-size:34px;font-weight:700;line-height:1}
.score .l{font-size:10px;text-transform:uppercase;letter-spacing:.9px;opacity:.9}
.herotext{flex:1;min-width:260px}
.herotext .band{font-size:19px;font-weight:600;margin-bottom:4px}
.herotext p{margin:0;color:#61707f;font-size:13px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-top:18px}
.kpi{background:#f8fafb;border:1px solid #e6ebef;border-radius:8px;padding:11px 13px}
.kpi .n{font-size:20px;font-weight:600}
.kpi .l{font-size:10.5px;text-transform:uppercase;letter-spacing:.6px;color:#7a8894;margin-top:1px}
.alert{border-left:4px solid #d35400;background:#fdf3ec;border-radius:0 8px 8px 0;padding:15px 18px;margin-bottom:18px}
.alert .big{font-size:20px;font-weight:700;color:#a04000}
.alert p{margin:6px 0 0;font-size:13px;color:#6b4423}
table{width:100%;border-collapse:collapse;font-size:13px;table-layout:fixed}
td,th{word-break:break-word;overflow-wrap:anywhere}
th{text-align:left;padding:8px 10px;background:#f8fafb;border-bottom:2px solid #e6ebef;font-size:11px;
  text-transform:uppercase;letter-spacing:.5px;color:#7a8894}
td{padding:9px 10px;border-bottom:1px solid #eef2f5;vertical-align:top}
tr:last-child td{border-bottom:none}
.sev{display:inline-block;padding:1px 8px;border-radius:10px;color:#fff;font-size:10.5px;font-weight:600;white-space:nowrap}
code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px}
.loc{color:#7a8894;font-size:11.5px}
.fix{color:#3d4c5a;font-size:12.5px}
.muted{color:#7a8894}
details{margin-bottom:10px}
summary{cursor:pointer;font-weight:600;padding:7px 0;font-size:13.5px}
summary::marker{color:#9aa7b3}
.foot{color:#8a97a3;font-size:11.5px;line-height:1.8;margin-top:26px;border-top:1px solid #dfe5ea;padding-top:18px}
.foot b{color:#61707f}
.badge{display:inline-block;padding:1px 7px;border-radius:9px;font-size:10.5px;background:#eef2f5;color:#61707f}
.verify{background:#fff4d6;color:#8a6d00}
@media print{body{background:#fff}.card{break-inside:avoid;border-color:#ccc}}
</style></head><body><div class="wrap">
<h1>Xamarin to .NET MAUI &mdash; Migration Readiness</h1>
<div class="sub">$(ConvertTo-HtmlText $solName) &middot; generated $generated &middot; analyser v$script:ToolVersion, rule set $script:RuleSetDate</div>
"@

# Deadline alert
$alertMain = if ($daysToPlay -gt 0) {
    "$daysToPlay days until the Google Play deadline"
} elseif ($daysToExt -gt 0) {
    "$daysToExt days until the Google Play extension deadline"
} else { "Both Google Play deadlines have passed" }

Add-Html @"
<div class="alert">
<div class="big">$alertMain</div>
<p><b>Google Play:</b> from 31 August 2026, new apps and updates must target Android 16 (API 36); an extension is available to 1 November 2026. Xamarin.Android cannot target API 36.<br>
<b>App Store:</b> since 28 April 2026, App Store Connect requires builds made with Xcode 26 and the iOS 26 SDK. Xamarin.iOS cannot produce them.<br>
A Xamarin app is not simply unsupported &mdash; it cannot ship updates to either store.</p>
</div>
"@

# Hero
if ($nothingFound) {
    Add-Html @"
<div class="card"><h2>No projects found</h2>
<p>No <code>.csproj</code> or <code>.fsproj</code> files were found under the scanned path. In practice that
means the wrong folder was scanned, rather than a codebase with nothing to fix &mdash; so this report
deliberately shows no score and no estimate.</p>
<p class="fix">Point the tool at the folder containing your <code>.sln</code> file and run it again:<br>
<code>.\XamarinMAUIMigration.ps1 -Path C:\src\MyApp</code></p></div>
</div></body></html>
"@
    $sb.ToString() | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "  Report written to $OutputPath" -ForegroundColor Green
    Write-Host ""
    return
}

$scoreColour = if ($score -ge 70) { '#1e8449' } elseif ($score -ge 45) { '#b7950b' } elseif ($score -ge 25) { '#d35400' } else { '#c0392b' }
Add-Html @"
<div class="card"><div class="hero">
<div class="score" style="background:$scoreColour"><div class="n">$score</div><div class="l">Readiness</div></div>
<div class="herotext">
<div class="band">$band migration</div>
<p>Estimated at <b>$lowDays&ndash;$highDays developer-days</b> for the framework migration itself. This covers porting what exists; it excludes new features, redesign, QA cycles and store resubmission. The calculation is shown in full further down.</p>
</div></div>
<div class="kpis">
<div class="kpi"><div class="n" style="color:#c0392b">$($counts.Critical)</div><div class="l">Critical</div></div>
<div class="kpi"><div class="n" style="color:#d35400">$($counts.High)</div><div class="l">High</div></div>
<div class="kpi"><div class="n" style="color:#b7950b">$($counts.Medium)</div><div class="l">Medium</div></div>
<div class="kpi"><div class="n">$($counts.Low)</div><div class="l">Low</div></div>
<div class="kpi"><div class="n">$($projects.Count)</div><div class="l">Projects</div></div>
<div class="kpi"><div class="n">$($packageResults.Count)</div><div class="l">Packages</div></div>
</div></div>
"@

# ---- Findings by severity ----
Add-Html '<div class="card"><h2>Findings</h2>'
if ($findings.Count -eq 0) {
    Add-Html '<p class="muted">No migration blockers detected. Verify that the scan covered the intended folder, and re-run with -IncludeTestProjects if test projects matter to you.</p>'
} else {
    foreach ($sev in @('Critical','High','Medium','Low')) {
        $group = @($findings | Where-Object Severity -eq $sev)
        if ($group.Count -eq 0) { continue }
        $open = if ($sev -in @('Critical','High')) { ' open' } else { '' }
        Add-Html "<details$open><summary><span class=`"sev`" style=`"background:$($sevColour[$sev])`">$sev</span> &nbsp;$($group.Count) finding(s)</summary>"
        Add-Html '<table><tr><th style="width:24%">Issue</th><th style="width:22%">Location</th><th style="width:54%">What to do</th></tr>'
        foreach ($g in ($group | Sort-Object Category, File)) {
            $loc = if ($g.Line -gt 0) { "$(ConvertTo-HtmlText $g.File)<span class=`"loc`">:$($g.Line)</span>" } else { ConvertTo-HtmlText $g.File }
            Add-Html "<tr><td><b>$(ConvertTo-HtmlText $g.Title)</b><br><span class=`"loc`">$(ConvertTo-HtmlText $g.Evidence)</span></td><td class=`"mono`">$loc</td><td class=`"fix`">$(ConvertTo-HtmlText $g.Fix)</td></tr>"
        }
        Add-Html '</table></details>'
    }
}
Add-Html '</div>'

# ---- Projects ----
Add-Html '<div class="card"><h2>Projects</h2><table><tr><th style="width:27%">Project</th><th style="width:24%">Type</th><th style="width:15%">Target</th><th style="width:34%">Path</th></tr>'
foreach ($p in ($projects | Sort-Object @{E={$_.Blocking};D=$true}, Name)) {
    $flag = if ($p.Blocking -gt 0) { ' <span class="sev" style="background:#c0392b">not auto-converted</span>' } else { '' }
    Add-Html "<tr><td><b>$(ConvertTo-HtmlText $p.Name)</b>$flag</td><td>$(ConvertTo-HtmlText $p.Kinds)</td><td class=`"mono`">$(ConvertTo-HtmlText $p.Tfm)</td><td class=`"mono loc`">$(ConvertTo-HtmlText $p.Path)</td></tr>"
}
Add-Html '</table><p class="muted" style="margin-top:12px;font-size:12.5px">Projects flagged <b>not auto-converted</b> are outside what the .NET Upgrade Assistant handles. Budget for these separately &mdash; they are the most commonly underestimated part of a Xamarin migration.</p></div>'

# ---- Packages ----
Add-Html '<div class="card"><h2>NuGet dependencies</h2><table><tr><th style="width:26%">Package</th><th style="width:11%">Version</th><th style="width:15%">Status</th><th style="width:48%">MAUI path</th></tr>'
$statusOrder = @{ 'Blocked'=0;'Replaced'=1;'Check'=2;'Renamed'=3;'Builtin'=4;'Unknown'=5;'Ok'=6 }
foreach ($p in ($packageResults | Sort-Object @{E={$statusOrder[$_.Status]}}, Id)) {
    $col = $sevColour[$p.Severity]
    $conf = if ($p.Confidence -eq 'Verify') { ' <span class="badge verify">verify</span>' } else { '' }
    $target = if ($p.Target) { ConvertTo-HtmlText $p.Target } else { '<span class="muted">&mdash;</span>' }
    $note = if ($p.Note) { "<br><span class=`"loc`">$(ConvertTo-HtmlText $p.Note)</span>" } else { '' }
    Add-Html "<tr><td class=`"mono`">$(ConvertTo-HtmlText $p.Id)</td><td class=`"mono loc`">$(ConvertTo-HtmlText $p.Version)</td><td><span class=`"sev`" style=`"background:$col`">$($p.Status)</span>$conf</td><td class=`"fix`">$target$note</td></tr>"
}
Add-Html '</table>'
Add-Html '<p class="muted" style="margin-top:12px;font-size:12.5px"><b>Unknown</b> means the package is not in this tool&rsquo;s rule set &mdash; it is not a judgement about the package. <b>Verify</b> marks entries a maintainer should confirm against current sources rather than trust outright.</p></div>'

# ---- Syncfusion mapping ----
if ($syncfusionFound.Count -gt 0) {
    Add-Html '<div class="card"><h2>Syncfusion control mapping</h2><table><tr><th>Xamarin package</th><th>Version</th><th>.NET MAUI package</th></tr>'
    foreach ($s in ($syncfusionFound | Sort-Object From -Unique)) {
        Add-Html "<tr><td class=`"mono`">$(ConvertTo-HtmlText $s.From)</td><td class=`"mono loc`">$(ConvertTo-HtmlText $s.Version)</td><td class=`"mono`">$(ConvertTo-HtmlText $s.To)</td></tr>"
    }
    Add-Html '</table><p class="muted" style="margin-top:12px;font-size:12.5px">Per-control migration guides: <a href="https://help.syncfusion.com/maui/common/migration">help.syncfusion.com/maui/common/migration</a></p></div>'
}

# ---- Effort method ----
Add-Html '<div class="card"><h2>How the estimate was calculated</h2>'
Add-Html '<p class="muted" style="font-size:12.5px;margin-top:0">Every number below is shown so you can substitute your own rates. The range applied to the total is &minus;40% to +40%, which reflects how wide real migration outcomes are.</p>'
Add-Html '<table><tr><th>Work</th><th style="width:70px">Count</th><th style="width:90px">Hours each</th><th style="width:80px">Hours</th></tr>'
foreach ($e in $effortLines) {
    Add-Html "<tr><td>$(ConvertTo-HtmlText $e.Label)</td><td class=`"mono`">$($e.Count)</td><td class=`"mono loc`">$($e.Rate)</td><td class=`"mono`">$($e.Hours)</td></tr>"
}
Add-Html "<tr><td><b>Total</b></td><td></td><td></td><td class=`"mono`"><b>$totalHours</b></td></tr>"
Add-Html "</table><p style=`"margin-top:12px`"><b>$totalHours hours</b> &rarr; $([math]::Round($totalHours/8,1)) developer-days &rarr; reported range <b>$lowDays&ndash;$highDays days</b> at &plusmn;40%.</p>"
Add-Html '<h3>What this excludes</h3><p class="fix">New features, UI redesign, QA and regression cycles, store resubmission and review, team ramp-up on MAUI, and any backend work. It also assumes the app currently builds.</p>'
Add-Html @"
<h3>And how the readiness score was calculated</h3>
<p class="fix">The score measures blocker <i>density</i>, so a large application is not penalised simply for being large:</p>
<p class="mono" style="background:#f8fafb;border:1px solid #e6ebef;border-radius:6px;padding:11px 13px;font-size:12px">
penalty = (10 &times; $($counts.Critical)) + (4 &times; $($counts.High)) + (1 &times; $($counts.Medium)) + (0.2 &times; $($counts.Low)) = <b>$penalty</b><br>
scale &nbsp;&nbsp;= 40 + (8 &times; $($projects.Count) projects) + (0.4 &times; $($csFiles.Count + $xamlFiles.Count) source files) = <b>$sizeScale</b><br>
score &nbsp;&nbsp;= 100 &times; e<sup>&minus;penalty/scale</sup> = <b>$score</b>
</p>
<p class="fix">Those constants are judgement rather than measurement. They are printed here so you can disagree with them and recompute.</p></div>
"@

# ---- Next steps ----
Add-Html @"
<div class="card"><h2>Suggested sequence</h2>
<ol style="margin:0;padding-left:20px;font-size:13.5px;line-height:1.9">
<li><b>Deal with the projects the Upgrade Assistant will not touch first.</b> UWP heads, iOS extensions and binding projects drive the timeline, and finding them late is what turns an eight-week migration into a five-month one.</li>
<li><b>Resolve blocked packages before writing any code.</b> A dependency with no MAUI path is an architectural decision, not a porting task.</li>
<li><b>Run the .NET Upgrade Assistant on the shared project and the mobile heads.</b> Expect it to handle project files and namespaces, and nothing platform-specific. Note that the official documentation is stale &mdash; it was last updated in January 2024 and still retargets to net8.0, which left support in May 2025. Retarget to a current TFM yourself.</li>
<li><b>Port renderers to handlers.</b> Take the highest-traffic screens first so you get a shippable build early.</li>
<li><b>Replace removed APIs.</b> Application.Properties deserves care: without a one-time upgrade path, existing users lose their stored data on update.</li>
<li><b>Clear the compatibility namespace.</b> Microsoft.Maui.Controls.Compatibility does not ship in .NET 11. Anything left behind here blocks that upgrade.</li>
<li><b>Ship to both stores before the deadlines.</b> Store review is not instant; work back from 31 August, or 1 November if you take the Play extension.</li>
</ol></div>
"@

# ---- Errors ----
if ($scanErrors.Count) {
    Add-Html '<div class="card"><h2>Files that could not be read</h2><ul class="mono loc">'
    foreach ($e in ($scanErrors | Select-Object -First 40)) { Add-Html "<li>$(ConvertTo-HtmlText $e)</li>" }
    Add-Html '</ul></div>'
}

Add-Html @"
<div class="foot">
<b>Method and limits.</b> This is static text analysis, not compilation. It finds patterns in project files, C# and XAML; it cannot see runtime behaviour, reflection, source generators, or anything behind conditional compilation. Treat the output as a scoped starting point for planning, not a guarantee of completeness. Findings are evidence-linked so every one can be checked by opening the file at the stated line.<br>
<b>Privacy.</b> Nothing is uploaded and nothing leaves this machine. The tool makes no network calls. The HTML report contains file paths and short code excerpts from your solution &mdash; review it before sharing outside your team.<br>
<b>Rule set.</b> $script:RuleSetDate. Package guidance changes as community ports appear and are abandoned; entries marked <span class="badge verify">verify</span> should be confirmed against current sources.<br>
<b>Licence.</b> MIT. Corrections and additional package rules are welcome at <a href="https://github.com/syncfusion/Xamarin-MAUI-Migration-Advisor">github.com/syncfusion/xamarin-migration-advisor</a>.<br>
<b>About.</b> Built by Syncfusion, which actively contributes to the <a href="https://github.com/dotnet/maui">.NET MAUI open-source project</a> &mdash; including migrating .NET MAUI&rsquo;s own UI test suite from Xamarin.UITest to Appium. <a href="https://devblogs.microsoft.com/dotnet/dotnet-maui-welcomes-syncfusion-open-source-contributions/">Microsoft .NET Blog</a>.
</div>
</div></body></html>
"@

$sb.ToString() | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "  Report written to $OutputPath" -ForegroundColor Green
Write-Host ""
