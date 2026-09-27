#!/bin/sh
# Runs tests with a throwaway GNOME Keyring on a private D-Bus session, so
# the Secret Service tests (LOOKIN_KEYRING_TESTS=1) never touch your real
# keyring. Needs gnome-keyring and dbus-run-session.
#
#   tool/test_with_keyring.sh test/secret_store_test.dart
set -eu
exec dbus-run-session -- sh -c '
  export XDG_DATA_HOME=$(mktemp -d)
  eval "$(printf "look-in-test" | gnome-keyring-daemon --daemonize --unlock --components=secrets)"
  export LOOKIN_KEYRING_TESTS=1
  flutter test "$@"
' sh "$@"
