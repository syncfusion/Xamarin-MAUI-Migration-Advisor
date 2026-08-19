using Xamarin.Forms;
using Xamarin.Forms.Platform.Android;
[assembly: ExportRenderer(typeof(Label), typeof(CleanApp.Droid.BadgeRenderer))]
namespace CleanApp.Droid { public class BadgeRenderer : LabelRenderer { } }
