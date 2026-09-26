import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/email_message.dart';
import 'package:look_in/models/mail_rule.dart';

EmailMessage message({
  String accountId = 'acc-1',
  String subject = 'Quarterly report',
  EmailAddress from = const EmailAddress(
      address: 'alice@example.com', displayName: 'Alice Smith'),
  List<EmailAddress> to = const [EmailAddress(address: 'me@example.com')],
  List<EmailAddress> cc = const [],
  List<EmailAddress> bcc = const [],
  String? textBody,
  String? htmlBody,
  String preview = '',
  bool hasAttachments = false,
  MessageImportance importance = MessageImportance.normal,
}) =>
    EmailMessage(
      id: 'm-1',
      accountId: accountId,
      folderId: 'INBOX',
      subject: subject,
      from: from,
      to: to,
      cc: cc,
      bcc: bcc,
      date: DateTime(2026, 1, 5, 9),
      textBody: textBody,
      htmlBody: htmlBody,
      preview: preview,
      hasAttachments: hasAttachments,
      importance: importance,
    );

bool cond(RuleField field, String value, EmailMessage m) =>
    RuleCondition(field: field, value: value).matches(m);

void main() {
  group('RuleCondition.matches', () {
    test('from matches the address or display name, case-insensitively', () {
      final m = message();
      expect(cond(RuleField.from, 'alice@example.com', m), isTrue);
      expect(cond(RuleField.from, 'EXAMPLE.COM', m), isTrue);
      expect(cond(RuleField.from, 'smith', m), isTrue);
      expect(cond(RuleField.from, 'Alice Smith', m), isTrue);
      expect(cond(RuleField.from, 'bob', m), isFalse);
      final noName = message(from: const EmailAddress(address: 'x@y.org'));
      expect(cond(RuleField.from, 'x@y.org', noName), isTrue);
      expect(cond(RuleField.from, 'null', noName), isFalse);
    });

    test('to matches To and Cc recipients but not Bcc', () {
      final m = message(
        to: const [
          EmailAddress(address: 'team@example.com', displayName: 'Team')
        ],
        cc: const [EmailAddress(address: 'boss@example.com')],
        bcc: const [EmailAddress(address: 'secret@example.com')],
      );
      expect(cond(RuleField.to, 'team@', m), isTrue);
      expect(cond(RuleField.to, 'team', m), isTrue);
      expect(cond(RuleField.to, 'BOSS@example.com', m), isTrue);
      expect(cond(RuleField.to, 'secret', m), isFalse);
      expect(cond(RuleField.to, 'alice', m), isFalse);
    });

    test('to with no recipients never matches', () {
      final m = message(to: const []);
      expect(cond(RuleField.to, 'me', m), isFalse);
    });

    test('subject contains the value', () {
      final m = message(subject: 'Re: [Invoice] #1234 overdue');
      expect(cond(RuleField.subject, 'invoice', m), isTrue);
      expect(cond(RuleField.subject, '[INVOICE]', m), isTrue);
      expect(cond(RuleField.subject, '#1234', m), isTrue);
      expect(cond(RuleField.subject, 'receipt', m), isFalse);
    });

    test('value is trimmed', () {
      final m = message(subject: 'Weekly newsletter');
      expect(cond(RuleField.subject, '  newsletter  ', m), isTrue);
    });

    test('an empty or blank value never matches text fields', () {
      final m = message();
      for (final field in [
        RuleField.from,
        RuleField.to,
        RuleField.subject,
        RuleField.body,
      ]) {
        expect(cond(field, '', m), isFalse, reason: field.name);
        expect(cond(field, '   ', m), isFalse, reason: field.name);
      }
    });

    test('body searches the text body and the HTML body', () {
      final m = message(
        textBody: 'Please find the numbers attached.',
        htmlBody: '<p>Unsubscribe <a href="#">here</a></p>',
      );
      expect(cond(RuleField.body, 'NUMBERS', m), isTrue);
      expect(cond(RuleField.body, 'unsubscribe', m), isTrue);
      expect(cond(RuleField.body, 'lottery', m), isFalse);
    });

    test('body falls back to the preview when there is no text body', () {
      final m = message(preview: 'Your parcel has shipped');
      expect(cond(RuleField.body, 'parcel', m), isTrue);
      final withText = message(preview: 'preview only', textBody: 'full text');
      expect(cond(RuleField.body, 'preview only', withText), isFalse);
      expect(cond(RuleField.body, 'full text', withText), isTrue);
    });

    test('hasAttachment ignores the value', () {
      expect(cond(RuleField.hasAttachment, '', message(hasAttachments: true)),
          isTrue);
      expect(
          cond(RuleField.hasAttachment, 'anything',
              message(hasAttachments: true)),
          isTrue);
      expect(cond(RuleField.hasAttachment, '', message()), isFalse);
    });

    test('importanceHigh', () {
      expect(
          cond(RuleField.importanceHigh, '',
              message(importance: MessageImportance.high)),
          isTrue);
      expect(cond(RuleField.importanceHigh, '', message()), isFalse);
      expect(
          cond(RuleField.importanceHigh, '',
              message(importance: MessageImportance.low)),
          isFalse);
    });

    test('describe', () {
      expect(
          const RuleCondition(field: RuleField.subject, value: 'invoice')
              .describe(),
          'subject contains "invoice"');
      expect(const RuleCondition(field: RuleField.to, value: 'me').describe(),
          'sent to (to/cc) contains "me"');
      expect(const RuleCondition(field: RuleField.hasAttachment).describe(),
          'has attachment');
    });
  });

  group('RuleField', () {
    test('needsValue only for text fields', () {
      expect(RuleField.from.needsValue, isTrue);
      expect(RuleField.to.needsValue, isTrue);
      expect(RuleField.subject.needsValue, isTrue);
      expect(RuleField.body.needsValue, isTrue);
      expect(RuleField.hasAttachment.needsValue, isFalse);
      expect(RuleField.importanceHigh.needsValue, isFalse);
    });

    test('every field has a label', () {
      for (final f in RuleField.values) {
        expect(f.label, isNotEmpty);
      }
    });
  });

  group('MailRule.matches', () {
    const invoice = RuleCondition(field: RuleField.subject, value: 'invoice');
    const fromAlice = RuleCondition(field: RuleField.from, value: 'alice');
    final m = message(
        subject: 'Invoice 42',
        from: const EmailAddress(address: 'bob@example.com'));

    test('matchAll requires every condition', () {
      const rule =
          MailRule(id: 'r', name: 'r', conditions: [invoice, fromAlice]);
      expect(rule.matchAll, isTrue);
      expect(rule.matches(m), isFalse);
      expect(rule.matches(message(subject: 'Invoice 42')), isTrue);
    });

    test('match any requires one condition', () {
      const rule = MailRule(
          id: 'r',
          name: 'r',
          matchAll: false,
          conditions: [invoice, fromAlice]);
      expect(rule.matches(m), isTrue);
      expect(rule.matches(message(subject: 'Hello')), isTrue);
      expect(
          rule.matches(message(
              subject: 'Hello',
              from: const EmailAddress(address: 'carol@example.com'))),
          isFalse);
    });

    test('a rule without conditions never matches', () {
      const rule = MailRule(id: 'r', name: 'r', markAsRead: true);
      expect(rule.matches(m), isFalse);
      const any = MailRule(id: 'r', name: 'r', matchAll: false);
      expect(any.matches(m), isFalse);
    });

    test('disabled rules never match', () {
      const rule =
          MailRule(id: 'r', name: 'r', isEnabled: false, conditions: [invoice]);
      expect(rule.matches(m), isFalse);
      expect(rule.copyWith(isEnabled: true).matches(m), isTrue);
    });

    test('accountId scopes the rule to one account', () {
      const scoped = MailRule(
          id: 'r', name: 'r', accountId: 'acc-2', conditions: [invoice]);
      expect(scoped.matches(m), isFalse);
      expect(scoped.matches(message(subject: 'Invoice', accountId: 'acc-2')),
          isTrue);
      const global = MailRule(id: 'r', name: 'r', conditions: [invoice]);
      expect(global.matches(m), isTrue);
      expect(global.matches(message(subject: 'Invoice', accountId: 'acc-9')),
          isTrue);
      expect(scoped.copyWith(clearAccount: true).matches(m), isTrue);
    });

    test('hasActions', () {
      expect(const MailRule(id: 'r', name: 'r').hasActions, isFalse);
      expect(const MailRule(id: 'r', name: 'r', flag: true).hasActions, isTrue);
      expect(const MailRule(id: 'r', name: 'r', markAsRead: true).hasActions,
          isTrue);
      expect(
          const MailRule(id: 'r', name: 'r', delete: true).hasActions, isTrue);
      expect(
          const MailRule(id: 'r', name: 'r', moveToFolderPath: 'X').hasActions,
          isTrue);
      expect(
          const MailRule(id: 'r', name: 'r', stopProcessing: true).hasActions,
          isFalse);
    });

    test('summary', () {
      const rule = MailRule(
        id: 'r',
        name: 'r',
        matchAll: false,
        conditions: [invoice, RuleCondition(field: RuleField.hasAttachment)],
        moveToFolderPath: 'Finance',
        markAsRead: true,
      );
      expect(rule.summary,
          'If subject contains "invoice" or has attachment then move to "Finance", mark as read');
      const nothing = MailRule(id: 'r', name: 'r', conditions: [invoice]);
      expect(nothing.summary, 'If subject contains "invoice" then do nothing');
    });

    test('copyWith keeps and clears fields', () {
      const rule = MailRule(
        id: 'r',
        name: 'Old',
        accountId: 'acc-1',
        moveToFolderPath: 'Archive',
        conditions: [invoice],
      );
      final renamed = rule.copyWith(name: 'New');
      expect(renamed.id, 'r');
      expect(renamed.name, 'New');
      expect(renamed.accountId, 'acc-1');
      expect(renamed.moveToFolderPath, 'Archive');
      expect(rule.copyWith(clearMoveTo: true).moveToFolderPath, isNull);
      expect(rule.copyWith(clearAccount: true).accountId, isNull);
    });
  });

  group('RuleOutcome.evaluate', () {
    const invoice = RuleCondition(field: RuleField.subject, value: 'invoice');
    const urgent = RuleCondition(field: RuleField.subject, value: 'urgent');
    final m = message(subject: 'URGENT: invoice overdue');

    test('no matching rules gives an empty outcome', () {
      final outcome = RuleOutcome.evaluate([
        const MailRule(
            id: 'a',
            name: 'a',
            conditions: [
              RuleCondition(field: RuleField.subject, value: 'nope')
            ],
            flag: true),
      ], m);
      expect(outcome.isEmpty, isTrue);
      expect(outcome.moveToFolderPath, isNull);
      expect(outcome.markAsRead, isFalse);
      expect(outcome.flag, isFalse);
      expect(outcome.delete, isFalse);
      expect(RuleOutcome.evaluate(const [], m).isEmpty, isTrue);
    });

    test('the first move target wins and flags accumulate', () {
      const first = MailRule(
          id: 'a',
          name: 'a',
          conditions: [invoice],
          moveToFolderPath: 'Finance');
      const second = MailRule(
          id: 'b',
          name: 'b',
          conditions: [urgent],
          moveToFolderPath: 'Urgent',
          markAsRead: true);
      const third =
          MailRule(id: 'c', name: 'c', conditions: [invoice], flag: true);
      final outcome = RuleOutcome.evaluate([first, second, third], m);
      expect(outcome.matchedRules.map((r) => r.id), ['a', 'b', 'c']);
      expect(outcome.moveToFolderPath, 'Finance');
      expect(outcome.markAsRead, isTrue);
      expect(outcome.flag, isTrue);
      expect(outcome.delete, isFalse);
      expect(outcome.isEmpty, isFalse);

      final reversed = RuleOutcome.evaluate([second, first], m);
      expect(reversed.moveToFolderPath, 'Urgent');
    });

    test('a rule without a move target does not block a later one', () {
      const flagOnly =
          MailRule(id: 'a', name: 'a', conditions: [urgent], flag: true);
      const move = MailRule(
          id: 'b',
          name: 'b',
          conditions: [invoice],
          moveToFolderPath: 'Finance');
      final outcome = RuleOutcome.evaluate([flagOnly, move], m);
      expect(outcome.moveToFolderPath, 'Finance');
      expect(outcome.flag, isTrue);
    });

    test('stopProcessing ends evaluation after a matching rule', () {
      const stop = MailRule(
          id: 'a',
          name: 'a',
          conditions: [urgent],
          markAsRead: true,
          stopProcessing: true);
      const later = MailRule(
          id: 'b',
          name: 'b',
          conditions: [invoice],
          moveToFolderPath: 'Finance');
      final outcome = RuleOutcome.evaluate([stop, later], m);
      expect(outcome.matchedRules.map((r) => r.id), ['a']);
      expect(outcome.markAsRead, isTrue);
      expect(outcome.moveToFolderPath, isNull);
    });

    test('stopProcessing on a rule that does not match has no effect', () {
      const stop = MailRule(
          id: 'a',
          name: 'a',
          conditions: [RuleCondition(field: RuleField.subject, value: 'nope')],
          stopProcessing: true);
      const later =
          MailRule(id: 'b', name: 'b', conditions: [invoice], flag: true);
      final outcome = RuleOutcome.evaluate([stop, later], m);
      expect(outcome.matchedRules.map((r) => r.id), ['b']);
      expect(outcome.flag, isTrue);
    });

    test('disabled rules are skipped', () {
      const disabled = MailRule(
          id: 'a',
          name: 'a',
          isEnabled: false,
          conditions: [invoice],
          delete: true,
          stopProcessing: true);
      const later =
          MailRule(id: 'b', name: 'b', conditions: [invoice], flag: true);
      final outcome = RuleOutcome.evaluate([disabled, later], m);
      expect(outcome.matchedRules.map((r) => r.id), ['b']);
      expect(outcome.delete, isFalse);
    });

    test('delete overrides move, even when the move came first', () {
      const move = MailRule(
          id: 'a',
          name: 'a',
          conditions: [invoice],
          moveToFolderPath: 'Finance');
      const delete =
          MailRule(id: 'b', name: 'b', conditions: [urgent], delete: true);
      final outcome = RuleOutcome.evaluate([move, delete], m);
      expect(outcome.delete, isTrue);
      expect(outcome.moveToFolderPath, isNull);
      expect(outcome.matchedRules, hasLength(2));

      final deleteFirst = RuleOutcome.evaluate([delete, move], m);
      expect(deleteFirst.delete, isTrue);
      expect(deleteFirst.moveToFolderPath, isNull);
    });

    test('rules scoped to another account are ignored', () {
      const other = MailRule(
          id: 'a',
          name: 'a',
          accountId: 'acc-2',
          conditions: [invoice],
          delete: true);
      expect(RuleOutcome.evaluate([other], m).isEmpty, isTrue);
    });
  });

  group('serialization', () {
    test('toMap/fromMap round trip', () {
      const rule = MailRule(
        id: 'rule-1',
        name: 'Invoices',
        isEnabled: false,
        accountId: 'acc-7',
        matchAll: false,
        conditions: [
          RuleCondition(field: RuleField.subject, value: 'invoice'),
          RuleCondition(field: RuleField.from, value: 'billing@'),
          RuleCondition(field: RuleField.hasAttachment),
          RuleCondition(field: RuleField.importanceHigh),
        ],
        moveToFolderPath: 'Finance/2026',
        markAsRead: true,
        flag: true,
        delete: false,
        stopProcessing: true,
      );
      final copy = MailRule.fromMap(rule.toMap());
      expect(copy.toMap(), rule.toMap());
      expect(copy.id, 'rule-1');
      expect(copy.name, 'Invoices');
      expect(copy.isEnabled, isFalse);
      expect(copy.accountId, 'acc-7');
      expect(copy.matchAll, isFalse);
      expect(copy.conditions.map((c) => c.field), [
        RuleField.subject,
        RuleField.from,
        RuleField.hasAttachment,
        RuleField.importanceHigh,
      ]);
      expect(
          copy.conditions.map((c) => c.value), ['invoice', 'billing@', '', '']);
      expect(copy.moveToFolderPath, 'Finance/2026');
      expect(copy.markAsRead, isTrue);
      expect(copy.flag, isTrue);
      expect(copy.delete, isFalse);
      expect(copy.stopProcessing, isTrue);
    });

    test('toMap uses plain JSON types', () {
      const rule = MailRule(
          id: 'r',
          name: 'r',
          conditions: [RuleCondition(field: RuleField.body, value: 'x')]);
      final map = rule.toMap();
      expect(map['conditions'], [
        {'field': 'body', 'value': 'x'}
      ]);
      expect(map['isEnabled'], isTrue);
      expect(map['accountId'], isNull);
    });

    test('fromMap applies defaults for missing fields', () {
      final rule = MailRule.fromMap(const {'id': 'r'});
      expect(rule.name, 'Rule');
      expect(rule.isEnabled, isTrue);
      expect(rule.matchAll, isTrue);
      expect(rule.accountId, isNull);
      expect(rule.conditions, isEmpty);
      expect(rule.moveToFolderPath, isNull);
      expect(rule.markAsRead, isFalse);
      expect(rule.flag, isFalse);
      expect(rule.delete, isFalse);
      expect(rule.stopProcessing, isFalse);
    });

    test('RuleCondition.fromMap falls back for unknown fields', () {
      final c = RuleCondition.fromMap(const {'field': 'mystery', 'value': 'v'});
      expect(c.field, RuleField.subject);
      expect(c.value, 'v');
      final empty = RuleCondition.fromMap(const {});
      expect(empty.field, RuleField.subject);
      expect(empty.value, '');
    });

    test('fromMap accepts conditions as untyped maps (decoded JSON)', () {
      final rule = MailRule.fromMap(<String, dynamic>{
        'id': 'r',
        'name': 'n',
        'conditions': <dynamic>[
          <dynamic, dynamic>{'field': 'from', 'value': 'alice'},
        ],
      });
      expect(rule.conditions.single.field, RuleField.from);
      expect(rule.matches(message()), isTrue);
    });
  });
}
