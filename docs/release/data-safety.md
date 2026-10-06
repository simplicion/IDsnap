# IDSnap — data safety and privacy disclosures

Source of truth for the Google Play **Data safety** form, the Play **Ads** and **Advertising
ID** declarations, the App Store **App Privacy** labels and the privacy policy. Keep it in sync
with [ADR-0013](../adr/0013-free-with-ads.md) (free with ads — the default build) and ADR-0008
(amended).

This page describes the **default build: free, with ads** (`IDSNAP_MONETIZATION=ads`). The paid
builds (`licence`, `store`) show no ads and are described at the end.

## One-sentence summary
Your documents, IDs and codes never leave this phone. IDSnap is free and shows ads on a few
screens; the ads are provided by Google, which may use your device's advertising ID.

## What stays on the phone — always
Never collected, never shared, never sent anywhere by IDSnap or given to the ads SDK:

- documents, scans, photos, ID cards, passport photos, signatures;
- recognised (OCR) text, file names, folder names, notes;
- authenticator (2FA) secrets, codes and recovery codes; QR scan history;
- PINs, passwords, the vault encryption key;
- name, e-mail, phone number, contacts, precise location, account identifiers (there is no
  account).

IDSnap's own code makes **no network calls** in this build (checked by
`apps/scanner/test/architecture_test.dart`). The Google Mobile Ads SDK runs in the app's process
but is given nothing from the vault and is never present on vault, authenticator, notes, scanner
or settings screens.

## What leaves the phone, and where it goes
Only what the **Google Mobile Ads SDK** (AdMob, including the User Messaging Platform consent
SDK) collects by itself, sent to **Google** (and, through Google's ad auction, to advertising
partners) to load, show and measure ads. Per Google's own disclosure for the SDK
(<https://developers.google.com/admob/android/privacy/play-data-disclosure>):

| Data | Play data type | Collected | Shared | Why |
|---|---|---|---|---|
| **Advertising ID** (Android), app set ID, other device identifiers | Device or other IDs | Yes | Yes | Advertising or marketing, analytics, fraud prevention |
| **IP address**, used to estimate a general location | Location → Approximate location | Yes | Yes | Advertising or marketing, analytics, fraud prevention |
| **Ad interactions**: which ads were shown or tapped, app launches | App activity → App interactions | Yes | Yes | Advertising or marketing, analytics |
| **Diagnostics**: crash logs and performance data of the ads SDK (ad load times, app hangs) | App info and performance → Crash logs, Diagnostics | Yes | Yes | Analytics, fraud prevention |
| **Consent choice** (the TCF / privacy strings saved by the consent form) | — (stored on the device; sent with ad requests) | — | — | Applying the user's ad choices |

Users in the EEA, the UK and Switzerland (and the US states that require it) are asked through
Google's consent form **before any ad is requested**, and can change the choice in *Settings → Ad
privacy choices*. Without consent to personalisation IDSnap requests **non-personalised ads**.
Anyone can reset or delete the advertising ID in the phone's settings.

On Android the system's document-scanner module may be downloaded once by Google Play services
(unchanged; not part of IDSnap's own traffic).

## Google Play Console

### App content → Ads
**Yes, my app contains ads.** (Banner, native and interstitial ads from Google AdMob.) The
"Contains ads" label will show on the store listing.

### App content → Advertising ID
**Yes, my app uses an advertising ID.** Reasons: **Advertising or marketing** and **Analytics**
(both by the Google Mobile Ads SDK). The manifest declares
`com.google.android.gms.permission.AD_ID`.

### App content → Data safety — suggested answers
- **Does your app collect or share any of the required user data types?** Yes.
- **Is all of the user data collected by your app encrypted in transit?** Yes (HTTPS only;
  cleartext is refused by the network security config).
- **Do you provide a way for users to request that their data is deleted?** IDSnap holds no
  user data on any server. For ad data, point to Google's controls (reset / delete the
  advertising ID; <https://myadcenter.google.com>) and the in-app *Ad privacy choices*. Give the
  support address for questions.

| Data type | Collected | Shared | Processed ephemerally | Required or optional | Purposes |
|---|---|---|---|---|---|
| **Device or other IDs** | Yes | Yes | No | Required¹ | Advertising or marketing; Analytics; Fraud prevention, security and compliance |
| **Location → Approximate location** | Yes | Yes | No | Required¹ | Advertising or marketing; Analytics |
| **App activity → App interactions** | Yes | Yes | No | Required¹ | Advertising or marketing; Analytics |
| **App info and performance → Crash logs** | Yes | Yes | No | Required¹ | Analytics |
| **App info and performance → Diagnostics** | Yes | Yes | No | Required¹ | Analytics; Fraud prevention, security and compliance |
| Personal info, Financial info, Health, Messages, **Photos and videos**, Audio, **Files and docs**, Calendar, Contacts, Web browsing, precise location | **No** | **No** | — | — | — |

¹ "Required": the user can't switch ad data collection off entirely inside the app (they can
limit personalisation and reset the advertising ID). Re-check each answer against Google's
current disclosure page for the SDK version in use before submitting; it is Google's SDK that
collects this data, and Google updates that page.

### Other declarations
- **Target audience and content:** not directed at children. Don't select age groups under 13.
- **Financial features, health, government apps:** unchanged.
- **Privacy policy URL:** must describe the ads (the marketing site's `privacy` page does).
- **App access:** no login. **Payments:** none in this build.

## App Store App Privacy
Ads are **off on iOS** until iOS AdMob IDs are configured (ADR-0013 §6). The Google Mobile Ads
SDK is linked into the iOS app but never started, so the current iOS build collects nothing.
The safest label while the SDK is linked is still to follow Google's guidance for it; when iOS
ads are switched on, declare:

- **Identifiers → Device ID**: collected, used for *Third-Party Advertising*, *Analytics*; not
  linked to identity.
- **Location → Coarse Location**: *Third-Party Advertising*, *Analytics*.
- **Usage Data → Advertising Data, Product Interaction**: *Third-Party Advertising*, *Analytics*.
- **Diagnostics → Crash Data, Performance Data**: *Analytics*.
- **Tracking:** IDSnap does not request the IDFA and shows no App Tracking Transparency prompt
  (no `NSUserTrackingUsageDescription`). Answer "No" to tracking only if that stays true and
  Google's guidance for the SDK version agrees; otherwise add the ATT prompt first.

## Owner checklist before submitting
- AdMob → *Privacy & messaging*: publish the European regulations message and the US states
  message for the app (otherwise no consent form appears).
- AdMob → block sensitive ad categories; set the maximum ad content rating; add an
  interstitial frequency cap; review "High-engagement ads".
- Play Console → Ads: Yes · Advertising ID: Yes · Data safety as above.
- Update the store listing text: remove "no ads", "no tracking", "zero trackers", prices and
  "Pro"; keep "your documents never leave your phone".
- `app-ads.txt` live at the root of the developer website shown on Google Play.

## Paid builds (not shipped by default)
`IDSNAP_MONETIZATION=licence` (ADR-0012) shows **no ads** and starts no ads SDK. Its only
network traffic is the licence client talking to the IDSnap licence server: a **hashed device
ID** (`sha256("idsnap.device.v1:" + ANDROID_ID or Keychain ID)`), platform and app version; the
server keeps the plan, its expiry and the payment sessions; payments happen on the 180 Pay page
in the browser (card, UPI and bank details never reach IDSnap); the customer's e-mail is
received from 180 Pay only for monthly subscribers. If that build is ever shipped, declare
*Device or other IDs* (collected, not shared; app functionality, fraud prevention), *Purchase
history* and, for subscribers, *Email address* — and note that the ads SDK is still linked
(dormant) and the manifest still declares `AD_ID` unless `engine_ads` is removed from the app.
`IDSNAP_MONETIZATION=store` uses Google Play Billing / StoreKit and sends nothing of its own.
