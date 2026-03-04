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
    let context = getContext(this);
    OfflineSyncManager.getInstance().init(context);
    
    const isAuth = await WatchSessionManager.getInstance().init(context);
    this.isAuthenticated = isAuth;
    this.isLoaded = true;
    
    // Listen for the PairingView signaling success
    AppStorage.setOrCreate('PairingSuccess', false);
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
        .indicator(true)          
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