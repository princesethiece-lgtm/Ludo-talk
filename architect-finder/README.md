# AN Architects (iPhone)

Finds architects, consultants and interior designers around your location or a city (Ludhiana, Jalandhar or any city you add), within 1 to 25 km. Shows firm name, rating, number of reviews, phone (tap to call, only when a number is listed) and a one-tap map link.

Data comes from the Google Places API (New), so the app needs your own API key (Settings, gear icon).

* Free allowance: 1,000 searches a month. The app stops at 900 and does not count repeated searches (saved for 12 hours).
* Restrict the key to "Places API (New)" and to the iOS bundle id `com.audionation.architectfinder`.

Build: pushing to `main` runs `.github/workflows/build-architect-ipa.yml` and publishes `AN-Architects.ipa` under Releases (tag `architects-N`). Install it with AltServer or Sideloadly like the Ludo app.
