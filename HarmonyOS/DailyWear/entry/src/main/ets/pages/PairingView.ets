import { WatchSessionManager } from '../utils/WatchSessionManager';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct PairingView {
  @State code: string = '------';
  @State errorMessage: string = '';
  @State isGenerating: boolean = true;

  async aboutToAppear() {
    await this.generateCode();
  }

  aboutToDisappear() {
    WatchSessionManager.getInstance().stopPolling();
  }

  private triggerHaptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
    } catch (_e) {}
  }

  private async generateCode() {
    this.isGenerating = true;
    this.errorMessage = '';
    try {
      this.code = await WatchSessionManager.getInstance().generatePairingCode();
      if (this.code === '' || this.code === '------') {
        this.errorMessage = 'Failed to generate pairing code. Check your connection.';
      }
    } catch (_e) {
      this.errorMessage = 'Network error. Please try again.';
    }
    this.isGenerating = false;
  }

  build() {
    Scroll() {
      Column() {
        Text('DayOne Orbit')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#00FFFF')
          .margin({ top: 12 })

        Text('Pairing PIN')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#888888')
          .margin({ top: 2 })

        if (this.errorMessage) {
          Text(this.errorMessage)
            .fontSize(10)
            .fontColor('#FF3B30')
            .textAlign(TextAlign.Center)
            .margin({ top: 10, left: 16, right: 16 })

          Row() {
            Text('Retry')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#00FFFF')
          }
          .width(80)
          .height(30)
          .borderRadius(15)
          .backgroundColor('rgba(0, 255, 255, 0.2)')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 10 })
          .onClick(() => {
            this.triggerHaptic();
            this.generateCode();
          })
        } else if (this.isGenerating) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#00FFFF')
            .margin({ top: 24 })
        } else {
          // Large Green OTP PIN
          Text(this.code)
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4CAF50')
            .letterSpacing(4)
            .fontFamily('monospace')
            .margin({ top: 8 })

          Text('Enter this PIN in DayOne to link.')
            .fontSize(10)
            .fontColor('#AAAAAA')
            .textAlign(TextAlign.Center)
            .margin({ top: 4, left: 16, right: 16 })

          Row() {
            LoadingProgress()
              .width(14)
              .height(14)
              .color('#888888')

            Text('Waiting for authorization...')
              .fontSize(9)
              .fontColor('#888888')
              .margin({ left: 4 })
          }
          .margin({ top: 8 })

          Row() {
            Text('New PIN')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#00FFFF')
          }
          .width(80)
          .height(28)
          .borderRadius(8)
          .backgroundColor('rgba(255, 255, 255, 0.1)')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 8, bottom: 16 })
          .onClick(() => {
            this.triggerHaptic();
            this.generateCode();
          })
        }
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
