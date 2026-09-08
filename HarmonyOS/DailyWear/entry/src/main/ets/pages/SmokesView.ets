import { SupabaseClient } from '../utils/SupabaseClient';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { LogType, SupabaseHabitLog } from '../models/HabitLog';
import { TemporalNavHeader } from './TemporalNavHeader';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct SmokesView {
  @Prop @Watch('onRefresh') refreshTrigger: number = 0;
  @State dayOffset: number = 0;
  @State cigTotal: number = 0;
  @State heatTotal: number = 0;
  @State smokesTotal: number = 0;
  @State baseline: number = 20;
  @State dayLogs: SupabaseHabitLog[] = [];
  @State isLoading: boolean = true;
  onOpenLogs: (habitType: string, dateTitle: string, logs: SupabaseHabitLog[]) => void = () => {};

  async aboutToAppear() {
    await this.fetchData();
  }

  onRefresh(): void {
    this.fetchData();
  }

  private triggerHaptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
    } catch (_e) {}
  }

  private getFormattedDateTitle(): string {
    if (this.dayOffset === 0) return 'Today';
    if (this.dayOffset === -1) return 'Yesterday';

    const d = new Date();
    d.setDate(d.getDate() + this.dayOffset);
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${days[d.getDay()]}, ${d.getDate()} ${months[d.getMonth()]}`;
  }

  private async fetchData() {
    this.isLoading = true;
    const client = SupabaseClient.getInstance();

    try {
      if (this.dayOffset === 0) {
        this.baseline = await client.fetchSmokesBaseline();
      }
      const logs = await client.fetchDayLogs('smokes', this.dayOffset);
      this.dayLogs = logs;
      this.computeTotals();
    } catch (e) {
      hilog.error(0x0000, 'SmokesView', `fetchData error: ${JSON.stringify(e)}`);
    }
    this.isLoading = false;
  }

  private computeTotals() {
    let cig = 0;
    let heat = 0;
    for (const log of this.dayLogs) {
      const type = this.getSmokeType(log);
      if (type === 'Heated Tobacco') {
        heat += 1;
      } else {
        cig += 1;
      }
    }
    this.cigTotal = cig;
    this.heatTotal = heat;
    this.smokesTotal = cig + heat;
  }

  private getSmokeType(log: SupabaseHabitLog): string {
    if (log.metadata) {
      try {
        const meta: Record<string, string> = JSON.parse(
          typeof log.metadata === 'string' ? log.metadata : JSON.stringify(log.metadata)
        );
        return meta['type'] || 'Cigarette';
      } catch (_e) {}
    }
    return 'Cigarette';
  }

  private getSmokesColor(): string {
    if (this.smokesTotal >= this.baseline) return '#FF3B30'; // Red
    if (this.smokesTotal >= this.baseline * 0.75) return '#FF9500'; // Orange
    return '#4CD964'; // Green
  }

  private async logSmoke(smokeType: string) {
    this.triggerHaptic();

    if (smokeType.includes('Heated')) {
      this.heatTotal += 1;
    } else {
      this.cigTotal += 1;
    }
    this.smokesTotal += 1;

    // Target date calculation based on dayOffset
    const targetDate = new Date();
    if (this.dayOffset !== 0) {
      targetDate.setDate(targetDate.getDate() + this.dayOffset);
    }
    const loggedAt = targetDate.toISOString();

    let payload: Record<string, Object | null> = {};
    payload['user_id'] = SupabaseClient.getInstance().getUserId();
    payload['habit_type'] = 'smokes';
    payload['value'] = 1;
    payload['unit'] = 'cig';
    payload['logged_at'] = loggedAt;
    payload['metadata'] = JSON.stringify({ type: smokeType });

    const success = await SupabaseClient.getInstance().insertLog('habits_logs', payload);

    if (success) {
      await this.fetchData();
    } else {
      hilog.warn(0x0000, 'SmokesView', 'Offline mode - queuing log');
      await OfflineSyncManager.getInstance().enqueueLog(LogType.Smokes, loggedAt);
    }
  }

  build() {
    Scroll() {
      Column() {
        // Header
        Row() {
          Text('🔥')
            .fontSize(15)
          Text('Smokes')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ left: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 4, bottom: 2 })

        // Temporal Navigation Header (Days)
        TemporalNavHeader({
          title: this.getFormattedDateTitle(),
          canGoForward: this.dayOffset < 0,
          accentColor: '#FF5555',
          onPrevious: () => {
            this.dayOffset -= 1;
            this.fetchData();
          },
          onNext: () => {
            if (this.dayOffset < 0) {
              this.dayOffset += 1;
              this.fetchData();
            }
          }
        })

        // Progress Ring & Action Buttons Row
        Row() {
          // Circular Progress Ring (clickable to open Logs)
          Stack({ alignContent: Alignment.Center }) {
            // Background track
            Circle()
              .width(86)
              .height(86)
              .fill(Color.Transparent)
              .stroke('#222222')
              .strokeWidth(9)

            // Progress Arc
            Circle()
              .width(86)
              .height(86)
              .fill(Color.Transparent)
              .stroke(this.getSmokesColor())
              .strokeWidth(9)
              .strokeDashArray([
                Math.min(this.smokesTotal / Math.max(this.baseline, 1), 1.0) * 270,
                270
              ])
              .strokeLineCap(LineCapStyle.Round)
              .rotate({ angle: -90 })

            // Center text
            Column() {
              Text(`${this.smokesTotal}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.smokesTotal > this.baseline ? '#FF3B30' : '#FFFFFF')
              Text(`/ ${this.baseline}`)
                .fontSize(10)
                .fontColor('#888888')
            }
          }
          .width(86)
          .height(86)
          .onClick(() => {
            this.triggerHaptic();
            this.onOpenLogs('smokes', this.getFormattedDateTitle(), this.dayLogs);
          })

          // 2 Quick Add Action Buttons (🔥 Cig, ⚡ Heat)
          Column() {
            // 🔥 Cig
            Row() {
              Text('🔥 Cig')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
            }
            .width(68)
            .height(28)
            .borderRadius(14)
            .backgroundColor('#222222')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.logSmoke('Cigarette'); })

            // ⚡ Heat
            Row() {
              Text('⚡ Heat')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
            }
            .width(68)
            .height(28)
            .borderRadius(14)
            .backgroundColor('#222222')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: 6 })
            .onClick(() => { this.logSmoke('Heated Tobacco'); })
          }
          .alignItems(HorizontalAlign.Center)
        }
        .width('92%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 4, bottom: 6 })

        // Breakdown Summary Row with chevron (Tapping opens Logs)
        Row() {
          Text('🔥')
            .fontSize(11)
          Text(`${this.cigTotal} cig`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ left: 2 })

          Text('  •  ')
            .fontSize(11)
            .fontColor('#888888')

          Text('⚡')
            .fontSize(11)
          Text(`${this.heatTotal} heat`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ left: 2 })

          Text('›')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF5555')
            .margin({ left: 4 })
        }
        .width('90%')
        .height(32)
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 4, bottom: 12 })
        .onClick(() => {
          this.triggerHaptic();
          this.onOpenLogs('smokes', this.getFormattedDateTitle(), this.dayLogs);
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
