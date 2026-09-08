import { SupabaseClient } from '../utils/SupabaseClient';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { LogType, SupabaseHabitLog } from '../models/HabitLog';
import { TemporalNavHeader } from './TemporalNavHeader';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct BubblesView {
  @Prop @Watch('onRefresh') refreshTrigger: number = 0;
  @State dayOffset: number = 0;
  @State waterTotal: number = 0;
  @State coffeeTotal: number = 0;
  @State waterGoal: number = 2000;
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
        this.waterGoal = await client.fetchWaterGoal();
      }
      const logs = await client.fetchDayLogs('water', this.dayOffset);
      this.dayLogs = logs;
      this.computeTotals();
    } catch (e) {
      hilog.error(0x0000, 'BubblesView', `fetchData error: ${JSON.stringify(e)}`);
    }
    this.isLoading = false;
  }

  private computeTotals() {
    let water = 0;
    let coffee = 0;
    for (const log of this.dayLogs) {
      const drinkType = this.getDrinkType(log);
      if (drinkType.includes('Coffee')) {
        coffee += log.value;
      } else {
        water += log.value;
      }
    }
    this.waterTotal = water;
    this.coffeeTotal = coffee;
  }

  private getDrinkType(log: SupabaseHabitLog): string {
    if (log.metadata) {
      try {
        const meta: Record<string, string> = JSON.parse(
          typeof log.metadata === 'string' ? log.metadata : JSON.stringify(log.metadata)
        );
        return meta['drink'] || 'Water';
      } catch (_e) {}
    }
    return 'Water';
  }

  private async logWater(amount: number, drinkName: string) {
    this.triggerHaptic();

    // Optimistic UI
    if (drinkName.includes('Coffee')) {
      this.coffeeTotal += amount;
    } else {
      this.waterTotal += amount;
    }

    // Target date calculation based on dayOffset
    const targetDate = new Date();
    if (this.dayOffset !== 0) {
      targetDate.setDate(targetDate.getDate() + this.dayOffset);
    }
    const loggedAt = targetDate.toISOString();

    let payload: Record<string, Object | null> = {};
    payload['user_id'] = SupabaseClient.getInstance().getUserId();
    payload['habit_type'] = 'water';
    payload['value'] = amount;
    payload['unit'] = 'ml';
    payload['logged_at'] = loggedAt;
    payload['metadata'] = JSON.stringify({ drink: drinkName });

    const success = await SupabaseClient.getInstance().insertLog('habits_logs', payload);

    if (success) {
      await this.fetchData();
    } else {
      hilog.warn(0x0000, 'BubblesView', 'Offline mode - queuing log');
      await OfflineSyncManager.getInstance().enqueueLog(LogType.Bubbles, loggedAt);
    }
  }

  private getWaterProgress(): number {
    return Math.min(this.waterTotal / Math.max(this.waterGoal, 1), 1.0);
  }

  private getCoffeeProgress(): number {
    return Math.min(this.coffeeTotal / Math.max(this.waterGoal, 1), 1.0);
  }

  build() {
    Scroll() {
      Column() {
        // Header
        Row() {
          Text('💧')
            .fontSize(15)
          Text('Bubbles')
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
          accentColor: '#00FFFF',
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

        // Progress Ring & Quick Add Buttons Row
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

            // Water progress arc (cyan)
            Circle()
              .width(86)
              .height(86)
              .fill(Color.Transparent)
              .stroke('#00FFFF')
              .strokeWidth(9)
              .strokeDashArray([
                this.getWaterProgress() * 270,
                270
              ])
              .strokeLineCap(LineCapStyle.Round)
              .rotate({ angle: -90 })

            // Coffee arc (orange) — stacked after water
            if (this.coffeeTotal > 0) {
              Circle()
                .width(86)
                .height(86)
                .fill(Color.Transparent)
                .stroke('#FFA500')
                .strokeWidth(9)
                .strokeDashArray([
                  this.getCoffeeProgress() * 270,
                  270 - this.getCoffeeProgress() * 270
                ])
                .strokeLineCap(LineCapStyle.Round)
                .rotate({ angle: -90 + this.getWaterProgress() * 360 })
            }

            // Center text
            Column() {
              Text(`${this.waterTotal + this.coffeeTotal}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text(`/ ${this.waterGoal}`)
                .fontSize(10)
                .fontColor('#888888')
            }
          }
          .width(86)
          .height(86)
          .onClick(() => {
            this.triggerHaptic();
            this.onOpenLogs('water', this.getFormattedDateTitle(), this.dayLogs);
          })

          // 3 Quick Add Buttons (💧 300, 💧 150, ☕ 100)
          Column() {
            // 💧 300
            Row() {
              Text('💧 300')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
            }
            .width(68)
            .height(26)
            .borderRadius(13)
            .backgroundColor('#222222')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.logWater(300, 'Large Water'); })

            // 💧 150
            Row() {
              Text('💧 150')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
            }
            .width(68)
            .height(26)
            .borderRadius(13)
            .backgroundColor('#222222')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })
            .onClick(() => { this.logWater(150, 'Small Water'); })

            // ☕ 100
            Row() {
              Text('☕ 100')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
            }
            .width(68)
            .height(26)
            .borderRadius(13)
            .backgroundColor('#222222')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })
            .onClick(() => { this.logWater(100, 'Coffee'); })
          }
          .alignItems(HorizontalAlign.Center)
        }
        .width('92%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 4, bottom: 6 })

        // Breakdown Summary Row with chevron (Tapping opens Logs)
        Row() {
          Text('💧')
            .fontSize(11)
          Text(`${this.waterTotal} ml`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ left: 2 })

          Text('  •  ')
            .fontSize(11)
            .fontColor('#888888')

          Text('☕')
            .fontSize(11)
          Text(`${this.coffeeTotal} ml`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ left: 2 })

          Text('›')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#00FFFF')
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
          this.onOpenLogs('water', this.getFormattedDateTitle(), this.dayLogs);
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
