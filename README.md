# VoltBuddy

**A Flutter app that visualises your phone's charging habits using a friendly pet animation.**

---

## Table of Contents
1. [Overview](#overview)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Getting Started](#getting-started)
5. [Running the App](#running-the-app)
6. [Background Data Collection](#background-data-collection)
7. [Database Schema](#database-schema)
8. [UI Flow](#ui-flow)
9. [Dependencies](#dependencies)
10. [Project Structure](#project-structure)
11. [Contributing](#contributing)
12. [License](#license)

---

## Overview
VoltBuddy monitors battery level and charging state in the background, stores the data locally in an SQLite database, and displays a cute pet animation that reacts to the collected data. The app shows a placeholder screen until enough data (two entries) is gathered.

---

## Features
- **Background data collection** using `workmanager` (every 15 minutes on Android).
- **Local persistence** with `sqflite` & `path` – stores `BatteryRecord` entries.
- **Dynamic UI** – `HomePage` decides whether to show the placeholder `NotEnoughDataScreen` or the real `PetRenderer`.
- **Pet renderer** – reusable widget that displays a pet (cat/dog/rabbit) with optional glow effect.
- **Clean, feature‑first folder structure** (`background/`, `data/`, `ui/`).
- **Scalable architecture** – easy to add more sensors or UI screens.

---

## Architecture
```
lib/
├─ background/          # Workmanager integration
│   ├─ battery_task.dart      // collectBatteryData()
│   └─ schedule_battery.dart // scheduleBatteryBackground()
├─ data/                # SQLite helper
│   └─ battery_db.dart        // BatteryDb class (insert, count, getAll)
├─ ui/                  # UI components
│   ├─ home_page.dart        // FutureBuilder wrapper
│   └─ not_enough_data.dart  // Placeholder screen with PetRenderer overlay
├─ main.dart            # App entry – registers Workmanager & HomePage
└─ widgets/             # Existing widgets (PetRenderer, etc.)
```
The **callbackDispatcher** defined in `main.dart` delegates to `collectBatteryData()`. The periodic job is registered once at startup via `scheduleBatteryBackground()`.

---

## Getting Started
1. **Prerequisites**
   - Flutter SDK (≥3.10)
   - Android SDK (for Workmanager) – iOS not required for now.
2. **Clone the repo**
   ```bash
   git clone https://github.com/your-org/voltbuddy.git
   cd voltbuddy
   ```
3. **Install dependencies**
   ```bash
   flutter pub get
   ```
4. **Run the app**
   ```bash
   flutter run
   ```

---

## Running the App
- On first launch the app shows **"Collecting data…"** overlay until at least two `BatteryRecord` entries exist in the database.
- After enough data, the placeholder disappears and the main `PetRenderer` UI becomes visible.
- Background collection continues even when the app is closed (Android only).

---

## Background Data Collection
- **Workmanager** registers `batteryBackground` task (15 min interval).
- The `callbackDispatcher` invokes `collectBatteryData()` which:
  1. Reads battery level & charging state via `battery_plus`.
  2. Persists a `BatteryRecord(timestamp, level, isCharging)` using `BatteryDb.insertRecord`.
- The task is initialized in `main()` before `runApp()`.

---

## Database Schema
```sql
CREATE TABLE battery_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  level INTEGER NOT NULL,
  isCharging INTEGER NOT NULL
);
```
- **BatteryDb** provides:
  - `Future<void> insertRecord(BatteryRecord record)`
  - `Future<int> count()` – used by `HomePage` to decide UI.
  - `Future<List<BatteryRecord>> getAll()` – available for future analytics.

---

## UI Flow
1. **HomePage** (uses `FutureBuilder<int>` on `BatteryDb().count()`).
2. If `count < 2` → display `NotEnoughDataScreen`:
   - Shows a semi‑transparent overlay with the text *“Collecting data…”*.
   - Renders the default `PetRenderer` underneath.
3. When enough data → displays the regular `PetRenderer` (or any other main UI you add).

---

## Dependencies
| Package | Reason |
|---------|--------|
| `workmanager` | Schedule periodic background jobs (Android) |
| `sqflite` | SQLite database handling |
| `path` | Resolve file paths for the database |
| `battery_plus` | Access battery level & charging state |
| `google_fonts` | Modern typography |
| `flutter` (sdk) | Core framework |

---

## Project Structure
```
android/            # Android native files (Workmanager setup)
ios/                # Placeholder – not used yet
lib/
  background/       # Background task & scheduler
  data/             # SQLite helper
  ui/               # Screens (HomePage, placeholder)
  widgets/          # Re‑usable UI widgets (PetRenderer, etc.)
  main.dart         # App entry point & Workmanager init
pubspec.yaml        # Dependencies
README.md           # This file
```
Keep new features in their own folders to maintain a clean, feature‑first layout.

---

## Contributing
Contributions are welcome! Please follow these steps:
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/your‑feature`).
3. Ensure the code follows the existing architecture and runs `flutter test` (if tests exist).
4. Submit a Pull Request with a clear description.

---

## License
This project is licensed under the **MIT License** – see the `LICENSE` file for details.
