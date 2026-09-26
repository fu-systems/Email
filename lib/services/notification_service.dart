import 'package:dbus/dbus.dart';

/// Shows desktop notifications through the freedesktop notification
/// service (org.freedesktop.Notifications on the session bus), which GNOME,
/// KDE, XFCE and most other Linux desktops implement.
///
/// All failures (no session bus, no notification daemon) are swallowed:
/// notifications are a convenience, never a requirement.
class NotificationService {
  DBusClient? _client;
  bool _unavailable = false;
  final Map<String, int> _lastIds = {};

  /// Whether notifications should be shown at all (user setting).
  bool enabled;

  NotificationService({this.enabled = true});

  /// Shows a notification. Notifications with the same [tag] replace each
  /// other instead of piling up (e.g. "3 new messages" → "4 new messages").
  Future<void> show({
    required String title,
    required String body,
    String? tag,
    String icon = 'mail-unread',
  }) async {
    if (!enabled || _unavailable) return;
    try {
      _client ??= DBusClient.session();
      final object = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );
      final result = await object.callMethod(
        'org.freedesktop.Notifications',
        'Notify',
        [
          const DBusString('Look In'),
          DBusUint32(tag == null ? 0 : (_lastIds[tag] ?? 0)),
          DBusString(icon),
          DBusString(title),
          DBusString(_escape(body)),
          DBusArray.string(const []),
          DBusDict.stringVariant({
            'desktop-entry': const DBusString('look_in'),
            'category': const DBusString('email.arrived'),
          }),
          const DBusInt32(-1),
        ],
        replySignature: DBusSignature('u'),
      ).timeout(const Duration(seconds: 3));
      if (tag != null) {
        _lastIds[tag] = (result.returnValues.first as DBusUint32).value;
      }
    } catch (_) {
      // No session bus or notification daemon (e.g. headless): give up
      // quietly and don't retry for the rest of the session.
      _unavailable = true;
      await close();
    }
  }

  /// Notification bodies may contain markup; escape user content.
  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Future<void> close() async {
    final client = _client;
    _client = null;
    try {
      await client?.close();
    } catch (_) {}
  }
}
