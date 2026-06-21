-- Docs/SQL/20260622_CalendarAccounts_SoftDelete.sql
-- Add soft delete support to calendar_accounts table

ALTER TABLE public.calendar_accounts ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
