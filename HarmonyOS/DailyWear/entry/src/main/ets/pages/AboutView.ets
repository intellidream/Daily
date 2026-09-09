import { WatchSessionManager } from '../utils/WatchSessionManager';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct AboutView {
  @Prop @Watch('onRefresh') refreshTrigger: number = 0;
  @State syncText: string = 'synced';
  @State syncColor: string = '#FFCC00';

  async aboutToAppear() {
    await this.updateSyncStatus();
  }

  onRefresh(): void {
    this.updateSyncStatus();
  }

  private async updateSyncStatus(): Promise<void> {
    const timeMs = await WatchSessionManager.getInstance().getLastHealthSyncTime();
    if (timeMs > 0) {
      const d = new Date(timeMs);
      const today = new Date();
      const isToday = d.getFullYear() === today.getFullYear() &&
        d.getMonth() === today.getMonth() &&
        d.getDate() === today.getDate();
      const h = d.getHours().toString().padStart(2, '0');
      const m = d.getMinutes().toString().padStart(2, '0');
      const timeStr = `${h}:${m}`;
      if (isToday) {
        this.syncText = `synced at ${timeStr}`;
      } else {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        this.syncText = `synced at ${timeStr}, ${d.getDate()} ${months[d.getMonth()]}`;
      }
      this.syncColor = '#FFCC00';
    } else {
      this.syncText = 'not synced';
      this.syncColor = '#FF3B30';
    }
  }

  private triggerHaptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
    } catch (_e) {}
  }

  private showUnpairConfirm(): void {
    this.triggerHaptic();
    this.getUIContext().showAlertDialog({
      title: 'Unpair Watch?',
      message: 'This will disconnect this watch from your account.',
      primaryButton: {
        value: 'Cancel',
        fontColor: '#888888',
        action: () => {}
      },
      secondaryButton: {
        value: 'Unpair',
        fontColor: '#FF3B30',
        action: () => {
          this.triggerHaptic();
          WatchSessionManager.getInstance().clearSession();
          AppStorage.setOrCreate('PairingSuccess', false);
        }
      }
    });
  }

  build() {
    Scroll() {
      Column() {
        // Orbit Logo
        Image($r('app.media.orbit_logo'))
          .width(46)
          .height(46)
          .borderRadius(11)

        Text('DayOne Orbit')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: 4 })

        Text('v1.0')
          .fontSize(11)
          .fontColor('#888888')
          .margin({ top: 2 })

        // Divider
        Row()
          .width('85%')
          .height(1)
          .backgroundColor('rgba(255, 255, 255, 0.15)')
          .margin({ top: 10, bottom: 8 })

        // Status & Health Rows
        Column() {
          Row() {
            Text('Status:')
              .fontSize(11)
              .fontColor('#888888')
            Text('Connected')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#4CAF50')
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          Row() {
            Text('Health:')
              .fontSize(11)
              .fontColor('#888888')
            Text(this.syncText)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.syncColor)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 4 })
        }
        .width('85%')

        // Divider
        Row()
          .width('85%')
          .height(1)
          .backgroundColor('rgba(255, 255, 255, 0.15)')
          .margin({ top: 8, bottom: 12 })

        // Unpair Button
        Row() {
          Text('Unpair Watch')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF3B30')
        }
        .width('85%')
        .height(36)
        .borderRadius(8)
        .backgroundColor('rgba(255, 59, 48, 0.2)')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showUnpairConfirm();
        })
      }
      .width('100%')
      .padding({ top: 12, bottom: 24 })
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
