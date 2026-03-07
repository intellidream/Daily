let smokesCompStorage = new LocalStorage();

@Entry(smokesCompStorage)
@Component
struct SmokesComplication {
  @LocalStorageProp('smokesTotal') smokesTotal: number = 0;
  @LocalStorageProp('smokesBaseline') smokesBaseline: number = 20;
  @LocalStorageProp('isLoggedIn') isLoggedIn: boolean = false;

  private getSmokesColor(): string {
    if (this.smokesTotal === 0) return '#4CAF50';
    const ratio = this.smokesTotal / Math.max(this.smokesBaseline, 1);
    if (ratio >= 1.0) return '#F44336';
    if (ratio >= 0.5) return '#FF9800';
    return '#FFEB3B';
  }

  build() {
    Column() {
      if (!this.isLoggedIn) {
        Text('--')
          .fontSize(14)
          .fontColor('#555555')
      } else {
        Text('🔥')
          .fontSize(14)
        Text(`${this.smokesTotal}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getSmokesColor())
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
