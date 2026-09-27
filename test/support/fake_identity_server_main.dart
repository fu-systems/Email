// Runs the fake Microsoft identity platform for manual testing:
//
//   dart run test/support/fake_identity_server_main.dart [access-token] [user]
//
// then start Look In with LOOKIN_MS_LOGIN_BASE set to the printed address.
// Any browser (or `curl -L`) opening the sign-in link is signed in at once.
import 'dart:io';

import 'fake_identity_server.dart';

Future<void> main(List<String> args) async {
  final idp = await FakeIdentityServer.start();
  if (args.isNotEmpty) idp.accessToken = args[0];
  if (args.length > 1) idp.username = args[1];
  stdout.writeln(idp.base);
  await ProcessSignal.sigterm.watch().first;
  await idp.close();
}
