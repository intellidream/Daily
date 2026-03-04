# HarmonyOS Watch App

This directory is intended for the Huawei Watch app (HarmonyOS/ArkTS) mirroring the WatchOS `.NET MAUI / Swift` features.

## Setup Instructions

1. Download and install **DevEco Studio** (Huawei's official IDE).
2. Open DevEco Studio, select **Create Project**.
3. Choose **Empty Ability** or the appropriate Wearable/Watch template (ArkTS).
4. For the project location, select this exact path:
   `/Users/mihai/Source/Daily/HarmonyOS` (or a subfolder like `DailyWear`).
5. After DevEco Studio scaffolds the build profile, signatures, and module configuration, we will populate `entry/src/main/ets` with the UI (Bubbles, Smokes) and Supabase connectivity layers.

## Testing on a Physical Watch

To deploy the `DailyWear` app to a real physical Huawei Watch, you must connect via IP debugging and generate a free developer signature.

### 1. Enable Debugging on the Watch
1. On the watch, go to **Settings > About**.
2. Tap the **Build Number** repeatedly until it says "Developer mode enabled".
3. Go back to **Settings > Developer options**.
4. Enable **HDC Debugging** and **Wi-Fi Debugging**.
5. Ensure the watch and your Mac are on the **exact same Wi-Fi network**.
6. Look at the IP address listed under the Wi-Fi Debugging setting (e.g., `192.168.1.50:5555`).

### 2. Connect via DevEco Studio
1. In DevEco Studio, click **Tools > Device Manager** from the top menu.
2. Go to the **IP Connect** tab.
3. Type in the watch's IP address and the `5555` port, then click the connect button.
4. An authorization prompt will instantly appear on your watch screen—**Accept it**.

### 3. Generate the Signing Configuration
HarmonyOS requires physical apps to be signed. DevEco Studio can do this automatically:
1. Navigate to **File > Project Structure...**
2. In the left panel, click on **Project > Signing Configs**.
3. Check the box for **Automatically generate signature**.
4. If you aren't already, you will be prompted to log in to your Huawei Developer account in the browser.
5. Once authenticated, DevEco Studio will hit AppGallery Connect and automatically download your debug certificate and profile.
6. Click **Apply/OK**.

### 4. Run the App
Your physical Huawei watch will now appear in the device dropdown next to the Green Play button at the top right of DevEco Studio. 

Click **Run**, and after building, the watch will launch the Daily app seamlessly using your actual Romanian UTC+2 timezone!
