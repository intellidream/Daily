import { WatchSessionManager } from '../utils/WatchSessionManager';

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

  private async generateCode() {
    this.isGenerating = true;
    this.errorMessage = '';
    try {
      this.code = await WatchSessionManager.getInstance().generatePairingCode();
      if (this.code === '' || this.code === '------') {
        this.errorMessage = 'Failed to generate pairing code. Check your connection.';
      }
    } catch (e) {
      this.errorMessage = 'Network error. Please try again.';
    }
    this.isGenerating = false;
  }

  build() {
    Column() {
      if (this.errorMessage) {
        // Error state
        Text('Error')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F44336')
          .margin({ top: 30 })

        Text(this.errorMessage)
          .fontSize(12)
          .fontColor('#AAAAAA')
          .textAlign(TextAlign.Center)
          .margin({ top: 10, left: 20, right: 20 })

        Button('Retry')
          .fontSize(14)
          .backgroundColor('#0277BD')
          .fontColor('#FFFFFF')
          .borderRadius(20)
          .margin({ top: 16 })
          .onClick(() => {
            this.generateCode();
          })
      } else if (this.isGenerating) {
        // Loading state
        LoadingProgress()
          .width(50)
          .height(50)
          .color('#0277BD')
          .margin({ top: 60 })
      } else {
        // Pairing code display
        Text('Pair Watch')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ top: 30 })

        Text('Enter this code in the Daily app on your phone:')
          .fontSize(13)
          .fontColor('#AAAAAA')
          .textAlign(TextAlign.Center)
          .margin({ top: 10, bottom: 16, left: 16, right: 16 })

        Text(this.code)
          .fontSize(44)
          .fontWeight(FontWeight.Bolder)
          .fontColor('#0277BD')
          .letterSpacing(5)
          .fontFamily('monospace')

        Text('Settings \u2192 Pair Watch')
          .fontSize(11)
          .fontColor('#666666')
          .margin({ top: 8 })

        LoadingProgress()
          .width(36)
          .height(36)
          .color('#0277BD')
          .margin({ top: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#000000')
  }
}
