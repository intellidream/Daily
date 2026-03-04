import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SupabaseClient';
const DOMAIN = 0x0000;

export class SupabaseClient {
  public static readonly SUPABASE_URL: string = 'https://akkfouifxztnfwwiclwg.supabase.co';
  public static readonly SUPABASE_ANON_KEY: string = 'sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG';
  
  private static instance: SupabaseClient | null = null;
  private accessToken: string | null = null;
  private userId: string | null = null;

  private constructor() {}

  public static getInstance(): SupabaseClient {
    if (!SupabaseClient.instance) {
      SupabaseClient.instance = new SupabaseClient();
    }
    return SupabaseClient.instance;
  }

  public getUserId(): string | null {
    return this.userId;
  }

  public setSession(token: string, userId: string): void {
    this.accessToken = token;
    this.userId = userId;
  }

  public async fetchTodayCount(habitType: string): Promise<number> {
    const httpRequest = http.createHttp();
    
    // Calculate today's start and end in UTC to match WatchOS logic roughly
    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
    const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).toISOString();
    
    let url = `${SupabaseClient.SUPABASE_URL}/rest/v1/habits_logs?select=value,metadata&habit_type=eq.${habitType}&is_deleted=eq.false&logged_at=gte.${startOfDay}&logged_at=lt.${endOfDay}`;
    
    if (this.userId) {
       url += `&user_id=eq.${this.userId}`;
    }

    const headers: Record<string, string> = {
      'apikey': SupabaseClient.SUPABASE_ANON_KEY,
      'Authorization': this.accessToken ? `Bearer ${this.accessToken}` : `Bearer ${SupabaseClient.SUPABASE_ANON_KEY}`,
      'Accept': 'application/json'
    };

    hilog.info(DOMAIN, TAG, `fetchTodayCount URL: ${url}`);

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        const result: Record<string, Object>[] = JSON.parse(response.result as string);
        let total = 0;
        for (const row of result) {
          if (row['value'] !== undefined) {
             let value = Number(row['value']);
             
             // Filter out Coffee for Water count like WatchOS does
             if (habitType === 'water' && row['metadata']) {
               try {
                 let meta: Record<string, string> = typeof row['metadata'] === 'string' 
                    ? JSON.parse(row['metadata']) 
                    : row['metadata'];
                 let drink = meta['drink'] || 'Water';
                 if (drink.includes('Coffee')) {
                    continue;
                 }
               } catch (e) {}
             }
             
             total += value;
          }
        }
        hilog.info(DOMAIN, TAG, `fetchTodayCount total for ${habitType}: ${total}`);
        return total;
      }
      return 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Fetch error: ${JSON.stringify(err)}`);
      return 0;
    } finally {
      httpRequest.destroy();
    }
  }

  public async insertLog(table: string, data: Record<string, Object | null>): Promise<boolean> {
    const httpRequest = http.createHttp();
    const url = `${SupabaseClient.SUPABASE_URL}/rest/v1/${table}`;
    
    // Inject user_id if needed by backend RLS
    if (this.userId && !data.user_id) {
       data.user_id = this.userId;
    }

    const headers: Record<string, string> = {
      'apikey': SupabaseClient.SUPABASE_ANON_KEY,
      'Authorization': this.accessToken ? `Bearer ${this.accessToken}` : `Bearer ${SupabaseClient.SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal'
    };

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(data),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 201 || response.responseCode === 200 || response.responseCode === 204) {
        hilog.info(DOMAIN, TAG, `Inserted to ${table} successfully`);
        return true;
      } else {
        hilog.error(DOMAIN, TAG, `Insert failed: HTTP ${response.responseCode} - ${response.result}`);
        return false;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Network error inserting to ${table}: ${JSON.stringify(err)}`);
      return false;
    } finally {
      httpRequest.destroy();
    }
  }

  public async deleteRow(table: string, column: string, value: string): Promise<boolean> {
    const httpRequest = http.createHttp();
    const url = `${SupabaseClient.SUPABASE_URL}/rest/v1/${table}?${column}=eq.${value}`;

    const headers: Record<string, string> = {
      'apikey': SupabaseClient.SUPABASE_ANON_KEY,
      'Authorization': this.accessToken ? `Bearer ${this.accessToken}` : `Bearer ${SupabaseClient.SUPABASE_ANON_KEY}`,
    };

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 204 || response.responseCode === 200) {
        hilog.info(DOMAIN, TAG, `Deleted row from ${table}`);
        return true;
      }
      return false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Network error deleting from ${table}: ${JSON.stringify(err)}`);
      return false;
    } finally {
      httpRequest.destroy();
    }
  }
}
