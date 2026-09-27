import 'package:enough_mail/enough_mail.dart' show AuthMechanism;
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/services/mail_backend.dart';

void main() {
  test('passwords go with PLAIN, LOGIN or CRAM-MD5, never XOAUTH2', () {
    expect(
        SmtpSender.passwordMechanism(
            [AuthMechanism.xoauth2, AuthMechanism.login, AuthMechanism.plain]),
        AuthMechanism.plain);
    expect(
        SmtpSender.passwordMechanism(
            [AuthMechanism.xoauth2, AuthMechanism.login]),
        AuthMechanism.login);
    expect(SmtpSender.passwordMechanism([AuthMechanism.cramMd5]),
        AuthMechanism.cramMd5);
    expect(SmtpSender.passwordMechanism([AuthMechanism.xoauth2]), isNull);
  });
}
