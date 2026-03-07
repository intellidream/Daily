let dailyCardStorage = new LocalStorage();

@Entry(dailyCardStorage)
@Component
struct DailyCard {
  @LocalStorageProp('waterTotal') waterTotal: number = 0;
  @LocalStorageProp('smokesTotal') smokesTotal: number = 0;
  @LocalStorageProp('smokesBaseline') smokesBaseline: number = 20;
  @LocalStorageProp('isLoggedIn') isLoggedIn: boolean = false;

  build() {
    Column() {
      if (!this.isLoggedIn) {
        Text('Open Daily')
          .fontSize(12)
          .fontColor('#AAAAAA')
          .textAlign(TextAlign.Center)
      } else {
        Row() {
          Text('💧')
            .fontSize(16)
          Text(`${this.waterTotal}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#00FFFF')
            .margin({ left: 2 })
          Text('ml')
            .fontSize(10)
            .fontColor('#00FFFF')
            .margin({ left: 1 })
        }
        .justifyContent(FlexAlign.Center)

        Row() {
          Text('🔥')
            .fontSize(16)
          Text(`${this.smokesTotal}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getSmokesColor())
            .margin({ left: 2 })
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#000000')
    .borderRadius(12)
  }

  private getSmokesColor(): string {
    if (this.smokesTotal === 0) return '#4CAF50';
    const ratio = this.smokesTotal / Math.max(this.smokesBaseline, 1);
    if (ratio >= 1.0) return '#F44336';
    if (ratio >= 0.5) return '#FF9800';
    return '#FFEB3B';
  }
}
