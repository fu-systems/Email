import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/folder.dart';

void main() {
  test('folder type detection', () {
    expect(MailFolder.detectType('INBOX'), FolderType.inbox);
  });
}
