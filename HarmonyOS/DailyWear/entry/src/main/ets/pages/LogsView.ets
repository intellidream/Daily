import { SupabaseHabitLog } from '../models/HabitLog';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct LogsView {
  @Prop habitType: string = 'water';
  @Prop dateTitle: string = 'Today';
  @Prop logs: SupabaseHabitLog[] = [];
  onDelete: (logId: string) => void = () => {};
  onClose: () => void = () => {};

  private triggerHaptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
    } catch (_e) {}
  }

  private formatTime(isoString: string): string {
    const d = new Date(isoString);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
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

  private showDeleteConfirm(logId: string): void {
    this.triggerHaptic();
    this.getUIContext().showAlertDialog({
      title: 'Delete Log?',
      message: 'This will permanently remove this entry.',
      buttonDirection: DialogButtonDirection.VERTICAL,
      buttons: [
        {
          value: 'Delete',
          fontColor: '#FF3B30',
          action: () => {
            this.triggerHaptic();
            this.onDelete(logId);
          }
        },
        {
          value: 'Cancel',
          fontColor: '#888888',
          action: () => {}
        }
      ]
    });
  }

  build() {
    Column() {
      // Header
      Row() {
        Row() {
          Text('◀')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor('#222222')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.triggerHaptic();
          this.onClose();
        })

        Column() {
          Text(this.habitType === 'water' ? '💧 Water Logs' : '🔥 Smoke Logs')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.habitType === 'water' ? '#00FFFF' : '#FF5555')

          Text(`${this.logs.length} entries • ${this.dateTitle}`)
            .fontSize(10)
            .fontColor('#888888')
        }
        .margin({ left: 8 })
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('84%')
      .margin({ top: 22, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      // Logs List
      if (this.logs.length === 0) {
        Column() {
          Text('No logs recorded for this day.')
            .fontSize(11)
            .fontColor('#666666')
            .textAlign(TextAlign.Center)
            .margin({ top: 40 })
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Scroll() {
          Column() {
            ForEach(this.logs, (log: SupabaseHabitLog) => {
              Row() {
                // Emoji & Details
                Row() {
                  if (this.habitType === 'water') {
                    Text(this.getDrinkType(log).includes('Coffee') ? '☕' : '💧')
                      .fontSize(16)
                      .margin({ right: 6 })

                    Column() {
                      Text(`${log.value} ml ${this.getDrinkType(log).includes('Coffee') ? 'Coffee' : (this.getDrinkType(log) === 'Small Water' ? 'Small' : 'Large')}`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#FFFFFF')

                      Text(this.formatTime(log.logged_at))
                        .fontSize(9)
                        .fontColor('#888888')
                    }
                    .alignItems(HorizontalAlign.Start)
                  } else {
                    Text(this.getSmokeType(log) === 'Heated Tobacco' ? '⚡' : '🔥')
                      .fontSize(16)
                      .margin({ right: 6 })

                    Column() {
                      Text(`1 ${this.getSmokeType(log) === 'Heated Tobacco' ? 'Heat' : 'Cig'}`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#FFFFFF')

                      Text(this.formatTime(log.logged_at))
                        .fontSize(9)
                        .fontColor('#888888')
                    }
                    .alignItems(HorizontalAlign.Start)
                  }
                }
                .alignItems(VerticalAlign.Center)
                .layoutWeight(1)

                // Delete Button
                Row() {
                  Text('🗑️')
                    .fontSize(13)
                }
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor('rgba(255, 59, 48, 0.2)')
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.showDeleteConfirm(log.id);
                })
              }
              .width('84%')
              .padding({ top: 8, bottom: 8, left: 10, right: 10 })
              .borderRadius(10)
              .backgroundColor('#1C1C1E')
              .margin({ bottom: 4 })
            }, (log: SupabaseHabitLog) => log.id)
          }
          .width('100%')
          .padding({ bottom: 36 })
          .alignItems(HorizontalAlign.Center)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .alignItems(HorizontalAlign.Center)
  }
}
