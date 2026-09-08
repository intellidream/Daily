import { BubblesView } from './BubblesView';
import { Bubbles7DaysView } from './Bubbles7DaysView';
import { SmokesView } from './SmokesView';
import { Smokes7DaysView } from './Smokes7DaysView';
import { AboutView } from './AboutView';
import { LogsView } from './LogsView';
import { PairingView } from './PairingView';
import { OfflineSyncManager } from '../utils/OfflineSyncManager';
import { WatchSessionManager } from '../utils/WatchSessionManager';
import { SupabaseClient } from '../utils/SupabaseClient';
import { SupabaseHabitLog } from '../models/HabitLog';

@Entry
@Component
struct Index {
  @State isAuthenticated: boolean = false;
  @State isLoaded: boolean = false;
  @State showLogs: boolean = false;
  @State logsHabitType: string = 'water';
  @State logsDateTitle: string = 'Today';
  @State logsList: SupabaseHabitLog[] = [];

  @State refreshBubbles: number = 0;
  @State refreshBubbles7D: number = 0;
  @State refreshSmokes: number = 0;
  @State refreshSmokes7D: number = 0;
  @State refreshAbout: number = 0;

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
    } catch (_err) {
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
          .width(50)
          .height(50)
          .color('#00FFFF')
      } else if (this.isAuthenticated || this.pairingSuccess) {
        if (this.showLogs) {
          LogsView({
            habitType: this.logsHabitType,
            dateTitle: this.logsDateTitle,
            logs: this.logsList,
            onDelete: (logId: string) => {
              this.logsList = this.logsList.filter(l => l.id !== logId);
              SupabaseClient.getInstance().softDeleteLog(logId);
              if (this.logsHabitType === 'water') {
                this.refreshBubbles++;
                this.refreshBubbles7D++;
              } else {
                this.refreshSmokes++;
                this.refreshSmokes7D++;
              }
            },
            onClose: () => {
              this.showLogs = false;
              if (this.logsHabitType === 'water') {
                this.refreshBubbles++;
              } else {
                this.refreshSmokes++;
              }
            }
          })
        } else {
          // Canonical 5-Page Swiper (watchOS & ZeppOS Parity)
          Swiper(this.swiperController) {
            BubblesView({
              refreshTrigger: this.refreshBubbles,
              onOpenLogs: (habitType: string, dateTitle: string, logs: SupabaseHabitLog[]) => {
                this.logsHabitType = habitType;
                this.logsDateTitle = dateTitle;
                this.logsList = logs;
                this.showLogs = true;
              }
            })

            Bubbles7DaysView({ refreshTrigger: this.refreshBubbles7D })

            SmokesView({
              refreshTrigger: this.refreshSmokes,
              onOpenLogs: (habitType: string, dateTitle: string, logs: SupabaseHabitLog[]) => {
                this.logsHabitType = habitType;
                this.logsDateTitle = dateTitle;
                this.logsList = logs;
                this.showLogs = true;
              }
            })

            Smokes7DaysView({ refreshTrigger: this.refreshSmokes7D })

            AboutView({ refreshTrigger: this.refreshAbout })
          }
          .indicator(
            new DotIndicator()
              .color('#333333')
              .selectedColor('#00FFFF')
          )
          .loop(false)
          .duration(350)
          .itemSpace(0)
          .width('100%')
          .height('100%')
          .onChange((index: number) => {
            if (index === 0) {
              this.refreshBubbles++;
            } else if (index === 1) {
              this.refreshBubbles7D++;
            } else if (index === 2) {
              this.refreshSmokes++;
            } else if (index === 3) {
              this.refreshSmokes7D++;
            } else if (index === 4) {
              this.refreshAbout++;
            }
          })
        }
      } else {
        PairingView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}