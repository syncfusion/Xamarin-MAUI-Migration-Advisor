using ContosoExpenses.iOS.Renderers;
using Xamarin.Forms;
using Xamarin.Forms.Platform.iOS;

[assembly: ExportRenderer(typeof(Xamarin.Forms.Button), typeof(RoundedButtonRenderer))]
namespace ContosoExpenses.iOS.Renderers
{
    public class RoundedButtonRenderer : ButtonRenderer
    {
        protected override void OnElementChanged(ElementChangedEventArgs<Button> e) { base.OnElementChanged(e); }
    }
}
