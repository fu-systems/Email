import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../providers/contacts_provider.dart';
import '../../theme/outlook_theme.dart';
import 'contact_actions.dart';
import 'contacts_common.dart';

/// Middle pane of the People module: a search box, the alphabet index (for
/// contacts) and the list of contacts or contact groups.
///
/// The list supports the keyboard once an item was clicked: Up/Down move the
/// selection, Enter opens the editor and Delete deletes (after a prompt).
class ContactsListPane extends StatefulWidget {
  /// Focus node of the search box (focused by Ctrl+E).
  final FocusNode searchFocusNode;

  const ContactsListPane({super.key, required this.searchFocusNode});

  @override
  State<ContactsListPane> createState() => _ContactsListPaneState();
}

class _ContactsListPaneState extends State<ContactsListPane> {
  late final TextEditingController _search;
  final _listFocus = FocusNode(debugLabel: 'People list');

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
        text: context.read<ContactsProvider>().searchQuery);
  }

  @override
  void dispose() {
    _search.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _clearFilters(ContactsProvider provider) {
    _search.clear();
    provider.setSearchQuery('');
    provider.setLetterFilter(null);
  }

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final provider = context.read<ContactsProvider>();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(provider, key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final contact = provider.showGroups ? null : provider.selectedContact;
    final group = provider.showGroups ? provider.selectedGroup : null;
    if (key == LogicalKeyboardKey.delete) {
      if (contact != null) deleteContactWithPrompt(context, contact);
      if (group != null) deleteGroupWithPrompt(context, group);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (contact != null) openContactEditor(context, contact: contact);
      if (group != null) openGroupEditor(context, group: group);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(ContactsProvider provider, int delta) {
    if (provider.showGroups) {
      final groups = provider.filteredGroups;
      if (groups.isEmpty) return;
      final index =
          groups.indexWhere((g) => g.id == provider.selectedGroup?.id);
      provider.selectGroup(groups[_step(index, delta, groups.length)]);
    } else {
      final contacts = provider.contacts;
      if (contacts.isEmpty) return;
      final index =
          contacts.indexWhere((c) => c.id == provider.selectedContact?.id);
      provider.selectContact(contacts[_step(index, delta, contacts.length)]);
    }
  }

  static int _step(int index, int delta, int length) =>
      index < 0 ? 0 : (index + delta).clamp(0, length - 1);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    return ColoredBox(
      color: OutlookTheme.messageListBackground,
      child: Column(
        children: [
          _buildSearchBox(provider),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!provider.showGroups) ...[
                  const _AlphabetRail(),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Focus(
                    focusNode: _listFocus,
                    onKeyEvent: _onListKey,
                    child: provider.showGroups
                        ? _buildGroupList(provider)
                        : _buildContactList(provider),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox(ContactsProvider provider) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OutlookTheme.dividerColor)),
      ),
      child: TextField(
        controller: _search,
        focusNode: widget.searchFocusNode,
        onChanged: provider.setSearchQuery,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search People',
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 32),
          suffixIcon: provider.searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _search.clear();
                    provider.setSearchQuery('');
                  },
                ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
    );
  }

  Widget _buildContactList(ContactsProvider provider) {
    final contacts = provider.contacts;
    if (contacts.isEmpty) {
      if (provider.contactsById.isEmpty) {
        return const PeopleEmptyState(
          icon: Icons.person_add_alt,
          title: 'No contacts yet',
          message: 'Click New Contact to add someone, or import contacts '
              'from a CSV or vCard file.',
        );
      }
      return PeopleEmptyState(
        icon: Icons.search_off,
        title: 'No contacts match',
        action: TextButton(
          onPressed: () => _clearFilters(provider),
          child: const Text('Show all contacts'),
        ),
      );
    }
    final selectedId = provider.selectedContact?.id;
    return ListView.builder(
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return _PeopleListTile(
          key: ValueKey('contact-${contact.id}'),
          selected: contact.id == selectedId,
          onTap: () {
            _listFocus.requestFocus();
            provider.selectContact(contact);
          },
          onDoubleTap: () => openContactEditor(context, contact: contact),
          onContextMenu: (position) {
            provider.selectContact(contact);
            showContactContextMenu(context, position, contact);
          },
          child: _ContactTileContent(contact: contact),
        );
      },
    );
  }

  Widget _buildGroupList(ContactsProvider provider) {
    final groups = provider.filteredGroups;
    if (groups.isEmpty) {
      if (provider.groups.isEmpty) {
        return const PeopleEmptyState(
          icon: Icons.groups_outlined,
          title: 'No contact groups yet',
          message: 'Click New Contact Group to create a list of people you '
              'email together.',
        );
      }
      return PeopleEmptyState(
        icon: Icons.search_off,
        title: 'No contact groups match',
        action: TextButton(
          onPressed: () => _clearFilters(provider),
          child: const Text('Show all groups'),
        ),
      );
    }
    final selectedId = provider.selectedGroup?.id;
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _PeopleListTile(
          key: ValueKey('group-${group.id}'),
          selected: group.id == selectedId,
          onTap: () {
            _listFocus.requestFocus();
            provider.selectGroup(group);
          },
          onDoubleTap: () => openGroupEditor(context, group: group),
          onContextMenu: (position) {
            provider.selectGroup(group);
            showGroupContextMenu(context, position, group);
          },
          child: _GroupTileContent(group: group),
        );
      },
    );
  }
}

/// A selectable list row with hover highlight, a blue bar when selected,
/// double-click and right-click handling.
class _PeopleListTile extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onContextMenu;
  final Widget child;

  const _PeopleListTile({
    super.key,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onContextMenu,
    required this.child,
  });

  @override
  State<_PeopleListTile> createState() => _PeopleListTileState();
}

class _PeopleListTileState extends State<_PeopleListTile> {
  bool _hovered = false;
  DateTime? _lastTap;

  @override
  void didUpdateWidget(_PeopleListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      // Keep a newly selected row (e.g. via the arrow keys) in view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        Scrollable.ensureVisible(context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
      });
    }
  }

  /// Selects on the first click and reports a second click on the same row
  /// within [kDoubleTapTimeout] as a double-click, so selection is instant.
  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) <= kDoubleTapTimeout) {
      _lastTap = null;
      widget.onDoubleTap();
      return;
    }
    _lastTap = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.selected
        ? OutlookTheme.selectedItemBackground
        : _hovered
            ? OutlookTheme.hoverColor
            : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onSecondaryTapUp: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
          decoration: BoxDecoration(
            color: background,
            border: Border(
              left: BorderSide(
                color: widget.selected
                    ? OutlookTheme.primaryBlue
                    : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: Color(0xFFEDEDED)),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ContactTileContent extends StatelessWidget {
  final Contact contact;

  const _ContactTileContent({required this.contact});

  @override
  Widget build(BuildContext context) {
    final subtitle = contactSubtitle(contact);
    final email = contact.primaryEmail;
    return Row(
      children: [
        ContactAvatar(contact: contact),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PeopleStyles.itemName),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PeopleStyles.secondary),
              if (email != null && email != contact.displayName)
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PeopleStyles.muted),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupTileContent extends StatelessWidget {
  final ContactGroup group;

  const _GroupTileContent({required this.group});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const GroupAvatar(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PeopleStyles.itemName),
              Text(memberCountLabel(group.memberCount),
                  style: PeopleStyles.muted),
            ],
          ),
        ),
      ],
    );
  }
}

/// Narrow "# A B C ... Z" index. Letters that start a contact's "file as"
/// name are bold and filter the list when clicked; clicking the active
/// letter again clears the filter.
class _AlphabetRail extends StatelessWidget {
  const _AlphabetRail();

  static const letters = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactsProvider>();
    final available = provider.availableLetters.toSet();
    final active = provider.selectedLetter;
    return Container(
      width: 26,
      color: OutlookTheme.folderPaneBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height =
              (constraints.maxHeight / letters.length).clamp(14.0, 22.0);
          return ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final letter in letters)
                    _LetterButton(
                      key: ValueKey('people-letter-$letter'),
                      letter: letter,
                      height: height,
                      isActive: letter == active,
                      isAvailable: available.contains(letter),
                      onTap: () => provider
                          .setLetterFilter(letter == active ? null : letter),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LetterButton extends StatefulWidget {
  final String letter;
  final double height;
  final bool isActive;
  final bool isAvailable;
  final VoidCallback onTap;

  const _LetterButton({
    super.key,
    required this.letter,
    required this.height,
    required this.isActive,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  State<_LetterButton> createState() => _LetterButtonState();
}

class _LetterButtonState extends State<_LetterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // The active letter stays clickable (to clear the filter) even if its
    // contacts were deleted meanwhile.
    final enabled = widget.isAvailable || widget.isActive;
    final Color color;
    if (widget.isActive) {
      color = Colors.white;
    } else if (widget.isAvailable) {
      color = OutlookTheme.textPrimary;
    } else {
      color = OutlookTheme.textMuted.withValues(alpha: 0.6);
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onTap : null,
        child: Container(
          height: widget.height,
          alignment: Alignment.center,
          color: widget.isActive
              ? OutlookTheme.primaryBlue
              : _hovered && enabled
                  ? OutlookTheme.hoverColor
                  : Colors.transparent,
          child: Text(
            widget.letter,
            style: TextStyle(
              fontFamily: OutlookTheme.fontFamily,
              fontFamilyFallback: OutlookTheme.fontFamilyFallback,
              fontSize: 11,
              fontWeight: widget.isAvailable || widget.isActive
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
