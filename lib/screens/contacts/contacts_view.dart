import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/contacts_provider.dart';
import '../../theme/outlook_theme.dart';
import 'contact_actions.dart';
import 'contact_detail_pane.dart';
import 'contacts_list_pane.dart';

// The People module's public API (dialogs and actions used by the ribbon
// and other modules).
export 'contact_actions.dart';
export 'contact_editor_dialog.dart';
export 'contacts_io_actions.dart';
export 'group_editor_dialog.dart';

/// Width of the People navigation pane ("My Contacts").
const double _navigationPaneWidth = OutlookTheme.folderPaneWidth;

/// Width of the contact/group list pane (including the alphabet index).
const double _listPaneWidth = 340;

/// The People module (Outlook 2013 style): a navigation pane with the
/// Contacts and Contact Groups folders, the contact or group list with
/// search and an alphabet index, and a detail pane for the selection.
///
/// Ctrl+E focuses the search box.
class ContactsView extends StatelessWidget {
  const ContactsView({super.key});

  @override
  Widget build(BuildContext context) => const _PeopleLayout();
}

class _PeopleLayout extends StatefulWidget {
  const _PeopleLayout();

  @override
  State<_PeopleLayout> createState() => _PeopleLayoutState();
}

class _PeopleLayoutState extends State<_PeopleLayout> {
  final _searchFocus = FocusNode(debugLabel: 'People search');

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyE &&
        HardwareKeyboard.instance.isControlPressed) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: _navigationPaneWidth,
            child: _PeopleNavigationPane(),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: _listPaneWidth,
            child: ContactsListPane(searchFocusNode: _searchFocus),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: ContactDetailPane()),
        ],
      ),
    );
  }
}

/// Left pane: "My Contacts" with the Contacts and Contact Groups entries,
/// and New Contact / New Contact Group buttons at the bottom.
class _PeopleNavigationPane extends StatelessWidget {
  const _PeopleNavigationPane();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    return ColoredBox(
      color: OutlookTheme.folderPaneBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 0, 12, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: OutlookTheme.textSecondary,
                      ),
                      SizedBox(width: 2),
                      Text(
                        'My Contacts',
                        style: OutlookTheme.folderLabelBoldStyle,
                      ),
                    ],
                  ),
                ),
                // One entry per address book when there are Microsoft
                // ones; otherwise "Contacts" shows them all.
                if (provider.addressBooks.length < 2)
                  _NavigationEntry(
                    icon: Icons.contacts_outlined,
                    label: 'Contacts (${provider.contactsById.length})',
                    selected: !provider.showGroups,
                    onTap: () {
                      if (provider.showGroups) provider.setShowGroups(false);
                      provider.setAddressBookFilter(null);
                    },
                  )
                else ...[
                  _NavigationEntry(
                    icon: Icons.people_outline,
                    label: 'All Contacts (${provider.contactsById.length})',
                    selected:
                        !provider.showGroups &&
                        provider.addressBookFilter == null,
                    onTap: () {
                      if (provider.showGroups) provider.setShowGroups(false);
                      provider.setAddressBookFilter(null);
                    },
                  ),
                  for (final book in provider.addressBooks)
                    _NavigationEntry(
                      icon: book.id == null
                          ? Icons.contacts_outlined
                          : Icons.cloud,
                      // Microsoft address books by their account.
                      label:
                          '${book.id == null ? 'Contacts' : provider.addressBookLabel(book.id).replaceFirst('Contacts - ', '')}'
                          ' (${provider.countIn(book.id)})',
                      problem: book.id == null
                          ? null
                          : provider.addressBookError(book.id!),
                      selected:
                          !provider.showGroups &&
                          provider.addressBookFilter == (book.id ?? 'local'),
                      onTap: () {
                        if (provider.showGroups) provider.setShowGroups(false);
                        provider.setAddressBookFilter(book.id ?? 'local');
                      },
                    ),
                ],
                _NavigationEntry(
                  icon: Icons.groups_outlined,
                  label: 'Contact Groups (${provider.groups.length})',
                  selected: provider.showGroups,
                  onTap: () {
                    if (!provider.showGroups) provider.setShowGroups(true);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  style: _compactButton,
                  onPressed: () => openContactEditor(context),
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('New Contact'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: _compactButton,
                  onPressed: () => openGroupEditor(context),
                  icon: const Icon(Icons.group_add_outlined, size: 16),
                  label: const Text('New Contact Group'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _compactButton = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 32),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  backgroundColor: Colors.white,
);

/// A folder-style entry in the navigation pane.
class _NavigationEntry extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A sync problem, shown as a warning icon with the details on hover.
  final String? problem;

  const _NavigationEntry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.problem,
  });

  @override
  State<_NavigationEntry> createState() => _NavigationEntryState();
}

class _NavigationEntryState extends State<_NavigationEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 26, right: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? OutlookTheme.selectedItemBackground
                : _hovered
                ? OutlookTheme.hoverColor
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.selected
                    ? OutlookTheme.primaryBlue
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.selected
                    ? OutlookTheme.primaryBlue
                    : OutlookTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: widget.selected
                      ? OutlookTheme.folderLabelBoldStyle
                      : OutlookTheme.folderLabelStyle,
                ),
              ),
              if (widget.problem case final String problem)
                Tooltip(
                  message: problem,
                  child: const Icon(
                    Icons.sync_problem,
                    size: 14,
                    color: OutlookTheme.flaggedColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
