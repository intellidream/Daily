Can you check and explain to me why rows aren't deleted from watch_pairings, I don't really mind them, but should they after a pairing is succesfull, at least, maybe even for failures? Also, in paired_watches, if I unpair a watch the row still remains there... Just see and explain, we'll decide together what to do (this needs checking in mainapp I think, just FYI)

----

I looked into the database logic for both tables, and here is exactly why you're seeing those leftover rows:

1. watch_pairings (The 6-Digit Code Table)
Currently, no one is programmed to delete these rows.

The Watch creates the row and waits.
The Phone adds the access_token to the row.
The Watch reads the access_token and logs in.
...And the row just sits there forever. (If the Phone deleted it immediately, the Watch might miss reading it!).
My Recommendation: We should make the Watch Apps explicitly call a DELETE on their specific row the moment they successfully finish reading the token. For abandoned/failed pairings that never got a token, we could either add a quick SQL script to your database to auto-delete rows older than 10 minutes, or we could leave them (they are harmless tiny strings).

2. paired_watches (The Long-Term Sync Table)
When you tap "Unpair" in the MAUI App, the code does this: watch.IsActive = false; await SupabaseClient.From<PairedWatch>().Update(watch);

It is doing a "Soft Delete". It leaves the row physically in the database, but flips IsActive to false. The MAUI app only loads watches where IsActive == true, so it disappears from your screen, but remains in Supabase.

What would you like to do?

Should I change the MAUI app's "Unpair" button to do a Hard Delete (permanently erase the row from the paired_watches database table)?
Should I add logic to all the Watches (WearOS, WatchOS, HarmonyOS) so they automatically DELETE their 6-digit code from watch_pairings after a successful pair?
Should I write a Postgres SQL script for your database that automatically sweeps dead watch_pairings every hour?