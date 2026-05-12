-- =============================================================
-- Habits Server-Side Aggregation Functions
-- Run this in the Supabase SQL Editor
-- =============================================================

-- Function 1: get_habits_consistency
-- Returns daily totals for a habit type over a date range.
-- Used for heatmaps and 7-day charts.
CREATE OR REPLACE FUNCTION get_habits_consistency(
  p_habit_type text,
  p_start_date date,
  p_end_date date
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  WITH
    -- Raw logs aggregated by date
    raw AS (
      SELECT
        (logged_at AT TIME ZONE 'UTC')::date AS day,
        SUM(value) AS total_value,
        COUNT(*) AS log_count
      FROM habits_logs
      WHERE user_id = auth.uid()
        AND habit_type = p_habit_type
        AND is_deleted = false
        AND (logged_at AT TIME ZONE 'UTC')::date BETWEEN p_start_date AND p_end_date
      GROUP BY 1
    ),
    -- Pre-consolidated summaries
    summaries AS (
      SELECT
        date::date AS day,
        total_value,
        log_count
      FROM habits_daily_summaries
      WHERE user_id = auth.uid()
        AND habit_type = p_habit_type
        AND date::date BETWEEN p_start_date AND p_end_date
    ),
    -- Merge: raw logs take priority over summaries
    merged AS (
      SELECT day, total_value, log_count FROM raw
      UNION ALL
      SELECT s.day, s.total_value, s.log_count FROM summaries s
      WHERE NOT EXISTS (SELECT 1 FROM raw r WHERE r.day = s.day)
    )
  SELECT json_agg(row_to_json(t) ORDER BY t.day)
  INTO result
  FROM merged t;

  RETURN COALESCE(result, '[]'::json);
END;
$$;

-- Function 2: get_smokes_financials
-- Returns total smokes consumed and days tracked since a given date.
-- Used for financial calculations (money saved).
CREATE OR REPLACE FUNCTION get_smokes_financials(
  p_since_date timestamptz
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  WITH
    raw AS (
      SELECT
        (logged_at AT TIME ZONE 'UTC')::date AS day,
        SUM(value) AS total_value
      FROM habits_logs
      WHERE user_id = auth.uid()
        AND habit_type = 'smokes'
        AND is_deleted = false
        AND logged_at >= p_since_date
      GROUP BY 1
    ),
    summaries AS (
      SELECT
        date::date AS day,
        total_value
      FROM habits_daily_summaries
      WHERE user_id = auth.uid()
        AND habit_type = 'smokes'
        AND date >= p_since_date::date
    ),
    merged AS (
      SELECT day, total_value FROM raw
      UNION ALL
      SELECT s.day, s.total_value FROM summaries s
      WHERE NOT EXISTS (SELECT 1 FROM raw r WHERE r.day = s.day)
    )
  SELECT json_build_object(
    'total_smoked', COALESCE(SUM(total_value), 0),
    'days_tracked', GREATEST(1, (CURRENT_DATE - p_since_date::date) + 1)
  )
  INTO result
  FROM merged;

  RETURN result;
END;
$$;
