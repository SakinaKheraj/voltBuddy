# VoltBuddy — Google Play submission guide

Play build: app ID `com.voltbuddy.app`, built with `--flavor play`.
It has **no research features**: no interaction tracking, no Student ID prompt, Talk answers
offline. Nothing leaves the phone unless the user taps **Share CSV**.

Build commands (from `voltBuddy/`):

```
flutter build appbundle --release --flavor play   # upload this .aab to Play
flutter build apk --release --flavor play         # same app as an APK, for testing on a phone
flutter build apk --release --flavor study        # research build for participants (com.example.voltbuddy)
```

The upload key lives outside the repo (`backups/play-upload-key/`), referenced by
`android/key.properties` (git-ignored). Keep a copy of that folder safe.

---

## 1. Create app (Play Console → Create app)

| Field | Answer |
|---|---|
| App name | VoltBuddy |
| Default language | English (United States) or English (India) |
| App or game | **App** |
| Free or paid | **Free** |
| Declarations | Tick both (Developer Program Policies, US export laws) |

## 2. Store listing (Grow → Store presence → Main store listing)

**Short description (max 80 chars)**

```
Gamified battery companion: keep your pet healthy by charging between 20–85%.
```

**Full description**

```
VoltBuddy turns healthy charging into a game.

Your phone's battery becomes your pet's life force. Charge between 20% and 85% and your pet earns XP, ranks up and stays happy. Leave it plugged in at 100% or let it drop below 10% and your pet gets tired or sick.

FEATURES
• Virtual pet (cat, dog or rabbit) that reacts to your real charging habits
• Automatic charging-session tracking, even when the app is closed
• "Unplug at 85%" reminder in the ongoing notification
• Weekly report, habit insights and a charging-quality heatmap
• Full charge history with start/end level, duration and charge speed
• Regular or Gen Z language mode
• Export your own charging history as a CSV file

PRIVACY
All data stays on your phone. VoltBuddy has no account, no ads and no analytics. Your charging history only leaves your phone if you choose to export it.

VoltBuddy was developed as part of a university Human–Computer Interaction research project on sustainable smartphone use.
```

**Graphics** (files in `Phase2 App/play_store_assets/`)

| Asset | File | Rule |
|---|---|---|
| App icon | `icon_512.png` | 512 × 512 PNG |
| Feature graphic | `feature_graphic_1024x500.png` | 1024 × 500 |
| Phone screenshots | at least 2; best: fresh screenshots of the Play build with real data | max 2:1 ratio (e.g. 1080 × 2160). Raw 1080 × 2400 phone screenshots are too tall and must be cropped |

**Category**: Tools (or Productivity). **Contact email**: your developer email.
**Privacy policy URL**: see section 8.

## 3. App content (Policy → App content)

| Section | Answer |
|---|---|
| **Privacy policy** | URL of the page from section 8 |
| **App access** | All functionality is available without special access (no login) |
| **Ads** | No, my app does not contain ads |
| **Content rating** | Category: *All other app types*. Answer **No** to violence, sexual content, language, drugs, gambling, user interaction/sharing, location sharing, digital purchases. Expected rating: Everyone / PEGI 3 |
| **Target audience** | **18 and over** (simplest: avoids the Families policy). If asked whether the store listing could appeal to children: No — it is a battery-health utility for adults |
| **News app** | No |
| **COVID-19 apps** | Not a COVID-19 app |
| **Data safety** | Section 4 |
| **Government app** | No |
| **Financial features** | None |
| **Health** | Not a health app (battery health refers to the phone's battery) |
| **Foreground service permissions** | Section 5 |

## 4. Data safety

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| (If asked) Is all user data encrypted in transit? | Not applicable — no data is transmitted |
| (If asked) Can users request data deletion? | Users can delete all data in the app (Logs → Clear All) or by uninstalling |

Why "No": all charging data is stored only on the device. The app has no backend, account,
ads or analytics SDK. CSV export happens only when the user taps Share CSV and chooses where to
send it through Android's share sheet. The only network use is downloading the app's fonts
(no user data is sent).

## 5. Foreground service declaration

Play Console asks for each foreground-service type the app uses (Android 14+).
The Play build declares only **Special use**.

| Field | Answer |
|---|---|
| Foreground service type | **Special use** |
| Feature description | `VoltBuddy continuously monitors the battery level and charger connection to record each charging session (start and end level, time) and to show a live "unplug at 85%" reminder in its notification while the phone charges. Android provides no foreground-service type for battery monitoring. The service shows a persistent, low-priority notification at all times, uses no location, camera or microphone, and does not transfer data.` |
| What happens if the task is interrupted/deferred? | `Charging sessions would be missed or recorded with wrong start/end times, and the user would not get the 85% unplug reminder at the moment it matters.` |
| Video link | Record a 30–60 s screen video: open VoltBuddy → plug in the charger → pull down the notification shade to show the VoltBuddy notification updating (e.g. "Charging (xx%)") → unplug → reopen the app to show the session logged. Upload to YouTube as **Unlisted** (or Google Drive "anyone with the link") and paste the link. |

Manifest already contains the required subtype property:
`android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "Real-time continuous battery health and charge cycle logging"`.

## 6. Closed testing (required for new personal accounts)

1. Testing → Closed testing → Create track → upload `app-play-release.aab`.
2. Testers: create an email list with **at least 12 (aim for 15–20)** Gmail addresses.
3. Release notes: `First test release of VoltBuddy.`
4. Send testers the opt-in link. Each tester must open it, tap **Become a tester**, then install
   from the Play Store link and **keep it installed for 14 days in a row**.
5. After 14 days with ≥ 12 opted-in testers: Dashboard → **Apply for production**.

Testers install from the Play Store: no "unknown app" warning.

## 7. Before every upload

- `versionCode` (the number after `+` in `pubspec.yaml`) must be higher than the last upload.
- Build with `--flavor play`. A `--flavor study` build has the wrong app ID and would be rejected.
- Check the package and key: `aapt dump badging app-play-release.apk | head -1` → `com.voltbuddy.app`.

## 8. Privacy policy (host on Google Sites or Google Docs → Publish to web)

```
VoltBuddy Privacy Policy
Last updated: [DATE]

VoltBuddy ("the app") is developed by [YOUR NAME] as part of a university Human–Computer Interaction research project.

What the app stores
The app records your phone's battery level, charging state and charger type to create a history of your charging sessions, and saves your in-app settings (chosen pet and language). This data is stored only on your device.

What the app does not do
The app does not create an account, does not collect your name, contacts, location, photos or messages, has no advertising, and does not use analytics or tracking services. The app does not send your data to us or to any third party.

Exporting your data
If you tap "Share CSV", the app creates a file with your charging history and opens Android's share menu. You choose where the file goes; the app does not send it anywhere on its own.

Permissions
- Notifications: to show the ongoing battery notification and the 85% unplug reminder.
- Foreground service and start at boot: to keep recording charging sessions when the app is closed and after the phone restarts.
- Internet: used only to download the app's fonts.

Deleting your data
Use Logs → Clear All in the app, or uninstall the app, to delete all stored data.

Children
The app is not directed at children under 13.

Contact
[YOUR EMAIL]
```
