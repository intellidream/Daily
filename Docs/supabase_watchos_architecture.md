# Supabase Architecture for WatchOS & WearOS

## Data Layer (Reusable)
The Supabase Database Schema (tables like `water_logs`, `habit_goals`) is fully reusable. Your WatchOS (Swift) and WearOS (Kotlin/MAUI) apps will connect to the **same** Supabase project and read/write to these exact tables.

## Authorization
You will use the **Supabase Auth SDKs** native to each platform (Swift, Kotlin, etc.) to sign the user in. This generates a session token that respects the Row Level Security (RLS) policies defined in the database.

## API Strategy
You **do not** need to rewrite the API. Supabase **is** the API. 
- It automatically exposes your database as a REST/GraphQL API.
- You do not need a separate `.NET` Web API middleware unless you have complex business logic.
- Use the standard **Supabase Client SDK** for each platform to query data directly.

## Logic Sharing
- **Backend Logic**: Handled by Supabase RLS Policies and Database Triggers.
- **UI Logic**: Will likely need to be rewritten for the native experiences (SwiftUI for Apple Watch, Jetpack Compose for WearOS), as UI code is rarely shared with MAUI unless using MAUI for Android Wear.
