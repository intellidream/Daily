import { SupabaseClient } from '../utils/SupabaseClient';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { LogType, SupabaseHabitLog, DailyTotal } from '../models/HabitLog';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct SmokesView {
  @State smokesTotal: number = 0;
  @State baseline: number = 20;
  @State todayLogs: SupabaseHabitLog[] = [];
  @State weeklyTotals: DailyTotal[] = [];
  @State isLoading: boolean = true;

  async aboutToAppear() {
    await this.fetchData();
  }

  private async fetchData() {
    this.isLoading = true;
    const client = SupabaseClient.getInstance();

    try {
      const logs = await client.fetchTodayLogs('smokes');
      const bl = await client.fetchSmokesBaseline();
      const weekly = await client.fetchWeeklyTotals('smokes');

      this.baseline = bl;
      this.todayLogs = logs;
      this.weeklyTotals = weekly;
      this.smokesTotal = 0;
      for (const log of this.todayLogs) {
        this.smokesTotal += log.value;
      }
    } catch (e) {
      hilog.error(0x0000, 'SmokesView', `fetchData error: ${JSON.stringify(e)}`);
    }
    this.isLoading = false;
  }

  private getSmokeType(log: SupabaseHabitLog): string {
    if (log.metadata) {
      try {
        const meta: Record<string, string> = JSON.parse(
          typeof log.metadata === 'string' ? log.metadata : JSON.stringify(log.metadata)
        );
        return meta['type'] || 'Cigarette';
      } catch (e) {}
    }
    return 'Cigarette';
  }

  private getSmokesColor(): string {
    if (this.smokesTotal === 0) return '#4CAF50'; // Green
    const ratio = this.smokesTotal / Math.max(this.baseline, 1);
    if (ratio >= 1.0) return '#F44336'; // Red
    if (ratio >= 0.5) return '#FF9800'; // Orange
    return '#FFEB3B'; // Yellow
  }

  private getRemainingText(): string {
    const remaining = Math.max(0, this.baseline - this.smokesTotal);
    return `${remaining}`;
  }

  private async logSmoke(smokeType: string) {
    this.smokesTotal += 1;

    // Haptic feedback
    try {
      vibrator.startVibration({ type: 'time', duration: 50 }, { id: 0, usage: 'touch' });
    } catch (e) {
      // Vibrator optional, continue if unavailable
    }

    const now = new Date().toISOString();
    let payload: Record<string, Object | null> = {};
    payload['user_id'] = SupabaseClient.getInstance().getUserId();
    payload['habit_type'] = 'smokes';
    payload['value'] = 1;
    payload['unit'] = 'cig';
    payload['logged_at'] = now;
    payload['metadata'] = JSON.stringify({ type: smokeType });

    const success = await SupabaseClient.getInstance().insertLog('habits_logs', payload);

    if (success) {
      await this.fetchData();
    } else {
      hilog.warn(0x0000, 'SmokesView', 'Offline mode - queuing log');
      await OfflineSyncManager.getInstance().enqueueLog(LogType.Smokes, now);
    }
  }

  private async deleteLog(logId: string) {
    this.todayLogs = this.todayLogs.filter(l => l.id !== logId);
    this.smokesTotal = 0;
    for (const log of this.todayLogs) {
      this.smokesTotal += log.value;
    }

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

          // Smokes progress arc (dynamic color)
          Circle()
            .width(90)
            .height(90)
            .fill(Color.Transparent)
            .stroke(this.getSmokesColor())
            .strokeWidth(6)
            .strokeDashArray([
              Math.min(this.smokesTotal / Math.max(this.baseline, 1), 1.0) * 283,
              283
            ])
            .strokeLineCap(LineCapStyle.Round)
            .rotate({ angle: -90 })

          // Center text: remaining
          Column() {
            Text(this.getRemainingText())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getSmokesColor())
            Text('left')
              .fontSize(10)
              .fontColor('#888888')
          }
        }
        .width(100)
        .height(100)
        .margin({ top: 12 })

        // --- Two Action Buttons ---
        Row() {
          // Cigarette button
          Column() {
            Text('🚬')
              .fontSize(18)
            Text('Cig')
              .fontSize(11)
              .fontColor('#F44336')
              .fontWeight(FontWeight.Medium)
          }
          .width(64)
          .height(52)
          .borderRadius(12)
          .backgroundColor('#2A1010')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => { this.logSmoke('Cigarette'); })

          // Heated Tobacco button
          Column() {
            Text('⚡')
              .fontSize(18)
            Text('Heat')
              .fontSize(11)
              .fontColor('#2196F3')
              .fontWeight(FontWeight.Medium)
          }
          .width(64)
          .height(52)
          .borderRadius(12)
          .backgroundColor('#0A1A2A')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => { this.logSmoke('Heated Tobacco'); })
        }
        .width('80%')
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
              // Baseline line
              Row()
                .width('100%')
                .height(1)
                .backgroundColor('#FF5252')
                .opacity(0.5)
                .position({
                  y: `${Math.max(0, 100 - (this.baseline / this.getMaxWeeklyValue()) * 100)}%`
                })

              Row() {
                ForEach(this.weeklyTotals, (item: DailyTotal) => {
                  Column() {
                    Column()
                      .width(14)
                      .height(`${Math.min((item.total / Math.max(this.getMaxWeeklyValue(), 1)) * 100, 100)}%`)
                      .borderRadius(3)
                      .backgroundColor(item.date === this.getTodayDateStr() ? this.getSmokesColor() : '#D84315')

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
                Text(this.getSmokeType(log) === 'Heated Tobacco' ? '⚡' : '🚬')
                  .fontSize(14)
                  .margin({ right: 6 })

                Column() {
                  Text(`1 ${this.getSmokeType(log) === 'Heated Tobacco' ? 'Heat' : 'Cig'}`)
                    .fontSize(12)
                    .fontColor('#CCCCCC')
                  Text(this.formatTime(log.logged_at))
                    .fontSize(10)
                    .fontColor('#666666')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
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
      colors: [['#260D05', 0.0], ['#000000', 1.0]]
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
    let max = this.baseline;
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
