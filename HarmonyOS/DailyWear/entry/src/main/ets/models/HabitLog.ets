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

// Full log entry as returned from Supabase habits_logs table
export interface SupabaseHabitLog {
  id: string;
  user_id: string;
  habit_type: string;
  value: number;
  unit: string;
  logged_at: string;
  metadata: string | null;
  is_deleted: boolean;
}

// Parsed daily total for chart rendering
export interface DailyTotal {
  date: string; // YYYY-MM-DD
  total: number;
}

// Drink type extracted from metadata
export type DrinkType = 'Large Water' | 'Small Water' | 'Coffee';
export type SmokeType = 'Cigarette' | 'Heated Tobacco';
