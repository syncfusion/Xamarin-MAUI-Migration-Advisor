using ContosoExpenses.iOS.Renderers;
using Xamarin.Forms;
using Xamarin.Forms.Platform.iOS;

[assembly: ExportRenderer(typeof(Xamarin.Forms.ContentPage), typeof(CustomPageRenderer))]
namespace ContosoExpenses.iOS.Renderers
{
    public class CustomPageRenderer : PageRenderer
    {
        public override void ViewDidLoad() { base.ViewDidLoad(); }
    }
}
