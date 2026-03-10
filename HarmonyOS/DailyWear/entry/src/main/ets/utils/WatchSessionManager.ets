import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import { SupabaseClient, RefreshedTokens } from './SupabaseClient';
import util from '@ohos.util';
import buffer from '@ohos.buffer';

const TAG = 'WatchSessionManager';
const DOMAIN = 0x0000;
const STORE_NAME = 'daily_auth_store';
const ACCESS_TOKEN_KEY = 'supabase_access_token';
const REFRESH_TOKEN_KEY = 'supabase_refresh_token';
const USER_ID_KEY = 'supabase_user_id';
const PAIRED_WATCH_ID_KEY = 'paired_watch_id';

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
      const refresh = await this.pref.get(REFRESH_TOKEN_KEY, '') as string;
      const userId = await this.pref.get(USER_ID_KEY, '') as string;

      if (token && userId) {
        if (this.isTokenValid(token)) {
          // Token still valid — use it immediately
          SupabaseClient.getInstance().setSession(token, userId);
          this.isAuthenticated = true;
          hilog.info(DOMAIN, TAG, 'Restored existing session for user: ' + userId);

          // Proactively refresh in the background to extend the session
          if (refresh) {
            this.refreshSession(refresh, userId);
          }
          return true;
        }

        // Token expired — attempt refresh instead of clearing
        if (refresh) {
          hilog.info(DOMAIN, TAG, 'Token expired, attempting refresh');
          const refreshed = await this.refreshSession(refresh, userId);
          if (refreshed) {
            return true;
          }
        }

        hilog.warn(DOMAIN, TAG, 'Token expired and refresh failed, clearing session');
        await this.clearSession();
        return false;
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
    // Deactivate the paired_watches record
    if (this.pref) {
      try {
        const pairedWatchId = await this.pref.get(PAIRED_WATCH_ID_KEY, '') as string;
        if (pairedWatchId) {
          await SupabaseClient.getInstance().updateRows(
            'paired_watches', 'id', pairedWatchId, { 'is_active': false }
          );
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Failed to deactivate paired watch record');
      }
    }

    if (this.pref) {
      try {
        await this.pref.delete(ACCESS_TOKEN_KEY);
        await this.pref.delete(REFRESH_TOKEN_KEY);
        await this.pref.delete(USER_ID_KEY);
        await this.pref.delete(PAIRED_WATCH_ID_KEY);
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

            // Register this device in the persistent paired_watches table
            await this.registerPairing(userId || '');
            
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

  /**
   * Refreshes the Supabase session using the stored refresh token.
   * Returns true if successful, false otherwise.
   */
  private async refreshSession(refreshToken: string, userId: string): Promise<boolean> {
    try {
      const result = await SupabaseClient.getInstance().refreshToken(refreshToken);
      if (result) {
        await this.saveSession(result.access_token, result.refresh_token, userId);
        const newUserId = this.extractUserId(result.access_token) || userId;
        SupabaseClient.getInstance().setSession(result.access_token, newUserId);
        this.isAuthenticated = true;
        hilog.info(DOMAIN, TAG, 'Session refreshed successfully');
        return true;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'refreshSession error: ' + JSON.stringify(e));
    }
    return false;
  }

  /**
   * Called when the app comes to foreground. Checks for repair tokens first,
   * then refreshes the session to ensure a valid access token.
   */
  public async onAppResumed(): Promise<void> {
    if (!this.pref) return;

    // Step 0: Check if the main app pushed repair tokens (fresh credentials)
    await this.checkForRepairTokens();

    // Step 1: Refresh the session using stored tokens
    try {
      const token = await this.pref.get(ACCESS_TOKEN_KEY, '') as string;
      const refresh = await this.pref.get(REFRESH_TOKEN_KEY, '') as string;
      const userId = await this.pref.get(USER_ID_KEY, '') as string;

      if (token && refresh && userId) {
        // Always force-refresh on resume — the access token is almost certainly
        // expired after HarmonyOS suspends the app
        await this.refreshSession(refresh, userId);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onAppResumed error: ' + JSON.stringify(e));
    }
  }

  /**
   * Registers this device in the persistent paired_watches table after a successful
   * pairing. Saves the returned record ID to preferences so we can check for repair
   * tokens on future app resumes.
   */
  private async registerPairing(userId: string): Promise<void> {
    try {
      const deviceName = 'HarmonyOS Watch';
      const record: Record<string, Object | null> = {
        'user_id': userId,
        'platform': 'harmonyos',
        'device_name': deviceName,
        'is_active': true
      };

      const inserted = await SupabaseClient.getInstance().insertAndReturn('paired_watches', record);
      if (inserted && inserted['id']) {
        const id = inserted['id'] as string;
        if (this.pref) {
          await this.pref.put(PAIRED_WATCH_ID_KEY, id);
          await this.pref.flush();
        }
        hilog.info(DOMAIN, TAG, 'Registered pairing with id: ' + id);
      }
    } catch (e) {
      // Non-critical — pairing still works without the persistent record
      hilog.error(DOMAIN, TAG, 'registerPairing error: ' + JSON.stringify(e));
    }
  }

  /**
   * Checks the paired_watches table for repair tokens pushed by the main app.
   * If found, applies them to restore the session and clears the pending columns.
   */
  private async checkForRepairTokens(): Promise<void> {
    if (!this.pref) return;
    try {
      const pairedWatchId = await this.pref.get(PAIRED_WATCH_ID_KEY, '') as string;
      if (!pairedWatchId) return;

      const rows = await SupabaseClient.getInstance().selectRows(
        'paired_watches', `id=eq.${pairedWatchId}`
      );

      if (rows.length === 0) return;
      const record = rows[0];
      const pendingAccess = record['pending_access_token'] as string | null;
      const pendingRefresh = record['pending_refresh_token'] as string | null;

      if (pendingAccess && pendingRefresh) {
        hilog.info(DOMAIN, TAG, 'Found repair tokens, applying...');

        // Extract user ID from the fresh token
        const userId = this.extractUserId(pendingAccess) || (await this.pref.get(USER_ID_KEY, '') as string);

        // Save and apply the fresh tokens
        await this.saveSession(pendingAccess, pendingRefresh, userId);
        SupabaseClient.getInstance().setSession(pendingAccess, userId);
        this.isAuthenticated = true;

        // Refresh to get a fully valid session
        await this.refreshSession(pendingRefresh, userId);

        // Clear the pending tokens so we don't re-apply on next resume
        await SupabaseClient.getInstance().updateRows(
          'paired_watches', 'id', pairedWatchId,
          { 'pending_access_token': null, 'pending_refresh_token': null }
        );

        hilog.info(DOMAIN, TAG, 'Repair tokens applied and cleared');
      }
    } catch (e) {
      // Non-critical — normal session refresh will still run
      hilog.error(DOMAIN, TAG, 'checkForRepairTokens error: ' + JSON.stringify(e));
    }
  }
}
