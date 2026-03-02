# Features Logic

## Smokes
### Principles
    - This is not supposed to make you quit, no app can do that (so we're not a Quit Now clone), but to help manage and hopefully lower your tobacco intake;
    - The starting point of using this feature (which is supposed to compare to and improve on your previous smoking habits), will be decided and set by you;
### Configuration
    - The app allows you to set the following Configuration settings:
        - Quit Start Date - the date to start manage and lower your tobacco intake (I started to manage my tobacco intake on January 1st, 2026);
        - Baseline (Cigs/Day) - how much you used to smoke before (for example I used to smoke 2 packs, as in 40 cigarretes, per day);
        - Cigs in Pack - how many are in the packs you smoke/smoked, to help us understand the cost of a cigarette;
        - Cost per Pack - self-explanatory, will help us determine your savings;
        - Currency - self-explanatory, to provide you with your savings in your currency;
    - The app should save these settings for each logged in user and use them to provide that user with all of his/her smoking data, habits and savings;
    - How is the feature built in the UI of the main apps (iOS/Android/Mac/Windows):

### Configuration
    - User sets following 
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
