import { SupabaseClient } from '../utils/SupabaseClient';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { LogType, SupabaseHabitLog, DailyTotal } from '../models/HabitLog';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct BubblesView {
  @Prop @Watch('onRefresh') refreshTrigger: number = 0;
  @State waterTotal: number = 0;
  @State coffeeTotal: number = 0;
  @State waterGoal: number = 2000;
  @State todayLogs: SupabaseHabitLog[] = [];
  @State weeklyTotals: DailyTotal[] = [];
  @State isLoading: boolean = true;

  async aboutToAppear() {
    await this.fetchData();
  }

  onRefresh(): void {
    this.fetchData();
  }

  private async fetchData() {
    this.isLoading = true;
    const client = SupabaseClient.getInstance();

    try {
      const logs = await client.fetchTodayLogs('water');
      const goal = await client.fetchWaterGoal();
      const weekly = await client.fetchWeeklyTotals('water');

      this.waterGoal = goal;
      this.todayLogs = logs;
      this.weeklyTotals = weekly;
      this.computeTotals();
    } catch (e) {
      hilog.error(0x0000, 'BubblesView', `fetchData error: ${JSON.stringify(e)}`);
    }
    this.isLoading = false;
  }

  private computeTotals() {
    let water = 0;
    let coffee = 0;
    for (const log of this.todayLogs) {
      const drinkType = this.getDrinkType(log);
      if (drinkType === 'Coffee') {
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
      } catch (e) {}
    }
    return 'Water';
  }

  private async logWater(amount: number, drinkName: string) {
    // Optimistic UI
    if (drinkName.includes('Coffee')) {
      this.coffeeTotal += amount;
    } else {
      this.waterTotal += amount;
    }

    // Haptic feedback
    try {
      vibrator.startVibration({ type: 'time', duration: 50 }, { id: 0, usage: 'touch' });
    } catch (e) {
      // Vibrator optional, continue if unavailable
    }

    const now = new Date().toISOString();
    let payload: Record<string, Object | null> = {};
    payload['user_id'] = SupabaseClient.getInstance().getUserId();
    payload['habit_type'] = 'water';
    payload['value'] = amount;
    payload['unit'] = 'ml';
    payload['logged_at'] = now;
    payload['metadata'] = JSON.stringify({ drink: drinkName });

    const success = await SupabaseClient.getInstance().insertLog('habits_logs', payload);

    if (success) {
      await this.fetchData();
    } else {
      hilog.warn(0x0000, 'BubblesView', 'Offline mode - queuing log');
      await OfflineSyncManager.getInstance().enqueueLog(LogType.Bubbles, now);
    }
  }

  private async deleteLog(logId: string) {
    // Optimistic: remove from local list
    this.todayLogs = this.todayLogs.filter(l => l.id !== logId);
    this.computeTotals();

    const success = await SupabaseClient.getInstance().softDeleteLog(logId);
    if (success) {
      await this.fetchData();
    }
  }

  private formatTime(isoString: string): string {
    const d = new Date(isoString);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  private getDayLabel(dateStr: string): string {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const d = new Date(dateStr + 'T12:00:00');
    return days[d.getDay()];
  }

  build() {
    Scroll() {
      Column() {
        // --- Progress Ring ---
        Stack({ alignContent: Alignment.Center }) {
          // Background track
          Circle()
            .width(90)
            .height(90)
            .fill(Color.Transparent)
            .stroke('#333333')
            .strokeWidth(6)

          // Water progress arc (cyan)
          Circle()
            .width(90)
            .height(90)
            .fill(Color.Transparent)
            .stroke('#00BCD4')
            .strokeWidth(6)
            .strokeDashArray([
              Math.min(this.waterTotal / Math.max(this.waterGoal, 1), 1.0) * 283,
              283
            ])
            .strokeLineCap(LineCapStyle.Round)
            .rotate({ angle: -90 })

          // Coffee progress arc (orange, slightly smaller)
          Circle()
            .width(76)
            .height(76)
            .fill(Color.Transparent)
            .stroke('#FF9800')
            .strokeWidth(5)
            .strokeDashArray([
              Math.min(this.coffeeTotal / Math.max(this.waterGoal * 0.25, 1), 1.0) * 239,
              239
            ])
            .strokeLineCap(LineCapStyle.Round)
            .rotate({ angle: -90 })

          // Center text
          Column() {
            Text(`${this.waterTotal + this.coffeeTotal}`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
            Text(`/ ${this.waterGoal}`)
              .fontSize(11)
              .fontColor('#888888')
          }
        }
        .width(100)
        .height(100)
        .margin({ top: 12 })

        // --- Quick Add Buttons ---
        Row() {
          // Large Water
          Column() {
            Text('💧')
              .fontSize(18)
            Text('300')
              .fontSize(11)
              .fontColor('#00BCD4')
              .fontWeight(FontWeight.Medium)
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .backgroundColor('#1A3A4A')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => { this.logWater(300, 'Large Water'); })

          // Small Water
          Column() {
            Text('💧')
              .fontSize(14)
            Text('150')
              .fontSize(11)
              .fontColor('#00BCD4')
              .fontWeight(FontWeight.Medium)
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .backgroundColor('#1A3A4A')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => { this.logWater(150, 'Small Water'); })

          // Coffee
          Column() {
            Text('☕')
              .fontSize(18)
            Text('100')
              .fontSize(11)
              .fontColor('#FF9800')
              .fontWeight(FontWeight.Medium)
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .backgroundColor('#2A1F0A')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => { this.logWater(100, 'Coffee'); })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .margin({ top: 10 })

        // --- Weekly Chart ---
        if (this.weeklyTotals.length > 0) {
          Column() {
            Text('This Week')
              .fontSize(12)
              .fontColor('#888888')
              .margin({ bottom: 6 })

            Stack({ alignContent: Alignment.Bottom }) {
              // Goal line
              Row()
                .width('100%')
                .height(1)
                .backgroundColor('#FF5252')
                .opacity(0.5)
                .position({
                  y: `${Math.max(0, 100 - (this.waterGoal / this.getMaxWeeklyValue()) * 100)}%`
                })

              Row() {
                ForEach(this.weeklyTotals, (item: DailyTotal) => {
                  Column() {
                    // Bar
                    Column()
                      .width(14)
                      .height(`${Math.min((item.total / Math.max(this.getMaxWeeklyValue(), 1)) * 100, 100)}%`)
                      .borderRadius(3)
                      .backgroundColor(item.date === this.getTodayDateStr() ? '#00BCD4' : '#0277BD')

                    // Day label
                    Text(this.getDayLabel(item.date))
                      .fontSize(8)
                      .fontColor('#666666')
                      .margin({ top: 2 })
                  }
                  .justifyContent(FlexAlign.End)
                  .alignItems(HorizontalAlign.Center)
                  .layoutWeight(1)
                }, (item: DailyTotal) => item.date)
              }
              .width('100%')
              .height('100%')
              .alignItems(VerticalAlign.Bottom)
            }
            .width('90%')
            .height(60)
          }
          .margin({ top: 12 })
          .alignItems(HorizontalAlign.Center)
        }

        // --- Today's Logs ---
        if (this.todayLogs.length > 0) {
          Column() {
            Text("Today's Logs")
              .fontSize(12)
              .fontColor('#888888')
              .margin({ bottom: 4 })

            ForEach(this.todayLogs, (log: SupabaseHabitLog) => {
              Row() {
                Text(this.getDrinkType(log).includes('Coffee') ? '☕' : '💧')
                  .fontSize(14)
                  .margin({ right: 6 })

                Column() {
                  Text(this.getDrinkType(log))
                    .fontSize(12)
                    .fontColor('#CCCCCC')
                  Text(this.formatTime(log.logged_at))
                    .fontSize(10)
                    .fontColor('#666666')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(`${log.value} ml`)
                  .fontSize(12)
                  .fontColor('#AAAAAA')
              }
              .width('90%')
              .padding({ top: 4, bottom: 4, left: 8, right: 8 })
              .borderRadius(8)
              .backgroundColor('#111111')
              .margin({ bottom: 3 })
              .gesture(
                LongPressGesture({ repeat: false, duration: 600 })
                  .onAction(() => {
                    this.showDeleteConfirm(log.id);
                  })
              )
            }, (log: SupabaseHabitLog) => log.id)
          }
          .margin({ top: 10, bottom: 20 })
          .alignItems(HorizontalAlign.Center)
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 20 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#011520', 0.0], ['#000000', 1.0]]
    })
  }

  private showDeleteConfirm(logId: string) {
    this.getUIContext().showAlertDialog({
      message: 'Delete this log?',
      primaryButton: {
        value: 'Cancel',
        action: () => {}
      },
      secondaryButton: {
        value: 'Delete',
        fontColor: '#F44336',
        action: () => {
          this.deleteLog(logId);
        }
      }
    });
  }

  private getMaxWeeklyValue(): number {
    let max = this.waterGoal;
    for (const t of this.weeklyTotals) {
      if (t.total > max) max = t.total;
    }
    return max;
  }

  private getTodayDateStr(): string {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  }
}
