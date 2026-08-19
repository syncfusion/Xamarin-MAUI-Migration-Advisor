using System;
using Xamarin.Forms;

namespace ContosoExpenses
{
    public partial class App : Application
    {
        public App()
        {
            InitializeComponent();
            if (Device.RuntimePlatform == Device.iOS) { /* ... */ }
            Device.BeginInvokeOnMainThread(() => MainPage = new AppShell());
            Device.StartTimer(TimeSpan.FromMinutes(5), OnTick);

            if (Application.Current.Properties.ContainsKey("lastUser"))
            {
                var user = Application.Current.Properties["lastUser"];
            }
            MessagingCenter.Subscribe<object>(this, "refresh", _ => Reload());
        }
        bool OnTick() => true;
        void Reload() { }
    }
}
