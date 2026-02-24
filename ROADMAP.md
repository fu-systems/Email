# Look In - Project Roadmap

> **Linux Desktop Email Client** built with Flutter, inspired by Microsoft Outlook 2013.
> Last updated: 2026-02-24

---

## Project Progress Overview

```
Phase 1: Core Architecture          [##########] 100%  COMPLETE
Phase 2: Email Module               [##########] 100%  COMPLETE
Phase 3: Calendar & Contacts Views  [##########] 100%  COMPLETE  <-- current
Phase 4: Ribbon & UI Wiring         [##########] 100%  COMPLETE
Phase 5: Linux Platform & Build     [----------]   0%  PLANNED
Phase 6: Persistence & Offline      [#---------]  10%  PLANNED
Phase 7: Advanced Features          [----------]   0%  FUTURE
```

---

## Phase 1: Core Architecture — COMPLETE

Foundational layers: project setup, data models, state management, services, and theming.

| Task | File(s) | Status |
|------|---------|--------|
| Flutter project scaffold | `pubspec.yaml`, `main.dart`, `app.dart` | Done |
| Outlook 2013 theme system | `lib/theme/outlook_theme.dart` | Done |
| Email Account model + provider detection | `lib/models/email_account.dart` | Done |
| Email Message model + serialization | `lib/models/email_message.dart` | Done |
| Mailbox Folder model + type detection | `lib/models/folder.dart` | Done |
| Contact model + address/phone types | `lib/models/contact.dart` | Done |
| Calendar Event model + recurrence/reminders | `lib/models/calendar_event.dart` | Done |
| Navigation state (Mail/Calendar/Contacts) | `lib/providers/navigation_provider.dart` | Done |
| Account persistence (SharedPreferences) | `lib/providers/account_provider.dart` | Done |
| Mail state management (folders, messages) | `lib/providers/mail_provider.dart` | Done |
| Calendar state management (events, nav) | `lib/providers/calendar_provider.dart` | Done |
| Contacts state management (search, filter) | `lib/providers/contacts_provider.dart` | Done |
| IMAP/SMTP email service (enough_mail) | `lib/services/email_service.dart` | Done |
| In-memory data cache | `lib/services/database_service.dart` | Done |

---

## Phase 2: Email Module — COMPLETE

Full email experience: three-pane layout, compose, reply/forward, flags, search.

| Task | File(s) | Status |
|------|---------|--------|
| Main app layout (title bar + ribbon + content + status) | `lib/screens/home_screen.dart` | Done |
| Ribbon toolbar widget (tabs, groups, buttons) | `lib/widgets/ribbon/ribbon_toolbar.dart` | Done |
| Mail three-pane layout | `lib/screens/mail/mail_view.dart` | Done |
| Folder sidebar with tree + unread counts | `lib/widgets/folder_pane.dart` | Done |
| Message list with previews + flags | `lib/widgets/message_list.dart` | Done |
| Reading pane with header + body + attachments | `lib/widgets/reading_pane.dart` | Done |
| Compose screen (new, reply, reply all, forward) | `lib/screens/mail/compose_screen.dart` | Done |
| Navigation bar (Mail/Calendar/People tabs) | `lib/widgets/navigation_bar.dart` | Done |
| Status bar (sync status, message count) | `lib/widgets/status_bar.dart` | Done |

---

## Phase 3: Calendar & Contacts Views — COMPLETE

Calendar and contacts screens that plug into the existing provider layer.

| Task | File(s) | Status |
|------|---------|--------|
| Account setup wizard (first-run + settings) | `lib/screens/settings/account_setup_screen.dart` | Done |
| Calendar view (month grid + event list + dialogs) | `lib/screens/calendar/calendar_view.dart` | Done |
| Contacts view (list + alphabet index + detail pane) | `lib/screens/contacts/contacts_view.dart` | Done |

---

## Phase 4: Ribbon & UI Wiring — COMPLETE

Connect all ribbon buttons and UI callbacks to their provider actions.

| Task | File(s) | Status |
|------|---------|--------|
| Mail ribbon: New Email, Delete, Reply, Reply All, Forward | `home_screen.dart` | Done |
| Mail ribbon: Send/Receive All Folders, Unread, Flag | `home_screen.dart` | Done |
| Calendar ribbon: New Appointment | `home_screen.dart` | Done |
| Calendar ribbon: Today, Day/Week/Month view toggle | `home_screen.dart` | Done |
| Contacts ribbon: New Contact | `home_screen.dart` | Done |
| Contacts ribbon: Delete contact | `home_screen.dart` | Done |
| Mail ribbon: Move to folder dialog | `home_screen.dart` | Done |
| Mail ribbon: New Folder dialog (placeholder) | `home_screen.dart` | Done |
| Mail ribbon: Rules (placeholder snackbar) | `home_screen.dart` | Done |
| View ribbon: Reading Pane toggle | `home_screen.dart`, `mail_provider.dart`, `mail_view.dart` | Done |
| View ribbon: Folder Pane toggle | `home_screen.dart`, `mail_provider.dart`, `mail_view.dart` | Done |
| Navigation bar overflow popup menu | `navigation_bar.dart` | Done |
| File tab: Account management backstage view | `home_screen.dart` | Pending |

---

## Phase 5: Linux Platform & Build — PLANNED

Generate Flutter Linux desktop runner files so the app can compile and run natively.

| Task | File(s) | Status |
|------|---------|--------|
| CMake top-level config | `linux/CMakeLists.txt` | Pending |
| GTK application entry point | `linux/main.cc` | Pending |
| Flutter GTK embedder | `linux/my_application.h`, `linux/my_application.cc` | Pending |
| Flutter plugin integration | `linux/flutter/CMakeLists.txt` | Pending |
| Verify `flutter build linux` succeeds | — | Pending |
| Desktop window sizing (1200x800 default) | `linux/my_application.cc` | Pending |

---

## Phase 6: Persistence & Offline — PLANNED

Replace in-memory DataCache with SQLite for data that survives restarts.

| Task | File(s) | Status |
|------|---------|--------|
| Define Drift database tables (accounts, messages, contacts, events) | `database_service.dart` | Pending |
| Migrate AccountProvider from SharedPreferences to Drift | `account_provider.dart` | Pending |
| Cache fetched messages locally | `mail_provider.dart`, `database_service.dart` | Pending |
| Persist calendar events to SQLite | `calendar_provider.dart` | Pending |
| Persist contacts to SQLite | `contacts_provider.dart` | Pending |
| Secure credential storage (encrypt package) | `account_provider.dart` | Pending |
| Offline mode indicator in status bar | `status_bar.dart` | Pending |

---

## Phase 7: Advanced Features — FUTURE

Feature parity with Outlook 2013 and beyond.

| Task | Priority | Status |
|------|----------|--------|
| HTML email rendering (flutter_html) | High | Pending |
| Attachment download/save (file_picker) | High | Pending |
| Keyboard shortcuts (Ctrl+N, Ctrl+R, Delete) | High | Pending |
| Right-click context menus | Medium | Pending |
| Drag-and-drop message moving | Medium | Pending |
| Email signature editor | Medium | Pending |
| POP3 protocol support | Medium | Pending |
| Email rules and filters | Medium | Pending |
| Contact groups / distribution lists | Medium | Pending |
| Calendar invites (iCal parsing) | Medium | Pending |
| Recurring event expansion | Medium | Pending |
| Multi-account folder tree | Medium | Pending |
| Search across all folders | Medium | Pending |
| Print support | Low | Pending |
| Import/export (CSV, ICS) | Low | Pending |
| System tray & desktop notifications | Low | Pending |

---

## Architecture Reference

```
lib/
├── main.dart                          # Entry point
├── app.dart                           # MaterialApp + Provider setup + routing
├── theme/
│   └── outlook_theme.dart             # Colors, text styles, ThemeData
├── models/
│   ├── email_account.dart             # Account + provider auto-detection
│   ├── email_message.dart             # Message + EmailAddress + Attachment
│   ├── folder.dart                    # MailFolder + type detection
│   ├── contact.dart                   # Contact + email/phone/address
│   └── calendar_event.dart            # Event + category + recurrence
├── providers/
│   ├── navigation_provider.dart       # Section switching
│   ├── account_provider.dart          # Account CRUD + persistence
│   ├── mail_provider.dart             # Mail ops (connect, fetch, send, search)
│   ├── calendar_provider.dart         # Calendar navigation + event CRUD
│   └── contacts_provider.dart         # Contact list, search, filter, CRUD
├── services/
│   ├── email_service.dart             # IMAP/SMTP via enough_mail
│   └── database_service.dart          # DataCache (in-memory) + future Drift
├── screens/
│   ├── home_screen.dart               # Main layout + ribbon configurations
│   ├── mail/
│   │   ├── mail_view.dart             # Three-pane mail interface
│   │   └── compose_screen.dart        # Compose / reply / forward
│   ├── calendar/
│   │   └── calendar_view.dart         # Month grid + event list + editor
│   ├── contacts/
│   │   └── contacts_view.dart         # Contact list + detail + editor
│   └── settings/
│       └── account_setup_screen.dart  # Account wizard (first-run + settings)
└── widgets/
    ├── ribbon/
    │   └── ribbon_toolbar.dart        # Outlook ribbon component
    ├── folder_pane.dart               # Folder tree sidebar
    ├── message_list.dart              # Message list with previews
    ├── reading_pane.dart              # Message reader
    ├── navigation_bar.dart            # Bottom nav (Mail/Calendar/People)
    └── status_bar.dart                # Bottom status bar
```

---

## Dependencies

| Package | Purpose | Used |
|---------|---------|------|
| `provider` | State management | Yes |
| `enough_mail` | IMAP/SMTP protocol | Yes |
| `shared_preferences` | Account persistence | Yes |
| `uuid` | Unique ID generation | Yes |
| `intl` | Date/number formatting | Yes |
| `table_calendar` | Calendar month grid | Yes |
| `flutter_html` | HTML email rendering | Not yet |
| `drift` + `sqlite3_flutter_libs` | Local database | Not yet |
| `file_picker` | Attachment save dialog | Not yet |
| `encrypt` | Credential encryption | Not yet |
