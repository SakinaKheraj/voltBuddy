# VoltBuddy Phase 2 — Interaction Tracking Codebook

App version `2.2.1+6` (earlier pilot exports show `2.1.x` / `2.2.0`). This describes `interaction_logs_<ParticipantID>.csv`, exported next to
`charge_logs_<ParticipantID>.csv` from the Logs tab (**Share CSV**).

## How data is collected

- Events are stored **only on the participant's phone** in a separate SQLite file
  (`interaction_events.db`). Nothing is uploaded. "Clear All Data" does not erase events.
- Two sources:
  - `app` — logged by the Flutter UI while the app is open.
  - `native` — logged by the Android background service, even when the app is closed
    (plug / unplug / "85% reached" notification). Imported into the app the next time it opens.
- No text content, other apps, contacts or location are collected.
- Tracking can be disabled at build time: `flutter build apk --dart-define=VB_TRACKING=false`.

## File format

Lines starting with `#` are metadata (participant ID, install ID, device, export time).
Then one header row and one row per event.

| Column | Meaning |
|---|---|
| `participant_id` | Student ID typed by the participant on first launch of v2.1 |
| `install_id` | Random ID created on first launch of v2.1 (survives ID edits) |
| `event_id` | Insert order on the device. **Sort by `ts_utc_ms` for time order** (taps are logged ~0.4 s after they happen, with their real time) |
| `launch_id` | Changes every time the app process starts (cold start) |
| `session_id` | One foreground visit: `<launch_id>-<n>`. Empty for `native` events |
| `session_seq` | Counter within the session (gaps = lost rows) |
| `source` | `app` or `native` |
| `ts_utc_ms` | Event time, Unix epoch milliseconds |
| `ts_local` | Same time in the phone's local time with UTC offset |
| `mono_ms` | Milliseconds since app process start (monotonic; unaffected by clock changes, but **pauses while the phone sleeps** — use `ts_utc_ms` for gaps between sessions) |
| `event` | Event name (see below) |
| `user_action` | `1` = caused directly by the participant; `0` = shown by the app / system |
| `tab` | Tab selected at that moment: `tab-stats`, `tab-tips`, `tab-data` (Logs), `tab-sandbox` (Dev) |
| `target` | What the event is about (tab id, species, persona, zone, …) |
| `props` | JSON with event-specific fields |
| `battery_pct`, `battery_state`, `is_charging` | Battery state known to the app at that moment (empty until the first reading) |
| `persona`, `species` | Current language persona and pet |
| `hp`, `xp`, `rank_index` | Pet values **as displayed** (heatmap day previews temporarily change them) |
| `app_version` | App version that logged the event |

## Events

### App sessions
| Event | user_action | props |
|---|---|---|
| `app_opened` | 0 | `cold_start`, `launch_source` (`notification` / `launcher_or_recents`) |
| `app_foregrounded` | 0 | `bg_duration_ms` (wall clock; pilot builds before 2.1.2 undercounted it while the phone slept), `launch_source` |
| `app_backgrounded` | 0 | `fg_duration_ms` (length of this foreground session) |

### Navigation and attention
| Event | user_action | props |
|---|---|---|
| `tab_selected` | 1 | target = tab tapped; `from`, `changed` |
| `tab_entered` | 0 | `reason`: `launch` / `switch` / `resume` |
| `tab_left` | 0 | `reason`: `switch` / `background`; `duration_ms`, `max_scroll_px`, `scroll_extent_px` |
| `tab_content_seen` | 0 | target = tab; `duration_ms` the tab's content had ≥ 100 px on screen and was not covered by the mission brief or a dialog; `max_visible_px` |
| `scrolled` | 1 | `from_px`, `to_px`, `extent_px`, `viewport_px`, `duration_ms` |
| `overlay_opened` / `overlay_closed` | 0 | target = `dialog` / `menu`; `open_ms` on close |

### Feature use
| Event | user_action | props |
|---|---|---|
| `mission_brief_shown` | 0 | target = quest title; `score`, `log_count` |
| `mission_brief_dismissed` | 1 | `visible_ms` |
| `talk_tapped` | 1 | — |
| `talk_response` | 0 | `outcome`: `ok` / `key_missing` / `error`; `latency_ms` |
| `advice_generated` | 1 | `score`, `has_enough_data`, `total_sessions` |
| `species_selected` | 1 | target = species; `from`, `changed` |
| `persona_menu_opened` | 1 | — |
| `persona_selected` | 1 | target = persona; `from`, `changed` |
| `heatmap_day_opened` | 1 | target = date; `sessions`, `avg_score` |
| `heatmap_day_closed` | 1 | target = date; `open_ms` |
| `heatmap_mode_selected` | 1 | target = mode; `from`, `changed` |
| `log_card_toggled` | 1 | `index`, `expanded`, `session_date` |
| `export_tapped` | 1 | `already_running` (repeat taps while an export is open are ignored) |
| `export_result` | 0 | `status` (`success` / `dismissed` / `unavailable` / `error`), `files`, `charge_sessions`, `csv_lines` |
| `clear_dialog_opened` | 1 | — |
| `clear_dialog_closed` | 1 | `result`: `confirmed` / `cancelled` / `dismissed`; `open_ms` |
| `rank_badge_tapped` | 1 | `count` (5 taps unlock Dev tab) |
| `sandbox_unlocked` | 0 | — |
| `sandbox_action` | 1 | target = `good_charge` / `overcharge` / `force_state` / `set_rank`; `value` |
| `participant_id_prompt_shown` | 0 | `first_time` |
| `participant_id_saved` | 1 | `first_time`, `changed` |
| `participant_id_prompt_closed` | 1 | closed without saving (edit only) |

### Feedback shown by the app (exposures)
| Event | user_action | props |
|---|---|---|
| `unplug_nudge_shown` | 0 | In-app 85% warning. `level`, `severity` (`target` ≥ 85 %, `high` ≥ 95 %) |
| `session_feedback_shown` | 0 | Reaction to a newly logged charge. `kind` (`reward` / `risk` / `logged`), `start_pct`, `end_pct`, `start`, `end` |
| `charge_state_observed` | 0 | App saw charging start/stop while open. `charging`, `level`, `state`, `first_reading` |

### Native (background service)
| Event | props |
|---|---|
| `native_power_connected` | `level`, `state` (`connected`), `plugged_source` (often `none`: Android's plug-in signal has no charger type — use the value on `native_power_disconnected`), `temp_c` |
| `native_unplug_nudge_posted` | Notification text changed to "85% Target Reached! Unplug soon". Once per charge. `level`, `start_pct`, `temp_c`, `screen_on` and `locked` (was the phone in use at that moment) |
| `native_screen_on_after_nudge` | First time the screen turned on after the nudge, during the same charge. `level` |
| `native_unlock_after_nudge` | First unlock after the nudge, during the same charge. `level` |
| `native_power_disconnected` | `level`, `state` (`disconnected`), `plugged_source` (charger type for the whole charge, from 2.2.1), `start_pct`, `start_ts`, `nudge_posted`, `temp_c` |
| `native_heartbeat` | Once per day while the background service runs. `level`, `state` + device status fields |
| `native_service_started` / `native_service_stopped` | Background service started (incl. restarts after being killed) / stopped. Started includes device status fields |
| `native_boot_completed` | Phone restarted |

Screen state is recorded **only** between the 85% notification and unplugging, and only the first
screen-on and first unlock per charge. No other phone use is recorded.

### Device status
| Event | props |
|---|---|
| `device_status` | Logged on app start, and on later opens only if something changed (`changed`). `notifications_enabled` (app notifications allowed), `monitor_channel_enabled` (the VoltBuddy notification channel is not switched off), `battery_unrestricted` (exempt from battery optimisation, i.e. "Unrestricted"), `background_restricted` (Android "Restricted" background mode) |

If `notifications_enabled` or `monitor_channel_enabled` is false, the 85% notification could not be
seen — exclude those charges from nudge-effect analyses.

### Raw taps
| Event | props |
|---|---|
| `tap` | target = zone (`header`, `pet_stage`, `pet_details`, `progress_bars`, `tab_bar`, `tab_content`, `mission_brief`, `heatmap_popover`, `dialog`, `menu`, `outside`); `x`, `y`, `screen_w`, `screen_h` (logical px); `hold_ms`; `scroll_px`; `content_y`, `content_h` (within tab content); **`handled`** and `handled_by` |

`handled = false` is a **dead tap**: no user action was logged between the finger touching down and
250 ms after it lifted (or the next touch, if sooner), i.e. the participant tapped something that
does not respond. A touch that
stops a moving list counts as handled (`handled_by = scroll_stop`). Closing a menu or dialog by tapping outside it counts as
handled (`handled_by = overlay_closed`). Drags/scrolls and presses longer than 600 ms are not taps.

## Suggested derived measures

- **Session length**: `fg_duration_ms` of `app_backgrounded`. Merge sessions separated by short
  background gaps (`bg_duration_ms`) at 15 / 30 / 60 s as a sensitivity analysis.
- **Micro-usage**: share of sessions under 15 s (Ferreira et al., 2014).
- **Time per tab**: sum `tab_left.duration_ms` by `target`; attention-adjusted: `tab_content_seen`.
- **Nudge → unplug latency**: for each charge, `native_power_disconnected.ts_utc_ms −
  native_unplug_nudge_posted.ts_utc_ms`; compare charges with and without a nudge
  (`nudge_posted`). Also check whether the app was opened between the two.
- **Could the nudge be seen?** `screen_on` at the nudge, time to `native_screen_on_after_nudge` /
  `native_unlock_after_nudge`, and `notifications_enabled` from the latest `device_status` /
  `native_heartbeat`.
- **Tracking coverage**: days with a `native_heartbeat` ÷ study days; service restarts per week.
- **Notification-driven opens**: `launch_source = notification`.
- **Engagement over time**: active days, sessions/day, feature events per week.
- **Dead-tap rate** by zone.

## Known limitations

- Native events exist only while the background service runs; if the OS kills it, plug/unplug
  events can be missing (charge sessions are still captured by the Phase 1 mechanism).
- The background notification is silent and low-priority: `native_unplug_nudge_posted` means
  the message was **posted**, not that the participant saw it.
- If Android kills the app while it is open, no `app_backgrounded` is written; treat the last
  event of the session as its end.
- Visibility is sampled about every 0.5 s.
- `app_version` on `native` rows is the version of the background service that recorded the event
  (from 2.2.1). Earlier native rows show the version of the app that imported them.
- `export_result.status = unavailable` means Android did not report what happened in the share
  sheet (common on Android); it does not mean the export failed.
- **Phase 1 `Power Source` column is unreliable:** before 2.2.1 the charger type was taken from
  Android's plug-in signal, which has none, so most Phase 1 sessions show `none`.
- `export_result` is logged after the share sheet closes, so it appears in the *next* export,
  not in the file being shared.
- Expanded log cards collapse when the app refreshes its data (every ~10 s while open;
  Phase 1 behaviour, unchanged), so `log_card_toggled` collapses may be under-counted.
- `persona` and `species` are now saved between launches (they reset to Gen Z / Cat in Phase 1).
