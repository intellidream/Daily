import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import http from '@ohos.net.http';

const TAG = 'DailyCardAbility';
const DOMAIN = 0x0000;
const SUPABASE_URL = 'https://akkfouifxztnfwwiclwg.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG';
const AUTH_STORE = 'daily_auth_store';

export default class DailyCardAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    const defaultData: Record<string, string | number | boolean> = {
      'waterTotal': 0,
      'smokesTotal': 0,
      'isLoggedIn': false,
    };

    // Trigger async data fetch
    this.updateCardData(want);

    return formBindingData.createFormBindingData(JSON.stringify(defaultData));
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm: ' + formId);
    this.fetchAndPush(formId);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm: ' + formId);
  }

  private async updateCardData(want: Want): Promise<void> {
    const formId = want.parameters?.['ohos.extra.param.key.form_identity'] as string;
    if (!formId) return;
    await this.fetchAndPush(formId);
  }

  private async fetchAndPush(formId: string): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.context, AUTH_STORE);
      const token = await pref.get('supabase_access_token', '') as string;
      const userId = await pref.get('supabase_user_id', '') as string;

      if (!token || !userId) {
        const data: Record<string, string | number | boolean> = {
          'waterTotal': 0,
          'smokesTotal': 0,
          'isLoggedIn': false,
        };
        const bd: formBindingData.FormBindingData = formBindingData.createFormBindingData(JSON.stringify(data));
        await formProvider.updateForm(formId, bd);
        return;
      }

      const now = new Date();
      const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
      const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).toISOString();

      const url = `${SUPABASE_URL}/rest/v1/habits_logs?select=habit_type,value&is_deleted=eq.false&logged_at=gte.${startOfDay}&logged_at=lt.${endOfDay}&user_id=eq.${userId}`;

      const httpRequest = http.createHttp();
      const headers: Record<string, string> = {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json'
      };

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
      });

      let waterTotal = 0;
      let smokesTotal = 0;

      if (response.responseCode === 200) {
        const rows: Record<string, Object>[] = JSON.parse(response.result as string);
        for (const row of rows) {
          const habitType = row['habit_type'] as string;
          const value = Number(row['value']);
          if (habitType === 'water') {
            waterTotal += value;
          } else if (habitType === 'smokes') {
            smokesTotal += value;
          }
        }
      }

      httpRequest.destroy();

      const data: Record<string, string | number | boolean> = {
        'waterTotal': waterTotal,
        'smokesTotal': smokesTotal,
        'isLoggedIn': true,
      };
      const bd: formBindingData.FormBindingData = formBindingData.createFormBindingData(JSON.stringify(data));
      await formProvider.updateForm(formId, bd);
      hilog.info(DOMAIN, TAG, `Updated card: water=${waterTotal}, smokes=${smokesTotal}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to update card data: ' + JSON.stringify(err));
    }
  }
}
