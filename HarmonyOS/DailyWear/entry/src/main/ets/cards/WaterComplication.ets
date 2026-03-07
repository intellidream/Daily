let waterCompStorage = new LocalStorage();

@Entry(waterCompStorage)
@Component
struct WaterComplication {
  @LocalStorageProp('waterTotal') waterTotal: number = 0;
  @LocalStorageProp('isLoggedIn') isLoggedIn: boolean = false;

  build() {
    Column() {
      if (!this.isLoggedIn) {
        Text('--')
          .fontSize(14)
          .fontColor('#555555')
      } else {
        Text('💧')
          .fontSize(14)
        Text(`${this.waterTotal}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#00FFFF')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#000000')
    .borderRadius(50)
  }
}
