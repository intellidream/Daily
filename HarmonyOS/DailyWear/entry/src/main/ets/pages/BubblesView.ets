import { SupabaseClient } from '../utils/SupabaseClient';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { LogType } from '../models/HabitLog';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct BubblesView {
  @State waterCount: number = 0;
  
  async aboutToAppear() {
    this.waterCount = await SupabaseClient.getInstance().fetchTodayCount('water');
  }

  private async addWater() {
    this.waterCount += 300; // Assuming 1 drink is 300 ml
    const now = new Date().toISOString();
    
    let payload: Record<string, Object | null> = {};
    payload['user_id'] = SupabaseClient.getInstance().getUserId();
    payload['habit_type'] = 'water';
    payload['value'] = 300;
    payload['unit'] = 'ml';
    payload['logged_at'] = now;
    payload['metadata'] = JSON.stringify({ drink: 'Large Water' });
    
    const success = await SupabaseClient.getInstance().insertLog('habits_logs', payload);

    if (!success) {
      hilog.warn(0x0000, 'BubblesView', 'Offline mode - queuing log');
      await OfflineSyncManager.getInstance().enqueueLog(LogType.Bubbles, now);
    }
  }

  build() {
    Column() {
      Text('Water Today')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor('#B3E5FC') // Light blue
        .margin({ top: 40 })
      
      Text(`${this.waterCount}`)
        .fontSize(64)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ top: 5, bottom: 25 })
        
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Column() {
          Image($r('app.media.startIcon')) // Optional: replace with a droplet icon later
            .width(36).height(36).margin({bottom: 4})
          Text('+300 ml')
            .fontColor(Color.White)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
        }.justifyContent(FlexAlign.Center)
      }
      .width(140)
      .height(140)
      .backgroundColor('#0277BD') // Deep Blue
      .shadow({ radius: 20, color: 'rgba(2, 119, 189, 0.4)', offsetY: 5 })
      .onClick(() => {
        // Trigger haptic feedback here if available in the future
        this.addWater();
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#011520', 0.0], ['#000000', 1.0]] // Subtle blue-black background gradient
    })
  }
}
