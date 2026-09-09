import { SupabaseClient } from '../utils/SupabaseClient';
import { WeekBucket } from '../models/HabitLog';
import { TemporalNavHeader } from './TemporalNavHeader';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct Smokes7DaysView {
  @Prop @Watch('onRefresh') refreshTrigger: number = 0;
  @State weekOffset: number = 0;
  @State baseline: number = 20;
  @State buckets: WeekBucket[] = [];
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
      this.baseline = await client.fetchSmokesBaseline();
      this.buckets = await client.fetchWeekBuckets('smokes', this.weekOffset);
    } catch (e) {
      hilog.error(0x0000, 'Smokes7DaysView', `fetchData error: ${JSON.stringify(e)}`);
    }
    this.isLoading = false;
  }

  private getWeekTitle(): string {
    if (this.weekOffset === 0) return 'This Week';
    if (this.weekOffset === -1) return 'Last Week';

    const now = new Date();
    const dayOfWeek = now.getDay();
    const daysFromMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const mon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - daysFromMonday + this.weekOffset * 7);
    const sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6);

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${mon.getDate()} ${months[mon.getMonth()]} - ${sun.getDate()} ${months[sun.getMonth()]}`;
  }

  private getMaxVal(): number {
    let max = this.baseline;
    for (const b of this.buckets) {
      if (b.total > max) max = b.total;
    }
    return Math.max(max, 1);
  }

  private getWeeklyAverage(): string {
    if (this.buckets.length === 0) return '0';
    let sum = 0;
    for (const b of this.buckets) sum += b.total;

    let avg = 0;
    if (this.weekOffset === 0) {
      const now = new Date();
      const dow = now.getDay();
      const elapsed = dow === 0 ? 7 : dow;
      avg = sum / Math.max(elapsed, 1);
    } else {
      avg = sum / 7;
    }

    if (avg >= 10) return Math.round(avg).toString();
    return avg.toFixed(1);
  }

  build() {
    Scroll() {
      Column() {
        // Title
        Row() {
          Text('🔥')
            .fontSize(15)
          Text('7 Days')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ left: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 0, bottom: 2 })

        // Temporal Nav Header (Weeks)
        TemporalNavHeader({
          title: this.getWeekTitle(),
          canGoForward: this.weekOffset < 0,
          accentColor: '#FF5555',
          onPrevious: () => {
            this.weekOffset -= 1;
            this.fetchData();
          },
          onNext: () => {
            if (this.weekOffset < 0) {
              this.weekOffset += 1;
              this.fetchData();
            }
          }
        })

        // 7-Day Histogram
        if (this.isLoading && this.buckets.length === 0) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#FF5555')
            .margin({ top: 20, bottom: 20 })
        } else {
          Stack({ alignContent: Alignment.Bottom }) {
            // Target Baseline Line (Dashed / red line)
            Row()
              .width('100%')
              .height(1)
              .backgroundColor('#FF5252')
              .opacity(0.4)
              .position({
                y: `${Math.max(0, 100 - (this.baseline / this.getMaxVal()) * 100)}%`
              })

            // 7 Days Columns
            Row() {
              ForEach(this.buckets, (item: WeekBucket) => {
                Column() {
                  // Stacked Bar Container
                  Column() {
                    if (item.total > 0) {
                      // Stacked Heat (Blue) on top
                      if (item.heat > 0) {
                        Column()
                          .width(13)
                          .height(`${(item.heat / Math.max(item.total, 1)) * 100}%`)
                          .backgroundColor('#1E90FF')
                          .borderRadius({ topLeft: 3, topRight: 3 })
                      }
                      // Cig (Red) below
                      if (item.cig > 0) {
                        Column()
                          .width(13)
                          .height(`${(item.cig / Math.max(item.total, 1)) * 100}%`)
                          .backgroundColor(item.isToday ? '#FF3B30' : '#D84315')
                          .borderRadius({
                            bottomLeft: 3,
                            bottomRight: 3,
                            topLeft: item.heat === 0 ? 3 : 0,
                            topRight: item.heat === 0 ? 3 : 0
                          })
                      }
                    } else {
                      Column()
                        .width(13)
                        .height(3)
                        .backgroundColor('#222222')
                        .borderRadius(2)
                    }
                  }
                  .width(13)
                  .height(`${Math.max(3, (item.total / this.getMaxVal()) * 100)}%`)
                  .justifyContent(FlexAlign.End)

                  // Day Label
                  Text(item.dayLabel)
                    .fontSize(9)
                    .fontWeight(item.isToday ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(item.isToday ? '#FF5555' : '#888888')
                    .margin({ top: 3 })
                }
                .justifyContent(FlexAlign.End)
                .alignItems(HorizontalAlign.Center)
                .layoutWeight(1)
              }, (item: WeekBucket) => item.date)
            }
            .width('100%')
            .height('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .width('82%')
          .height(84)
          .margin({ top: 6, bottom: 6 })
        }

        // Summary Row: Avg & Base
        Row() {
          Text('🔥')
            .fontSize(11)
          Text(`Avg: ${this.getWeeklyAverage()}/d`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ left: 3 })

          Text('  •  ')
            .fontSize(10)
            .fontColor('#666666')

          Text(`Base: ${this.baseline}`)
            .fontSize(10)
            .fontColor('#888888')
        }
        .width('82%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 6, bottom: 16 })
      }
      .width('100%')
      .padding({ top: 22, bottom: 36 })
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
