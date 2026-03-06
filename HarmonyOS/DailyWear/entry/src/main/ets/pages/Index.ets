import { BubblesView } from './BubblesView';
import { SmokesView } from './SmokesView';
import { PairingView } from './PairingView';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { WatchSessionManager } from '../utils/WatchSessionManager';

@Entry
@Component
struct Index {
  @State isAuthenticated: boolean = false;
  @State isLoaded: boolean = false;
  @StorageLink('PairingSuccess') pairingSuccess: boolean = false;
  private swiperController: SwiperController = new SwiperController();

  async aboutToAppear() {
    try {
      const context: Context = this.getUIContext().getHostContext()!;
      await OfflineSyncManager.getInstance().init(context);

      const isAuth = await WatchSessionManager.getInstance().init(context);
      this.isAuthenticated = isAuth;

      // Process any queued offline logs on startup
      if (isAuth) {
        await OfflineSyncManager.getInstance().processQueue();
      }
    } catch (err) {
      // If init fails, default to unauthenticated (shows pairing)
      this.isAuthenticated = false;
    }
    this.isLoaded = true;
  }

  onPageShow() {
    // Process offline queue whenever app comes to foreground
    if (this.isAuthenticated || this.pairingSuccess) {
      OfflineSyncManager.getInstance().processQueue();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.isLoaded) {
        LoadingProgress()
          .width(60)
          .height(60)
          .color('#0277BD')
      } else if (this.isAuthenticated || this.pairingSuccess) {
        Swiper(this.swiperController) {
          BubblesView()
          SmokesView()
        }
        .indicator(
          new DotIndicator()
            .color('#333333')
            .selectedColor('#0277BD')
        )
        .loop(false)              
        .duration(400)
        .itemSpace(0)
        .width('100%')
        .height('100%')
      } else {
        PairingView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}