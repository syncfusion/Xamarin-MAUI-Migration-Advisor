using ContosoExpenses.Droid.Renderers;
using Xamarin.Forms;
using Xamarin.Forms.Platform.Android;

[assembly: ResolutionGroupName("Contoso")]
[assembly: ExportEffect(typeof(ShadowEffect), "ShadowEffect")]
namespace ContosoExpenses.Droid.Renderers
{
    public class ShadowEffect : PlatformEffect
    {
        protected override void OnAttached() { }
        protected override void OnDetached() { }
    }
}
