# Look In - Project Roadmap

> **Linux Desktop Email Client** built with Flutter, inspired by Microsoft Outlook 2013.
> Last updated: 2026-09-27

---

## Project Progress Overview

```
Phase 1: Core Architecture          [##########] 100%  COMPLETE
Phase 2: Email Module               [##########] 100%  COMPLETE
Phase 3: Calendar & Contacts Views  [##########] 100%  COMPLETE
Phase 4: Ribbon & UI Wiring         [##########] 100%  COMPLETE
Phase 5: Linux Platform & Build     [##########] 100%  COMPLETE
Phase 6: Persistence & Offline      [##########] 100%  COMPLETE
Phase 7: Advanced Features          [##########] 100%  COMPLETE
Phase 8: Next                       [#######---]  70%  IN PROGRESS  <-- current
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
| IMAP/SMTP email service (enough_mail) | `lib/services/mail_backend.dart` (was `email_service.dart`) | Done |
| In-memory data cache | `lib/services/data_store.dart` (now backed by SQLite) | Done |

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
| Mail ribbon: New Folder dialog | `home_screen.dart`, `mail_dialogs.dart` | Done |
| Mail ribbon: Rules (create rule, manage rules, run now) | `home_screen.dart`, `mail_dialogs.dart` | Done |
| View ribbon: Reading Pane toggle | `home_screen.dart`, `mail_provider.dart`, `mail_view.dart` | Done |
| View ribbon: Folder Pane toggle | `home_screen.dart`, `mail_provider.dart`, `mail_view.dart` | Done |
| Navigation bar overflow popup menu | `navigation_bar.dart` | Done |
| File tab: backstage (Info, Open & Export, Options, About, Exit) | `lib/screens/backstage/backstage_view.dart` | Done |
| Send/Receive, Folder and View ribbon tabs | `home_screen.dart` | Done |

---

## Phase 5: Linux Platform & Build — COMPLETE

| Task | File(s) | Status |
|------|---------|--------|
| CMake top-level config | `linux/CMakeLists.txt` | Done |
| GTK application entry point | `linux/runner/main.cc` | Done |
| Flutter GTK embedder (title, 1200x800 default, 960x600 minimum, icon) | `linux/runner/my_application.cc` | Done |
| Flutter plugin integration | `linux/flutter/CMakeLists.txt` | Done |
| `flutter build linux --release` succeeds | — | Done |
| Desktop entry and install script | `packaging/` | Done |

---

## Phase 6: Persistence & Offline — COMPLETE

| Task | File(s) | Status |
|------|---------|--------|
| SQLite schema with migrations (accounts, folders, messages, contacts, groups, events, rules, outbox, settings) | `database_service.dart` | Done |
| Migrate accounts and data from SharedPreferences | `data_store.dart` | Done |
| Cache folders, messages, bodies and raw MIME locally | `mail_provider.dart`, `data_store.dart` | Done |
| Persist calendar events | `calendar_provider.dart` | Done |
| Persist contacts and contact groups | `contacts_provider.dart` | Done |
| Encrypted credential storage (AES-256-GCM, 0600 key file) | `credential_store.dart` | Done |
| Offline indicator, Work Offline, pending changes and Outbox in the status bar | `status_bar.dart` | Done |
| Offline queue for flags, moves and deletes; Outbox for mail sent offline | `mail_provider.dart` | Done |

Deviation: the plan named Drift. The plain `sqlite3` package was used instead
(JSON documents plus indexed columns), which avoids code generation and bundles
SQLite through its build hook.

---

## Phase 7: Advanced Features — COMPLETE

| Task | Priority | Status |
|------|----------|--------|
| HTML email rendering (flutter_html) with sanitizing and blocked remote pictures | High | Done |
| Attachment open / save / save all (portal, zenity, kdialog or built-in dialog) | High | Done |
| Keyboard shortcuts (Outlook set: Ctrl+N/R/F, Delete, Ctrl+Q/U, F9, Ctrl+E …) | High | Done |
| Right-click context menus (messages, folders, contacts, events) | Medium | Done |
| Drag-and-drop message moving | Medium | Done |
| Email signature editor (per account) | Medium | Done |
| POP3 protocol support (leave on server option) | Medium | Done |
| Email rules and filters | Medium | Done |
| Contact groups / distribution lists | Medium | Done |
| Calendar invites (iCal parsing, VTIMEZONE, accept / tentative / decline replies) | Medium | Done |
| Recurring event expansion (DST-safe, until / count / exceptions) | Medium | Done |
| Multi-account folder tree with Favorites | Medium | Done |
| Search across all folders, plus server-side search | Medium | Done |
| Print support (messages, contacts, agenda) | Low | Done |
| Import/export (CSV and vCard contacts, ICS calendar) | Low | Done |
| Desktop notifications (new mail, reminders) | Low | Done |
| System tray icon | Low | Not done (see Phase 8) |

Deviations:
- Printing renders a print-ready HTML page and opens it in the browser. The
  `printing` plugin needs to download PDFium while building, which breaks
  offline and sandboxed builds.
- Notifications go straight to the freedesktop D-Bus service (`dbus`), with no
  extra native plugin.

---

## Phase 8: Next — IN PROGRESS

| Task | Notes |
|------|-------|
| OAuth2 sign-in for Outlook.com / Microsoft 365 (IMAP/SMTP XOAUTH2) | **Done**: bring-your-own Entra registration, see docs/microsoft-app-registration.md |
| Sign in with Google | Needs Google's restricted-scope verification; app passwords work meanwhile |
| Secret Service keyring for passwords and tokens | **Done** (File > Options > Security) |
| CalDAV / CardDAV sync | Calendar and contacts are local, apart from Microsoft accounts |
| Rich-text compose editor | **Done**: flutter_quill, tabbed message ribbon, inline pictures, HTML signatures |
| Compose polish | **Done**: drag-and-drop and pasted attachments/pictures, rich paste, undo send, Delay Delivery, hunspell spell checking (as you type and F7) |
| Mail backend interface + Microsoft Graph mail | **Done**: IMAP/SMTP and Graph behind one interface; delta sync, immutable ids, `$batch`, throttling retries, sendMail; Graph is the default for new Microsoft accounts |
| Microsoft Graph calendar and contacts | **Done**: each Microsoft account's default calendar and contacts folder sync both ways (calendarView and contacts delta, changed fields only, newer change wins); calendar checkboxes and default calendar, address books in People, invitations answered through Graph |
| More Microsoft calendars and contact folders | Other and shared calendars, contact subfolders, contact photos, editing whole recurring series |
| IMAP IDLE push | Sync currently polls on each account's interval |
| System tray icon and single-instance handling (`mailto:` links) | |
| Flatpak / AppImage packaging | |
| Conversation (thread) view | |

---

## Architecture Reference

```
lib/
├── main.dart                          # Entry point, opens the data store
├── app.dart                           # MaterialApp + Provider setup + routing
├── theme/outlook_theme.dart           # Colors, text styles, ThemeData
├── models/
│   ├── email_account.dart             # Account, protocols, provider presets
│   ├── email_message.dart             # Message, EmailAddress, Attachment
│   ├── folder.dart                    # MailFolder, hierarchy, special types
│   ├── contact.dart                   # Contact, ContactGroup
│   ├── calendar_event.dart            # Event, recurrence expansion, reminders
│   ├── mail_rule.dart                 # Rules and their evaluation
│   └── outgoing_message.dart          # Outbox / drafts
├── providers/
│   ├── navigation_provider.dart       # Mail / Calendar / People
│   ├── account_provider.dart          # Account CRUD, default account
│   ├── mail_provider.dart             # Sync, offline queue, send, search, rules
│   ├── calendar_provider.dart         # Views, event CRUD, reminders
│   └── contacts_provider.dart         # Contacts, groups, suggestions
├── services/
│   ├── database_service.dart          # SQLite schema and queries
│   ├── data_store.dart                # Cached, write-through data store
│   ├── credential_store.dart          # AES-GCM password encryption
│   ├── mail_backend.dart              # IMAP / POP3 / SMTP
│   ├── mime_converter.dart            # MIME parse / build
│   ├── ical_service.dart              # iCalendar parse / generate / reply
│   ├── sync/                          # Microsoft calendar and contacts (Graph)
│   ├── contacts_io.dart               # CSV and vCard
│   ├── html_sanitizer.dart            # Safe HTML, quoting
│   ├── autoconfig_service.dart        # ISPDB / autoconfig / MX
│   ├── notification_service.dart      # D-Bus notifications
│   ├── file_dialogs.dart              # File pickers and opening files
│   ├── print_service.dart             # Printable HTML
│   └── app_log.dart                   # Error log file
├── screens/
│   ├── home_screen.dart               # Layout, ribbons, shortcuts
│   ├── backstage/backstage_view.dart  # File tab
│   ├── mail/                          # Mail view, compose, dialogs, address book
│   ├── calendar/                      # Day/week/month grids, editor, import/export
│   ├── contacts/                      # List, details, editors, import/export
│   └── settings/account_setup_screen.dart  # Account wizard
└── widgets/
    ├── ribbon/ribbon_toolbar.dart     # Outlook ribbon component
    ├── common.dart                    # Dialogs, menus, shared widgets
    ├── folder_pane.dart               # Folder tree sidebar
    ├── message_list.dart              # Message list with grouping
    ├── reading_pane.dart              # Message reader
    ├── navigation_bar.dart            # Mail / Calendar / People bar
    └── status_bar.dart                # Status and connection state
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `enough_mail` | IMAP / POP3 / SMTP and MIME |
| `sqlite3` | Local database (SQLite bundled by its build hook) |
| `pointycastle` | AES-GCM encryption of secrets without a keyring |
| `crypto` | PKCE (SHA-256) for Sign in with Microsoft |
| `flutter_html`, `flutter_html_table` | HTML email rendering |
| `flutter_quill`, `vsc_quill_delta_to_html` | Rich text compose editor, editor document to email HTML |
| `desktop_drop` | Files dragged onto the message window |
| `clock` | Testable time for scheduled sending |
| `html` | HTML sanitizing (pinned below 0.15.7 for flutter_html 3.0.0) |
| `file_picker` | File dialogs through the XDG portal |
| `dbus` | Desktop notifications, Secret Service keyring |
| hunspell / enchant (runtime, optional) | Spell checking, through their ispell pipe mode |
| `url_launcher` | Opening links, files and print pages |
| `path_provider`, `path` | Data directory |
| `shared_preferences` | Only to migrate data from older versions |
| `intl`, `uuid`, `collection` | Formatting, ids, utilities |
| `flutter_localizations` | Localizations the editor needs |
