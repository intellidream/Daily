# Daily App - Deployment Protocol

## 1. Version Increment (Mandatory)
Before **EVERY** deployment, you must increment the version number in TWO places:

1.  **`Daily.csproj`**:
    ```xml
    <ApplicationDisplayVersion>1.1.X</ApplicationDisplayVersion>
    <ApplicationVersion>X</ApplicationVersion>
    ```
    *Increment `X` by 1.*

2.  **`Components/Layout/MainLayout.razor`**:
    *The app retrieves the version dynamically, but ensure the display logic matches the major/minor version if hardcoded anywhere.*
    *(Currently dynamic: `@($"V{AppInfo.Version.Major}.{AppInfo.Version.Minor}.{AppInfo.Version.Build}")` so no manual change needed in Razor unless the major/minor changes).*

## 2. Clean Build Protocol
Always perform a clean build to avoid stale assets or caching issues.

```bash
cd /Users/mihai/Source/Daily
rm -rf bin obj
dotnet clean
dotnet build -c Debug
```

## 3. Deployment Targets

### A. iOS (Physical - Schmitz)
Deploy to the physical iPhone "Schmitz".

```bash
# Build
dotnet build Daily.csproj -f net10.0-ios -r ios-arm64
# Install & Launch (More reliable than dotnet run)
xcrun devicectl device install app --device 62990754-1EE9-5A95-A45E-F4A69DA6E591 bin/Debug/net10.0-ios/ios-arm64/Daily.app
xcrun devicectl device process launch --device 62990754-1EE9-5A95-A45E-F4A69DA6E591 com.intellidream.daily
```

### B. Android (Physical - Wireless)
**CRITICAL**: JAVA 17 Requirement.
The system default `java_home` often hides JDK 17. Use the Xamarin-bundled version.

1.  **Set Java Home**:
    ```bash
    export JAVA_HOME="/Users/mihai/Library/Developer/Xamarin/jdk-17"
    ```
2.  **Deploy**:
    ```bash
    dotnet build Daily.csproj -f net10.0-android -t:Run
    ```
    *Note: If `adb` issues occur, restart the server: `adb kill-server && adb start-server`.*

### C. Mac Catalyst (Local)
Deploy to the local machine.

```bash
dotnet build -t:Run -f net10.0-maccatalyst
```
