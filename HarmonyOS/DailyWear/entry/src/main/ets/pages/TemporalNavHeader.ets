import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct TemporalNavHeader {
  @Prop title: string = '';
  @Prop canGoForward: boolean = false;
  @Prop accentColor: string = '#00FFFF';
  onPrevious: () => void = () => {};
  onNext: () => void = () => {};

  private triggerHaptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
    } catch (_e) {}
  }

  build() {
    Row() {
      // Previous Button (‹)
      Row() {
        Text('‹')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor)
      }
      .width(28)
      .height(24)
      .borderRadius(6)
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.triggerHaptic();
        this.onPrevious();
      })

      // Centered Date / Week Label
      Text(this.title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .layoutWeight(1)

      // Next Button (›)
      if (this.canGoForward) {
        Row() {
          Text('›')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.accentColor)
        }
        .width(28)
        .height(24)
        .borderRadius(6)
        .backgroundColor('rgba(255, 255, 255, 0.12)')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.triggerHaptic();
          this.onNext();
        })
      } else {
        Row()
          .width(28)
          .height(24)
      }
    }
    .width('94%')
    .height(30)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .margin({ top: 4, bottom: 4 })
  }
}
