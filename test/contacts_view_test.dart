import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_in/models/contact.dart';
import 'package:look_in/providers/contacts_provider.dart';
import 'package:look_in/screens/contacts/contact_detail_pane.dart';
import 'package:look_in/screens/contacts/contacts_list_pane.dart';
import 'package:look_in/screens/contacts/contacts_view.dart';
import 'package:look_in/services/data_store.dart';
import 'package:look_in/theme/outlook_theme.dart';
import 'package:look_in/widgets/common.dart';
import 'package:provider/provider.dart';

final _created = DateTime(2026, 1, 1);

Contact _contact(
  String id, {
  String? first,
  String? last,
  String? company,
  List<String> emails = const [],
  List<ContactPhone> phones = const [],
}) {
  return Contact(
    id: id,
    firstName: first,
    lastName: last,
    company: company,
    emails: [
      for (var i = 0; i < emails.length; i++)
        ContactEmail(
            label: i == 0 ? 'Email' : 'Email ${i + 1}', address: emails[i]),
    ],
    phones: phones,
    createdAt: _created,
    updatedAt: _created,
  );
}

ContactGroup _group(String id, String name, List<String> memberIds) =>
    ContactGroup(
      id: id,
      name: name,
      memberIds: memberIds,
      createdAt: _created,
      updatedAt: _created,
    );

void main() {
  late DataStore store;

  setUp(() {
    store = DataStore.inMemory();
    store.saveContacts([
      _contact('zoe',
          first: 'Zoe',
          last: 'Adams',
          company: 'Acme',
          emails: ['zoe@example.com']),
      _contact('bob',
          first: 'Bob', last: 'Carter', emails: ['bob@example.com']),
      _contact('alice',
          first: 'Alice', last: 'Young', emails: ['alice@example.com']),
      _contact('nw', company: 'Northwind Traders'),
    ]);
  });

  tearDown(() => store.close());

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ContactsProvider(store: store)),
        ],
        child: MaterialApp(
          theme: OutlookTheme.themeData,
          home: const Scaffold(body: ContactsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BuildContext viewContext(WidgetTester tester) =>
      tester.element(find.byType(ContactsView));

  ContactsProvider providerOf(WidgetTester tester) =>
      Provider.of<ContactsProvider>(viewContext(tester), listen: false);

  Finder inList(String text) => find.descendant(
      of: find.byType(ContactsListPane), matching: find.text(text));

  Finder inDetail(String text) => find.descendant(
      of: find.byType(ContactDetailPane), matching: find.text(text));

  Finder inDialog(Type dialog, Finder matching) =>
      find.descendant(of: find.byType(dialog), matching: matching);

  Finder field(Type dialog, String label) =>
      inDialog(dialog, find.widgetWithText(TextField, label));

  Finder searchBox() => find.descendant(
      of: find.byType(ContactsListPane), matching: find.byType(TextField));

  testWidgets('lists the seeded contacts sorted by file-as name',
      (tester) async {
    await pumpView(tester);

    expect(find.text('Contacts (4)'), findsOneWidget);
    expect(find.text('Contact Groups (0)'), findsOneWidget);
    expect(find.text('New Contact'), findsOneWidget);
    expect(find.text('New Contact Group'), findsOneWidget);

    // Adams, Zoe < Carter, Bob < Northwind Traders < Young, Alice
    final order = [
      'Zoe Adams',
      'Bob Carter',
      'Northwind Traders',
      'Alice Young'
    ];
    final tops = [for (final name in order) tester.getTopLeft(inList(name)).dy];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: order[i]);
    }
    expect(inList('zoe@example.com'), findsOneWidget);
    expect(inList('Acme'), findsOneWidget);
    expect(find.text('Select a contact to see the details'), findsOneWidget);
  });

  testWidgets('search filters the list and can be cleared', (tester) async {
    await pumpView(tester);

    await tester.enterText(searchBox(), 'bob');
    await tester.pump();
    expect(inList('Bob Carter'), findsOneWidget);
    expect(inList('Zoe Adams'), findsNothing);
    expect(inList('Alice Young'), findsNothing);

    // Company names match too.
    await tester.enterText(searchBox(), 'acme');
    await tester.pump();
    expect(inList('Zoe Adams'), findsOneWidget);
    expect(inList('Bob Carter'), findsNothing);

    await tester.enterText(searchBox(), 'nobody-matches');
    await tester.pump();
    expect(find.text('No contacts match'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(inList('Zoe Adams'), findsOneWidget);
    expect(inList('Bob Carter'), findsOneWidget);
    expect(providerOf(tester).searchQuery, isEmpty);
  });

  testWidgets('alphabet index filters by letter and toggles off',
      (tester) async {
    await pumpView(tester);
    final provider = providerOf(tester);

    await tester.tap(find.byKey(const ValueKey('people-letter-C')));
    await tester.pump();
    expect(provider.selectedLetter, 'C');
    expect(inList('Bob Carter'), findsOneWidget);
    expect(inList('Zoe Adams'), findsNothing);
    expect(inList('Northwind Traders'), findsNothing);

    // Clicking the active letter clears the filter.
    await tester.tap(find.byKey(const ValueKey('people-letter-C')));
    await tester.pump();
    expect(provider.selectedLetter, isNull);
    expect(inList('Zoe Adams'), findsOneWidget);

    // Letters without contacts are not clickable.
    await tester.tap(find.byKey(const ValueKey('people-letter-Q')));
    await tester.pump();
    expect(provider.selectedLetter, isNull);
    expect(inList('Alice Young'), findsOneWidget);
  });

  testWidgets('selecting a contact shows its details', (tester) async {
    store.saveContact(_contact('bob',
        first: 'Bob',
        last: 'Carter',
        emails: ['bob@example.com', 'bob@home.example'],
        phones: const [ContactPhone(label: 'Mobile', number: '555-0100')]));
    store.saveGroup(_group('g1', 'Bowling Team', ['bob']));
    await pumpView(tester);

    await tester.tap(inList('Bob Carter'));
    await tester.pump();

    expect(providerOf(tester).selectedContact?.id, 'bob');
    expect(inDetail('Bob Carter'), findsOneWidget);
    expect(inDetail('bob@example.com'), findsOneWidget);
    expect(inDetail('bob@home.example'), findsOneWidget);
    expect(inDetail('Email 2'), findsOneWidget);
    expect(inDetail('555-0100'), findsOneWidget);
    expect(inDetail('Phone'), findsOneWidget);
    expect(inDetail('Member of'), findsOneWidget);
    expect(inDetail('Bowling Team'), findsOneWidget);
    for (final action in ['Email', 'Edit', 'Delete']) {
      expect(
          find.descendant(
              of: find.byType(ContactDetailPane),
              matching: find.widgetWithText(HoverButton, action)),
          findsOneWidget,
          reason: action);
    }
    expect(find.text('Select a contact to see the details'), findsNothing);
  });

  testWidgets('ContactEditorDialog blocks invalid email and creates a contact',
      (tester) async {
    await pumpView(tester);
    final provider = providerOf(tester);

    showDialog<void>(
      context: viewContext(tester),
      builder: (_) => const ContactEditorDialog(),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Contact'), findsWidgets);

    // Nothing entered: saving is refused with a message.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    expect(
        find.text('Enter a name, company or email address for this contact.'),
        findsOneWidget);
    expect(find.byType(ContactEditorDialog), findsOneWidget);

    await tester.enterText(field(ContactEditorDialog, 'First name'), 'Dana');
    await tester.enterText(field(ContactEditorDialog, 'Last name'), 'Evans');
    await tester.enterText(field(ContactEditorDialog, 'Email'), 'not-an-email');
    await tester.enterText(field(ContactEditorDialog, 'Mobile'), '555-0199');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();

    expect(find.text("This doesn't look like a valid email address"),
        findsOneWidget);
    expect(find.byType(ContactEditorDialog), findsOneWidget);
    expect(provider.allContacts, hasLength(4));

    await tester.enterText(
        field(ContactEditorDialog, 'Email'), 'dana@example.com');
    await tester.pump();
    expect(find.text("This doesn't look like a valid email address"),
        findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ContactEditorDialog), findsNothing);
    expect(provider.allContacts, hasLength(5));
    final dana = provider.findByEmail('dana@example.com')!;
    expect(dana.firstName, 'Dana');
    expect(dana.lastName, 'Evans');
    expect(dana.emails.single.label, 'Email');
    expect(dana.phones.single.label, 'Mobile');
    expect(dana.phones.single.number, '555-0199');
    expect(dana.company, isNull);
    expect(dana.address, isNull);
    expect(provider.selectedContact?.id, dana.id);
    expect(inList('Dana Evans'), findsOneWidget);
    expect(inDetail('Dana Evans'), findsOneWidget);
    expect(find.text('Contacts (5)'), findsOneWidget);
  });

  testWidgets('ContactEditorDialog prefills a new contact from an address',
      (tester) async {
    await pumpView(tester);

    showDialog<void>(
      context: viewContext(tester),
      builder: (_) => const ContactEditorDialog(
          initialEmail: 'mary@example.com', initialName: 'Mary Ann Smith'),
    );
    await tester.pumpAndSettle();

    String text(String label) => tester
        .widget<TextField>(field(ContactEditorDialog, label))
        .controller!
        .text;
    expect(text('First name'), 'Mary Ann');
    expect(text('Last name'), 'Smith');
    expect(text('Email'), 'mary@example.com');
  });

  testWidgets('ContactEditorDialog edits keep other labels and clear fields',
      (tester) async {
    store.saveContact(
        _contact('zoe', first: 'Zoe', last: 'Adams', company: 'Acme', emails: [
      'zoe@example.com'
    ], phones: const [
      ContactPhone(label: 'Work', number: '111'),
      ContactPhone(label: 'Business Fax', number: '222'),
    ]));
    await pumpView(tester);
    final provider = providerOf(tester);

    showDialog<void>(
      context: viewContext(tester),
      builder: (_) =>
          ContactEditorDialog(contact: provider.contactsById['zoe']),
    );
    await tester.pumpAndSettle();

    // The work number fills "Business"; the fax gets a field of its own.
    expect(
        tester
            .widget<TextField>(field(ContactEditorDialog, 'Business'))
            .controller!
            .text,
        '111');
    expect(field(ContactEditorDialog, 'Business Fax'), findsOneWidget);

    await tester.enterText(field(ContactEditorDialog, 'Company'), '');
    await tester.enterText(field(ContactEditorDialog, 'City'), 'Seattle');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    final zoe = provider.contactsById['zoe']!;
    expect(zoe.company, isNull);
    expect(zoe.address?.city, 'Seattle');
    expect([for (final p in zoe.phones) '${p.label}:${p.number}'],
        ['Work:111', 'Business Fax:222']);
    expect(zoe.createdAt, _created);
  });

  testWidgets('ContactGroupEditorDialog creates a group with members',
      (tester) async {
    await pumpView(tester);
    final provider = providerOf(tester);

    showDialog<void>(
      context: viewContext(tester),
      builder: (_) => const ContactGroupEditorDialog(),
    );
    await tester.pumpAndSettle();

    // Only contacts with an email address are offered.
    expect(inDialog(ContactGroupEditorDialog, find.text('Northwind Traders')),
        findsNothing);

    // The name is required.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    expect(find.text('Enter a name for the group'), findsOneWidget);

    await tester.enterText(
        field(ContactGroupEditorDialog, 'Group name'), 'Team');
    await tester
        .tap(inDialog(ContactGroupEditorDialog, find.text('Zoe Adams')));
    await tester
        .tap(inDialog(ContactGroupEditorDialog, find.text('Bob Carter')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // One-off addresses are validated before they are added.
    await tester.enterText(
        field(ContactGroupEditorDialog, 'Add email address'), 'bad address');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
    await tester.pump();
    expect(find.text("This doesn't look like a valid email address"),
        findsOneWidget);

    await tester.enterText(field(ContactGroupEditorDialog, 'Add email address'),
        'extra@example.org');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
    await tester.pump();
    expect(find.text('extra@example.org'), findsOneWidget);
    expect(find.text('3 selected'), findsOneWidget);

    // Filtering the picker keeps the selection.
    await tester.enterText(
        inDialog(ContactGroupEditorDialog,
            find.widgetWithText(TextField, 'Search contacts')),
        'alice');
    await tester.pump();
    expect(inDialog(ContactGroupEditorDialog, find.text('Zoe Adams')),
        findsNothing);
    expect(inDialog(ContactGroupEditorDialog, find.text('Alice Young')),
        findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ContactGroupEditorDialog), findsNothing);
    final group = provider.groups.single;
    expect(group.name, 'Team');
    expect(group.memberIds, ['zoe', 'bob']);
    expect(group.extraAddresses, ['extra@example.org']);

    // The new group is shown in the groups list.
    expect(provider.showGroups, isTrue);
    expect(find.text('Contact Groups (1)'), findsOneWidget);
    expect(inList('Team'), findsOneWidget);
    expect(inList('3 members'), findsOneWidget);
    expect(inDetail('Team'), findsOneWidget);
    expect(inDetail('Zoe Adams'), findsOneWidget);
    expect(inDetail('extra@example.org'), findsOneWidget);
  });

  testWidgets('groups tab lists groups and members can be removed',
      (tester) async {
    store.saveGroup(_group('g1', 'Family', ['zoe', 'alice']));
    await pumpView(tester);
    final provider = providerOf(tester);

    await tester.tap(find.text('Contact Groups (1)'));
    await tester.pump();
    expect(provider.showGroups, isTrue);
    expect(inList('Family'), findsOneWidget);
    expect(inList('2 members'), findsOneWidget);
    expect(inList('Bob Carter'), findsNothing);
    expect(
        find.text('Select a contact group to see its members'), findsOneWidget);

    await tester.tap(inList('Family'));
    await tester.pump();
    expect(inDetail('Zoe Adams'), findsOneWidget);
    expect(inDetail('Alice Young'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ContactDetailPane),
            matching: find.widgetWithText(HoverButton, 'Email Group')),
        findsOneWidget);

    await tester.tap(find.byTooltip('Remove Zoe Adams from this group'));
    await tester.pump();
    expect(store.getGroup('g1')!.memberIds, ['alice']);
    expect(inDetail('Zoe Adams'), findsNothing);
    expect(inList('1 member'), findsOneWidget);

    // Back to the contacts list.
    await tester.tap(find.text('Contacts (4)'));
    await tester.pump();
    expect(provider.showGroups, isFalse);
    expect(inList('Bob Carter'), findsOneWidget);
  });

  testWidgets('context menu adds a contact to a group', (tester) async {
    store.saveGroup(_group('g1', 'Family', ['zoe']));
    await pumpView(tester);
    final provider = providerOf(tester);

    await tester.tap(inList('Bob Carter'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsWidgets);
    expect(find.text('Add to Group'), findsOneWidget);

    await tester.tap(find.text('Add to Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family').last);
    await tester.pumpAndSettle();

    expect(store.getGroup('g1')!.memberIds, ['zoe', 'bob']);
    // The contact stays selected in the contacts list.
    expect(provider.showGroups, isFalse);
    expect(provider.selectedContact?.id, 'bob');
    expect(inDetail('Family'), findsOneWidget);
  });

  testWidgets('deleteContactWithPrompt removes the contact and its memberships',
      (tester) async {
    store.saveGroup(_group('g1', 'Family', ['zoe', 'bob']));
    await pumpView(tester);
    final provider = providerOf(tester);

    await tester.tap(inList('Zoe Adams'));
    await tester.pump();
    final zoe = provider.selectedContact!;

    // Cancelling keeps the contact.
    deleteContactWithPrompt(viewContext(tester), zoe);
    await tester.pumpAndSettle();
    expect(find.textContaining('It will also be removed from 1 contact group'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(provider.contactsById.containsKey('zoe'), isTrue);

    deleteContactWithPrompt(viewContext(tester), zoe);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(provider.contactsById.containsKey('zoe'), isFalse);
    expect(store.getGroup('g1')!.memberIds, ['bob']);
    expect(inList('Zoe Adams'), findsNothing);
    expect(find.text('Contacts (3)'), findsOneWidget);
    expect(find.text('Select a contact to see the details'), findsOneWidget);
  });

  testWidgets('deleteGroupWithPrompt keeps the member contacts',
      (tester) async {
    store.saveGroup(_group('g1', 'Family', ['zoe']));
    await pumpView(tester);
    final provider = providerOf(tester);

    deleteGroupWithPrompt(viewContext(tester), store.getGroup('g1')!);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(provider.groups, isEmpty);
    expect(provider.contactsById.containsKey('zoe'), isTrue);
    expect(find.text('Contact Groups (0)'), findsOneWidget);
  });

  test('parseContactsFile detects vCard and CSV content', () {
    const vcard = 'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Doe;Jane;;;\r\n'
        'FN:Jane Doe\r\nEMAIL:jane@example.com\r\nEND:VCARD\r\n';
    const csv = 'First Name,Last Name,E-mail Address\r\n'
        'John,Roe,john@example.com\r\n';

    expect(parseContactsFile('/tmp/a.vcf', vcard).single.primaryEmail,
        'jane@example.com');
    expect(parseContactsFile('/tmp/a.txt', vcard).single.firstName, 'Jane');
    expect(parseContactsFile('/tmp/a.csv', csv).single.lastName, 'Roe');
  });
}
