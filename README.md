# ⚡ VoltBuddy

**A premium, Neo-brutalist Flutter companion app that gamifies your battery charging habits, tracks real-time battery diagnostics, and features a responsive pet that vibes with your battery health.**

---

## 📸 Screenshots

| Drip & Vibe Stage | receipts (Logs Tab) | vibe map (Receipts Tab) |
| :---: | :---: | :---: |
| *Add home_screen.png here* | *Add receipts.png here* | *Add heatmap.png here* |
| <!-- Placeholder for Home Screen Screenshot --> | <!-- Placeholder for Logs Tab Screenshot --> | <!-- Placeholder for Heatmap Screenshot --> |

---

## 📖 Table of Contents
1. [Overview](#-overview)
2. [Premium Features](#-premium-features)
3. [Architecture & Folder Structure](#-architecture--folder-structure)
4. [Core Systems](#-core-systems)
   - [Offline Checkpoint & Real Tracking Engine](#offline-checkpoint--real-tracking-engine)
   - [RPG Vibe & Clout Progression](#rpg-vibe--clout-progression)
   - [Localization & Slang Engine](#localization--slang-engine)
   - [Gemini AI Companion Integration](#gemini-ai-companion-integration)
5. [Getting Started](#-getting-started)
6. [How to Run & Test on Real Devices](#-how-to-run--test-on-real-devices)
7. [Database Schema](#-database-schema)
8. [Dependencies](#-dependencies)

---

## 🌟 Overview

**VoltBuddy** turns boring battery health parameters into a gamified, visual experience. By monitoring battery level and charging states dynamically, it converts your phone's battery into a digital pet's life force (**HP**). 

Good habits (keeping charges between 20% and 85%) earn your pet **XP/Clout**, unlocking rank promotions. Bad habits (leaving it plugged in past 95% or letting it drop below 10%) deal damage to your pet's HP, making them tired or sick.

---

## ✨ Premium Features

- **Neo-Brutalist RPG Aesthetics:** Bold borders, curated HSL color themes, shadow offsets, and clean, responsive layouts designed with maximum visual excellence.
- **Dynamic Pet Companionship:** Choose your companion (**Kitty**, **Doggo**, or **Bunbun**) and watch them react visually to charging states and overall battery health.
- **Real-Time Database Tracking:** Automatic, offline background session capturing. VoltBuddy logs completed charging cycles (duration, start/end level, date) even when the app is suspended.
- **Vibe Map (Heatmap Grid):** A beautiful, responsive 7-week charging quality heatmap showing daily charge scores, perfect sessions, and penalties.
- **Gemini AI Integration:** Your pet speaks! Ask for advice or perform "Vibe Checks" to trigger AI-generated slang reviews and actionable charging tips in the pet's voice.
- **Localization Engine:** Seamlessly toggle between **REGULAR** English and **GEN Z** slang mode ("Bussin", "Down Bad", "W Charge").
- **Developer Sandbox:** Unlock developer controls to test ranks, trigger manually simulated charges, or force pet health status (Thriving, Tired, Sick) for quick styling validation.

---

## 🏗️ Architecture & Folder Structure

VoltBuddy uses a clean, modular structure:

```
lib/
├─ background/           # Background schedule integration
│  ├─ battery_task.dart       // Runs background task collection
│  └─ schedule_battery.dart  // Periodically schedules Workmanager
├─ data/                 # SQLite storage layer
│  └─ battery_db.dart         // Handles BatteryRecords and ChargeSessions
├─ models/               # Shared logic data structures
│  └─ simulation_models.dart  // ChargeSession, DailyMetrics, WeeklyMetrics
├─ services/             # Core service integrations
│  ├─ gemini_service.dart     // Google Gemini AI API integration
│  └─ localization_service.dart// Gen Z / Regular localization handling
├─ ui/                   # Layouts and screen wrappers
│  └─ not_enough_data.dart   // Informative startup layout
├─ widgets/              # Premium visual controls
│  ├─ heatmap_widget.dart     // Compounded charging quality calendar
│  ├─ journey_map_widget.dart // Linear progression timeline nodes
│  ├─ neo_brutalist.dart      // NeoButton, NeoCard, custom styles
│  └─ pet_renderer.dart       // Animated pet canvas rendering
└─ main.dart             # App entry, state binding, and core UI tabs
```

---

## ⚙️ Core Systems

### Offline Checkpoint & Real Tracking Engine
VoltBuddy listens to foreground battery state changes via `battery_plus` streams, but also manages suspension.
When the app goes to the background:
1. It saves a `BatteryRecord` checkpoint in the database.
2. Upon resuming (foreground launch or startup), it checks if the battery level has risen.
3. If it increased while offline, VoltBuddy retrospectively calculates and registers the completed `ChargeSession` (start/end level, duration, date), ensuring no charging data goes unrecorded.

### RPG Vibe & Clout Progression
Your pet progresses through **7 ranks** (from *NPC/Recruit* up to *GOAT/Emperor*). Ranks are calculated dynamically based on historical sessions stored in the local DB:
- **Perfect Charge (+30 XP, +5 HP):** Battery started charging $\ge 20\%$ and stopped $\le 85\%$.
- **Overcharge Penalty (+5 XP, -15 HP):** Charger left connected $\ge 95\%$.
- **Critical Starvation (+10 XP, -10 HP):** Battery dropped $< 10\%$ before plugging in.

### Localization & Slang Engine
A custom localization translator switches strings between formal English and Gen Z slang on the fly. 
- *Regular:* "Standard Charge", "Battery Health (HP)", "Stars"
- *Gen Z:* "It's giving charge", "Battery Vibes (HP)", "Vibes"

### Gemini AI Companion Integration
Uses the Google Gemini API to generate personalized quotes. The pet uses the correct persona matching its current species, rank, and health state (e.g. Gen Z slang or simple caveman).

---

## 🚀 Getting Started

### 📋 Prerequisites
- Flutter SDK (>= 3.10)
- Android SDK (for Workmanager and local builds)
- Gemini API Key (stored or referenced inside the app configuration)

### 💻 Installation
1. **Clone the repository:**
   ```bash
   git clone https://github.com/SakinaKheraj/voltbuddy.git
   cd voltbuddy
   ```
2. **Install Dart packages:**
   ```bash
   flutter pub get
   ```
3. **Build or run:**
   ```bash
   flutter run
   ```

---

## 📱 How to Run & Test on Real Devices
To verify the background offline tracking on a real Android/iOS device:

1. **Enable Developer Options & USB Debugging** on your phone.
2. **Connect via USB** to your computer.
3. **Verify the device is detected:**
   ```bash
   flutter devices
   ```
4. **Run the app directly in Profile or Release mode:**
   ```bash
   flutter run -d <your-device-id>
   ```
5. **Simulate Offline Charging:**
   - With the app running, disconnect the USB cable.
   - Charge your device using a regular wall charger for a few percent.
   - Re-connect your device to the computer and open the app.
   - The app will retrieve the offline checkpoint, calculate the charge gap, insert the session, and animate Sparky's power absorption with XP/HP rewards!

---

## 🗄️ Database Schema

VoltBuddy uses an SQLite database (`sqflite`) with two primary tables:

### `battery_data`
Tracks periodic logs (timestamp, level, charging status) used for state checks and background history.
```sql
CREATE TABLE battery_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  level INTEGER NOT NULL,
  isCharging TEXT NOT NULL
);
```

### `charge_sessions`
Tracks fully finalized charging sessions used to calculate metrics, XP, and render the vibe maps.
```sql
CREATE TABLE charge_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  start_pct INTEGER NOT NULL,
  start_date TEXT NOT NULL,
  start_time TEXT NOT NULL,
  end_pct INTEGER NOT NULL,
  end_date TEXT NOT NULL,
  end_time TEXT NOT NULL
);
```

---

## 📦 Dependencies

The core modules that power VoltBuddy include:
- `battery_plus` — Native device battery streams & levels.
- `sqflite` & `path` — SQLite storage engine.
- `google_fonts` — Premium typography rendering.
- `google_generative_ai` — Gemini API integration.
- `workmanager` — Periodic background collection triggers.
