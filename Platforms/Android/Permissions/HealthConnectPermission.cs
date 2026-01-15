using static Microsoft.Maui.ApplicationModel.Permissions;

namespace Daily.Platforms.Android.Permissions
{
    public class HealthConnectPermission : BasePlatformPermission
    {
        public override (string androidPermission, bool isRuntime)[] RequiredPermissions =>
            new (string, bool)[]
            {
                ("android.permission.health.READ_STEPS", true),
                ("android.permission.health.READ_HEART_RATE", true),
                ("android.permission.health.READ_SLEEP", true),
                ("android.permission.health.READ_TOTAL_CALORIES_BURNED", true)
            };
    }
}
