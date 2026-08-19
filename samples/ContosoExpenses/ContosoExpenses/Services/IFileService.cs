using Xamarin.Forms;

namespace ContosoExpenses.Services
{
    public interface IFileService { string GetPath(); }

    public static class FileHelper
    {
        public static string Path() => DependencyService.Get<IFileService>().GetPath();
        public static string Path2() => DependencyService.Resolve<IFileService>().GetPath();
    }
}
