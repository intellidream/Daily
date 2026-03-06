import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import { SupabaseClient } from './SupabaseClient';
import util from '@ohos.util';
import buffer from '@ohos.buffer';

const TAG = 'WatchSessionManager';
const DOMAIN = 0x0000;
const STORE_NAME = 'daily_auth_store';
const ACCESS_TOKEN_KEY = 'supabase_access_token';
const REFRESH_TOKEN_KEY = 'supabase_refresh_token';
const USER_ID_KEY = 'supabase_user_id';

export class WatchSessionManager {
  private static instance: WatchSessionManager | null = null;
  private pref: preferences.Preferences | null = null;
  private pollIntervalId: number = -1;
  public pairingCode: string = '';
  public isAuthenticated: boolean = false;

  private constructor() {}

  public static getInstance(): WatchSessionManager {
    if (!WatchSessionManager.instance) {
      WatchSessionManager.instance = new WatchSessionManager();
    }
    return WatchSessionManager.instance;
  }

  public async init(context: Context): Promise<boolean> {
    try {
      this.pref = await preferences.getPreferences(context, STORE_NAME);
      return await this.checkExistingSession();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to init preferences: ' + JSON.stringify(err));
      return false;
    }
  }

  private async checkExistingSession(): Promise<boolean> {
    if (!this.pref) return false;
    try {
      const token = await this.pref.get(ACCESS_TOKEN_KEY, '') as string;
      const userId = await this.pref.get(USER_ID_KEY, '') as string;

      if (token && userId) {
        // Validate token is not expired before trusting it
        if (!this.isTokenValid(token)) {
          hilog.warn(DOMAIN, TAG, 'Stored token is expired or invalid, clearing session');
          await this.clearSession();
          return false;
        }
        SupabaseClient.getInstance().setSession(token, userId);
        this.isAuthenticated = true;
        hilog.info(DOMAIN, TAG, 'Restored existing session for user: ' + userId);
        return true;
      }
      hilog.info(DOMAIN, TAG, 'No stored session found');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to get credentials from preferences');
    }
    return false;
  }

  private isTokenValid(jwt: string): boolean {
    try {
      const parts = jwt.split('.');
      if (parts.length !== 3) return false;

      let base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const pad = base64.length % 4;
      if (pad) {
        base64 += '='.repeat(4 - pad);
      }

      const buf = buffer.from(base64, 'base64');
      const jsonString = buf.toString('utf-8');
      const payload = JSON.parse(jsonString) as Record<string, Object>;

      const exp = Number(payload['exp']);
      if (!exp) return false;

      // Token expired if exp is in the past (with 60s grace)
      const nowSec = Math.floor(Date.now() / 1000);
      return exp > (nowSec - 60);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to validate JWT: ' + JSON.stringify(e));
      return false;
    }
  }

  public async clearSession(): Promise<void> {
    if (this.pref) {
      try {
        await this.pref.delete(ACCESS_TOKEN_KEY);
        await this.pref.delete(REFRESH_TOKEN_KEY);
        await this.pref.delete(USER_ID_KEY);
        await this.pref.flush();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Failed to clear session from preferences');
      }
    }
    this.isAuthenticated = false;
    SupabaseClient.getInstance().setSession('', '');
    hilog.info(DOMAIN, TAG, 'Session cleared');
  }

  public async generatePairingCode(): Promise<string> {
    // Generate random 6 digit code
    this.pairingCode = Math.floor(100000 + Math.random() * 900000).toString();
    
    // Insert into watch_pairings
    const pairingData: Record<string, Object | null> = {
      'code': this.pairingCode,
      'access_token': null,
      'refresh_token': null
    };
    
    const success = await SupabaseClient.getInstance().insertLog('watch_pairings', pairingData);

    if (success) {
      this.startPolling();
    } else {
      hilog.error(DOMAIN, TAG, 'Failed to insert pairing code into Supabase.');
    }
    
    return this.pairingCode;
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollIntervalId = setInterval(() => {
      this.checkPairingStatus();
    }, 3000);
  }

  public stopPolling(): void {
    if (this.pollIntervalId !== -1) {
      clearInterval(this.pollIntervalId);
      this.pollIntervalId = -1;
    }
  }

  private async checkPairingStatus(): Promise<void> {
    const url = `${SupabaseClient.SUPABASE_URL}/rest/v1/watch_pairings?code=eq.${this.pairingCode}&select=*`;
    const httpRequest = http.createHttp();

    const headers: Record<string, string> = {
      'apikey': SupabaseClient.SUPABASE_ANON_KEY,
      'Authorization': `Bearer ${SupabaseClient.SUPABASE_ANON_KEY}`,
      'Accept': 'application/json'
    };

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
      });

      if (response.responseCode === 200) {
        let result: Record<string, Object>[] = JSON.parse(response.result as string);
        hilog.info(DOMAIN, TAG, `Parsed pairing response: ${JSON.stringify(result)}`);
        
        if (result.length > 0) {
          const pairing = result[0];
          const token = pairing['access_token'] as string | null;
          const refresh = pairing['refresh_token'] as string | null;
          
          if (token) {
            hilog.info(DOMAIN, TAG, 'Tokens received! Pairing successful.');
            this.stopPolling();
            
            const userId = this.extractUserId(token);
            await this.saveSession(token, refresh || '', userId || '');
            
            // Clean up the row
            await SupabaseClient.getInstance().deleteRow('watch_pairings', 'code', this.pairingCode);
            
            // Re-init client with token
            await this.checkExistingSession();
            
            // Notify UI
            AppStorage.setOrCreate('PairingSuccess', true);
          }
        } else {
            hilog.warn(DOMAIN, TAG, 'Pairing row missing/deleted.');
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Polling error: ${JSON.stringify(err)}`);
    } finally {
      httpRequest.destroy();
    }
  }

  private extractUserId(jwt: string): string | null {
    try {
      const parts = jwt.split('.');
      if (parts.length !== 3) return null;
      
      let base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const pad = base64.length % 4;
      if (pad) {
        base64 += '='.repeat(4 - pad);
      }
      
      let buf = buffer.from(base64, 'base64');
      let jsonString = buf.toString('utf-8');
      
      const payload = JSON.parse(jsonString) as Record<string, string>;
      hilog.info(DOMAIN, TAG, `Extracted JWT sub: ${payload['sub']}`);
      return payload['sub'] || null;
      
    } catch (e) {
       hilog.error(DOMAIN, TAG, `Failed to extract user ID from JWT: ${JSON.stringify(e)}`);
       return null;
    }
  }

  private async saveSession(token: string, refresh: string, userId: string): Promise<void> {
    if (!this.pref) return;
    try {
      await this.pref.put(ACCESS_TOKEN_KEY, token);
      await this.pref.put(REFRESH_TOKEN_KEY, refresh);
      await this.pref.put(USER_ID_KEY, userId);
      await this.pref.flush();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to save credentials to preferences');
    }
  }
}
