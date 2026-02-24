# Look In

An open-source Linux email client inspired by Microsoft Outlook 2013.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)
![Framework](https://img.shields.io/badge/framework-Flutter-02569B.svg)

## Features

- **Email** - Full IMAP/SMTP support with folder management, compose, reply, forward
- **Calendar** - Day, week, and month views with event creation and management
- **Contacts** - Address book with contact groups and search
- **Outlook 2013 UI** - Classic ribbon toolbar, folder pane, reading pane layout

## Screenshots

*Coming soon*

## Getting Started

### Prerequisites

- Flutter SDK >= 3.13.0 (with Linux desktop support enabled)
- Linux development libraries:

```bash
# Ubuntu/Debian
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsqlite3-dev

# Fedora
sudo dnf install clang cmake ninja-build gtk3-devel lzma-devel sqlite-devel

# Arch
sudo pacman -S clang cmake ninja gtk3 xz sqlite
```

### Building

```bash
# Enable Linux desktop support
flutter config --enable-linux-desktop

# Get dependencies
flutter pub get

# Run in debug mode
flutter run -d linux

# Build release
flutter build linux --release
```

The release binary will be at `build/linux/x64/release/bundle/look_in`.

### Account Setup

On first launch, Look In will guide you through adding an email account:

1. Enter your email address and display name
2. Configure IMAP server settings (host, port, encryption)
3. Configure SMTP server settings (host, port, encryption)
4. Enter your credentials

Common provider settings are auto-detected for Gmail, Outlook.com, Yahoo, and others.

## Architecture

```
lib/
  main.dart              # Entry point
  app.dart               # App widget and routing
  theme/                 # Outlook 2013 theme
  models/                # Data models
  services/              # IMAP, SMTP, database services
  providers/             # State management (Provider)
  screens/               # Full-page views
    mail/                # Mail view + compose
    calendar/            # Calendar views
    contacts/            # Contact management
    settings/            # Account & app settings
  widgets/               # Reusable UI components
    ribbon/              # Ribbon toolbar
```

## Protocol Support

| Protocol | Status |
|----------|--------|
| IMAP     | Supported |
| SMTP     | Supported |
| POP3     | Planned |
| Exchange  | Planned |

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by Microsoft Outlook 2013
- Built with [Flutter](https://flutter.dev) and [Dart](https://dart.dev)
- Email support via [enough_mail](https://pub.dev/packages/enough_mail)
