import { formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'CardUpdateHelper';
const DOMAIN = 0x0000;

export class CardUpdateHelper {
  /**
   * Request the system to update all form instances of our cards.
   * Called after logging a habit or deleting a log.
   */
  public static async notifyCardsChanged(waterTotal: number, smokesTotal: number): Promise<void> {
    try {
      const data: Record<string, string | number | boolean> = {
        'waterTotal': waterTotal,
        'smokesTotal': smokesTotal,
        'isLoggedIn': true,
      };
      const bindingData = formInfo.createFormBindingData(JSON.stringify(data));
      // Request the system to trigger onUpdateForm for all instances
      formProvider.requestPublishForm('DailyStats', (err: Error) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'requestPublishForm DailyStats: ' + JSON.stringify(err));
        }
      });
      hilog.info(DOMAIN, TAG, `Card update notified: water=${waterTotal}, smokes=${smokesTotal}`);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Card update failed: ' + JSON.stringify(err));
    }
  }
}
