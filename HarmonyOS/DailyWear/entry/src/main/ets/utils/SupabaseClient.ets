import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SupabaseHabitLog, DailyTotal } from '../models/HabitLog';

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

  private getHeaders(contentType?: string): Record<string, string> {
    const headers: Record<string, string> = {
      'apikey': SupabaseClient.SUPABASE_ANON_KEY,
      'Authorization': this.accessToken ? `Bearer ${this.accessToken}` : `Bearer ${SupabaseClient.SUPABASE_ANON_KEY}`,
      'Accept': 'application/json'
    };
    if (contentType) {
      headers['Content-Type'] = contentType;
    }
    return headers;
  }

  private getStartOfDay(): string {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
  }

  private getEndOfDay(): string {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).toISOString();
  }

  public async fetchTodayCount(habitType: string): Promise<number> {
    const httpRequest = http.createHttp();
    const startOfDay = this.getStartOfDay();
    const endOfDay = this.getEndOfDay();
    
    let url = `${SupabaseClient.SUPABASE_URL}/rest/v1/habits_logs?select=value,metadata&habit_type=eq.${habitType}&is_deleted=eq.false&logged_at=gte.${startOfDay}&logged_at=lt.${endOfDay}`;
    
    if (this.userId) {
       url += `&user_id=eq.${this.userId}`;
    }

    hilog.info(DOMAIN, TAG, `fetchTodayCount URL: ${url}`);

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.getHeaders(),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        const result: Record<string, Object>[] = JSON.parse(response.result as string);
        let total = 0;
        for (const row of result) {
          if (row['value'] !== undefined) {
             let value = Number(row['value']);
             
             if (habitType === 'water' && row['metadata']) {
               try {
                 let meta: Record<string, string> = typeof row['metadata'] === 'string' 
                    ? JSON.parse(row['metadata'] as string) 
                    : row['metadata'] as Record<string, string>;
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

  // Fetch all today's logs with full details for a habit type
  public async fetchTodayLogs(habitType: string): Promise<SupabaseHabitLog[]> {
    const httpRequest = http.createHttp();
    const startOfDay = this.getStartOfDay();
    const endOfDay = this.getEndOfDay();

    let url = `${SupabaseClient.SUPABASE_URL}/rest/v1/habits_logs?select=id,user_id,habit_type,value,unit,logged_at,metadata,is_deleted&habit_type=eq.${habitType}&is_deleted=eq.false&logged_at=gte.${startOfDay}&logged_at=lt.${endOfDay}&order=logged_at.desc`;

    if (this.userId) {
      url += `&user_id=eq.${this.userId}`;
    }

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.getHeaders(),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        const result: SupabaseHabitLog[] = JSON.parse(response.result as string) as SupabaseHabitLog[];
        return result;
      }
      return [];
    } catch (err) {
      hilog.error(DOMAIN, TAG, `fetchTodayLogs error: ${JSON.stringify(err)}`);
      return [];
    } finally {
      httpRequest.destroy();
    }
  }

  // Fetch last 7 days of totals for chart rendering
  public async fetchWeeklyTotals(habitType: string): Promise<DailyTotal[]> {
    const httpRequest = http.createHttp();
    const now = new Date();
    const sevenDaysAgo = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);
    const startDate = sevenDaysAgo.toISOString();
    const endOfDay = this.getEndOfDay();

    let url = `${SupabaseClient.SUPABASE_URL}/rest/v1/habits_logs?select=value,logged_at,metadata&habit_type=eq.${habitType}&is_deleted=eq.false&logged_at=gte.${startDate}&logged_at=lt.${endOfDay}`;

    if (this.userId) {
      url += `&user_id=eq.${this.userId}`;
    }

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.getHeaders(),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        const rows: Record<string, Object>[] = JSON.parse(response.result as string);
        // Group by date
        const dateMap = new Map<string, number>();

        // Init all 7 days with 0
        for (let i = 6; i >= 0; i--) {
          const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
          const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
          dateMap.set(key, 0);
        }

        for (const row of rows) {
          const loggedAt = row['logged_at'] as string;
          const value = Number(row['value']);
          const d = new Date(loggedAt);
          const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

          // For water, exclude coffee entries
          if (habitType === 'water' && row['metadata']) {
            try {
              let meta: Record<string, string> = typeof row['metadata'] === 'string'
                ? JSON.parse(row['metadata'] as string)
                : row['metadata'] as Record<string, string>;
              if ((meta['drink'] || '').includes('Coffee')) {
                continue;
              }
            } catch (e) {}
          }

          if (dateMap.has(key)) {
            dateMap.set(key, (dateMap.get(key) ?? 0) + value);
          }
        }

        const totals: DailyTotal[] = [];
        dateMap.forEach((total: number, date: string) => {
          totals.push({ date, total });
        });
        return totals;
      }
      return [];
    } catch (err) {
      hilog.error(DOMAIN, TAG, `fetchWeeklyTotals error: ${JSON.stringify(err)}`);
      return [];
    } finally {
      httpRequest.destroy();
    }
  }

  // Fetch water goal from habit_goals table
  public async fetchWaterGoal(): Promise<number> {
    const httpRequest = http.createHttp();
    let url = `${SupabaseClient.SUPABASE_URL}/rest/v1/habit_goals?select=target_value&habit_type=eq.water&is_deleted=eq.false&limit=1`;

    if (this.userId) {
      url += `&user_id=eq.${this.userId}`;
    }

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.getHeaders(),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        const result: Record<string, Object>[] = JSON.parse(response.result as string);
        if (result.length > 0 && result[0]['target_value'] !== undefined) {
          return Number(result[0]['target_value']);
        }
      }
      return 2000; // Default goal
    } catch (err) {
      hilog.error(DOMAIN, TAG, `fetchWaterGoal error: ${JSON.stringify(err)}`);
      return 2000;
    } finally {
      httpRequest.destroy();
    }
  }

  // Fetch smokes baseline from user_preferences table
  public async fetchSmokesBaseline(): Promise<number> {
    const httpRequest = http.createHttp();
    let url = `${SupabaseClient.SUPABASE_URL}/rest/v1/user_preferences?select=smokes_baseline&limit=1`;

    if (this.userId) {
      url += `&id=eq.${this.userId}`;
    }

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.getHeaders(),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        const result: Record<string, Object>[] = JSON.parse(response.result as string);
        if (result.length > 0 && result[0]['smokes_baseline'] !== undefined) {
          return Number(result[0]['smokes_baseline']);
        }
      }
      return 20; // Default baseline
    } catch (err) {
      hilog.error(DOMAIN, TAG, `fetchSmokesBaseline error: ${JSON.stringify(err)}`);
      return 20;
    } finally {
      httpRequest.destroy();
    }
  }

  // Soft-delete a log via Supabase RPC function (works around missing PATCH in HarmonyOS http)
  public async softDeleteLog(logId: string): Promise<boolean> {
    const httpRequest = http.createHttp();
    const url = `${SupabaseClient.SUPABASE_URL}/rest/v1/rpc/soft_delete_log`;

    const headers = this.getHeaders('application/json');

    const body: Record<string, string> = {};
    body['log_id'] = logId;

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200 || response.responseCode === 204) {
        hilog.info(DOMAIN, TAG, `Soft-deleted log ${logId}`);
        return true;
      }
      hilog.error(DOMAIN, TAG, `Soft-delete failed: HTTP ${response.responseCode}`);
      return false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Soft-delete error: ${JSON.stringify(err)}`);
      return false;
    } finally {
      httpRequest.destroy();
    }
  }

  public async insertLog(table: string, data: Record<string, Object | null>): Promise<boolean> {
    const httpRequest = http.createHttp();
    const url = `${SupabaseClient.SUPABASE_URL}/rest/v1/${table}`;
    
    if (this.userId && !data.user_id) {
       data.user_id = this.userId;
    }

    const headers = this.getHeaders('application/json');
    headers['Prefer'] = 'return=minimal';

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

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        header: this.getHeaders(),
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
