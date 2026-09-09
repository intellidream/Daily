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

  private formatTime(isoString: string): string {
    const d = new Date(isoString);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  private showDeleteConfirm(log: SupabaseHabitLog): void {
    this.triggerHaptic();
    const drinkName = this.getDrinkType(log);
    this.getUIContext().showAlertDialog({
      title: 'Delete Log?',
      message: `Delete ${log.value} ml ${drinkName} entry?`,
      primaryButton: {
        value: 'Cancel',
        fontColor: '#888888',
        action: () => {}
      },
      secondaryButton: {
        value: 'Delete',
        fontColor: '#FF3B30',
        action: async () => {
          this.triggerHaptic();
          this.dayLogs = this.dayLogs.filter(l => l.id !== log.id);
          this.computeTotals();
          await SupabaseClient.getInstance().softDeleteLog(log.id);
        }
      }
    });
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
          // Circular Progress Ring
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

        // Breakdown Summary Row
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
        }
        .width('90%')
        .height(28)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2, bottom: 6 })

        // In-Flow Logs List
        if (this.dayLogs.length > 0) {
          Row() {
            Text(`Logs (${this.dayLogs.length})`)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#888888')
          }
          .width('88%')
          .margin({ top: 2, bottom: 4 })
          .justifyContent(FlexAlign.Start)

          ForEach(this.dayLogs, (log: SupabaseHabitLog) => {
            Row() {
              Text(this.getDrinkType(log).includes('Coffee') ? '☕' : '💧')
                .fontSize(14)
                .margin({ right: 6 })

              Column() {
                Text(`${log.value} ml ${this.getDrinkType(log).includes('Coffee') ? 'Coffee' : (this.getDrinkType(log) === 'Small Water' ? 'Small' : 'Large')}`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')

                Text(this.formatTime(log.logged_at))
                  .fontSize(9)
                  .fontColor('#888888')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('✕')
                .fontSize(12)
                .fontColor('#FF5555')
                .padding({ left: 8, right: 4 })
            }
            .width('88%')
            .padding({ top: 6, bottom: 6, left: 10, right: 10 })
            .borderRadius(8)
            .backgroundColor('rgba(255, 255, 255, 0.08)')
            .margin({ bottom: 4 })
            .onClick(() => {
              this.showDeleteConfirm(log);
            })
          }, (log: SupabaseHabitLog) => log.id)
        }
      }
      .width('100%')
      .padding({ bottom: 24 })
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
