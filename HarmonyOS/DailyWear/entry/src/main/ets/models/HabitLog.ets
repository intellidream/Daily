export enum LogType {
  Bubbles = 'bubbles',
  Smokes = 'smokes'
}

export interface HabitLog {
  id: string;
  type: LogType;
  timestamp: string; // ISO8601 string
  synced: boolean;
}
