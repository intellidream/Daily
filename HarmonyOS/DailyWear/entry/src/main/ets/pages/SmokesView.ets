import { SupabaseClient } from '../utils/SupabaseClient';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { LogType } from '../models/HabitLog';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct SmokesView {
  @State smokesCount: number = 0;

  async aboutToAppear() {
    this.smokesCount = await SupabaseClient.getInstance().fetchTodayCount('smokes');
  }

  private async addSmoke() {
    this.smokesCount += 1;
    const now = new Date().toISOString();
    
    let payload: Record<string, Object | null> = {};
    payload['user_id'] = SupabaseClient.getInstance().getUserId();
    payload['habit_type'] = 'smokes';
    payload['value'] = 1;
    payload['unit'] = 'cig';
    payload['logged_at'] = now;
    payload['metadata'] = JSON.stringify({ type: 'Cigarette' });
    
    const success = await SupabaseClient.getInstance().insertLog('habits_logs', payload);

    if (!success) {
      hilog.warn(0x0000, 'SmokesView', 'Offline mode - queuing log');
      await OfflineSyncManager.getInstance().enqueueLog(LogType.Smokes, now);
    }
  }

  build() {
    Column() {
      Text('Smokes Today')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFCCBC') // Light orange
        .margin({ top: 40 })
      
      Text(`${this.smokesCount}`)
        .fontSize(64)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ top: 5, bottom: 25 })
        
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Column() {
          Text('+1 Smoke')
            .fontColor(Color.White)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
        }.justifyContent(FlexAlign.Center)
      }
      .width(140)
      .height(140)
      .backgroundColor('#D84315') // Deep Orange/Red
      .shadow({ radius: 20, color: 'rgba(216, 67, 21, 0.4)', offsetY: 5 })
      .onClick(() => {
        this.addSmoke();
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#260D05', 0.0], ['#000000', 1.0]] // Subtle reddish-black background gradient
    })
  }
}
