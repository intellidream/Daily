import { WatchSessionManager } from '../utils/WatchSessionManager';

@Component
export struct PairingView {
  @State code: string = '------';

  async aboutToAppear() {
    this.code = await WatchSessionManager.getInstance().generatePairingCode();
  }

  aboutToDisappear() {
    WatchSessionManager.getInstance().stopPolling();
  }

  build() {
    Column() {
      Text('Pair Watch')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 30 })

      Text('Enter this code in the Daily app on your phone:')
        .fontSize(14)
        .fontColor('#AAAAAA')
        .textAlign(TextAlign.Center)
        .margin({ top: 10, bottom: 20, left: 20, right: 20 })

      Text(this.code)
        .fontSize(48)
        .fontWeight(FontWeight.Bolder)
        .fontColor('#0277BD')
        .letterSpacing(5)

      LoadingProgress()
        .width(40)
        .height(40)
        .color('#0277BD')
        .margin({ top: 20 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#000000')
  }
}
