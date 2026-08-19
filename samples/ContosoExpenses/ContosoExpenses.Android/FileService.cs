using ContosoExpenses.Services;
using Xamarin.Forms;

[assembly: Dependency(typeof(ContosoExpenses.Droid.FileService))]
namespace ContosoExpenses.Droid
{
    public class FileService : IFileService { public string GetPath() => "/data"; }
}
