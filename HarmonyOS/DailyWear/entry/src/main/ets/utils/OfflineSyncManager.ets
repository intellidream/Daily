import { HabitLog, LogType } from '../models/HabitLog';
import preferences from '@ohos.data.preferences';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'OfflineSyncManager';
const DOMAIN = 0x0000;
const STORE_NAME = 'daily_offline_queue';
const QUEUE_KEY = 'offline_logs';

export class OfflineSyncManager {
  private static instance: OfflineSyncManager;
  private pref: preferences.Preferences | null = null;
  private queue: HabitLog[] = [];

  private constructor() {}

  public static getInstance(): OfflineSyncManager {
    if (!OfflineSyncManager.instance) {
      OfflineSyncManager.instance = new OfflineSyncManager();
    }
    return OfflineSyncManager.instance;
  }

  public async init(context: Context): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, STORE_NAME);
      await this.loadQueue();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to init preferences', JSON.stringify(err));
    }
  }

  private async loadQueue(): Promise<void> {
    if (!this.pref) return;
    try {
      const data = await this.pref.get(QUEUE_KEY, '[]');
      this.queue = JSON.parse(data as string);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to parse offline queue');
      this.queue = [];
    }
  }

  private async saveQueue(): Promise<void> {
    if (!this.pref) return;
    try {
      await this.pref.put(QUEUE_KEY, JSON.stringify(this.queue));
      await this.pref.flush();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to save offline queue');
    }
  }

  public async enqueueLog(type: LogType, timestamp: string = new Date().toISOString()): Promise<void> {
    const log: HabitLog = {
      id: this.generateUUID(),
      type: type,
      timestamp: timestamp,
      synced: false
    };
    this.queue.push(log);
    await this.saveQueue();
    hilog.info(DOMAIN, TAG, `Enqueued offline log: ${type}`);
  }

  public getQueue(): HabitLog[] {
    return this.queue;
  }

  public async clearQueue(): Promise<void> {
    this.queue = [];
    await this.saveQueue();
  }

  public async removeLog(id: string): Promise<void> {
    this.queue = this.queue.filter(log => log.id !== id);
    await this.saveQueue();
  }

  private generateUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      let r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }
}
