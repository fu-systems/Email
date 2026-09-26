import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/email_account.dart';
import '../../models/email_message.dart';
import '../../models/folder.dart';
import '../../models/mail_rule.dart';
import '../../providers/mail_provider.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/common.dart';

/// A scrollable, indented folder list for picking a folder of one account.
class FolderPicker extends StatelessWidget {
  final List<MailFolder> folders;
  final String? selectedId;
  final ValueChanged<MailFolder> onSelected;
  final ValueChanged<MailFolder>? onDoubleTap;
  final double height;

  const FolderPicker({
    super.key,
    required this.folders,
    required this.selectedId,
    required this.onSelected,
    this.onDoubleTap,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    final visible = folders
        .where((f) => f.type != FolderType.outbox)
        .toList();
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: OutlookTheme.dividerColor),
      ),
      child: ListView.builder(
        itemCount: visible.length,
        itemExtent: 28,
        itemBuilder: (context, i) {
          final f = visible[i];
          final selected = f.id == selectedId;
          return InkWell(
            onTap: f.isSelectable ? () => onSelected(f) : null,
            onDoubleTap: f.isSelectable && onDoubleTap != null
                ? () => onDoubleTap!(f)
                : null,
            child: Container(
              color: selected ? OutlookTheme.selectedItemBackground : null,
              padding: EdgeInsets.only(left: 8.0 + 16 * f.depth, right: 8),
              child: Row(
                children: [
                  Icon(f.icon, size: 15, color: OutlookTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.displayName,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: f.isSelectable
                            ? OutlookTheme.textPrimary
                            : OutlookTheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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

/// Moves the selected messages to a folder the user picks.
Future<void> showMoveToFolderDialog(BuildContext context) async {
  final mail = context.read<MailProvider>();
  final targets = mail.selectedMessages.isNotEmpty
      ? mail.selectedMessages
      : [if (mail.selectedMessage != null) mail.selectedMessage!];
  if (targets.isEmpty) {
    showStatusMessage(context, 'Select a message to move');
    return;
  }
  final accountId = targets.first.accountId;
  final folders = mail.foldersOf(accountId);
  final target = await showDialog<MailFolder>(
    context: context,
    builder: (_) => _MoveDialog(folders: folders, count: targets.length),
  );
  if (target != null) await mail.moveMessage(target);
}

class _MoveDialog extends StatefulWidget {
  final List<MailFolder> folders;
  final int count;

  const _MoveDialog({required this.folders, required this.count});

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  MailFolder? _selected;

  @override
  Widget build(BuildContext context) {
    return OutlookDialog(
      title: 'Move Items',
      width: 380,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              _selected == null ? null : () => Navigator.of(context).pop(_selected),
          child: const Text('OK'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Move ${widget.count == 1 ? 'the selected item' : '${widget.count} items'} to the folder:',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          FolderPicker(
            folders: widget.folders,
            selectedId: _selected?.id,
            onSelected: (f) => setState(() => _selected = f),
            onDoubleTap: (f) => Navigator.of(context).pop(f),
          ),
        ],
      ),
    );
  }
}

/// Creates a folder in [accountId], under [parent] when given.
Future<void> showNewFolderDialog(
  BuildContext context, {
  required String accountId,
  MailFolder? parent,
}) async {
  final mail = context.read<MailProvider>();
  final name = await showTextInputDialog(
    context,
    title: 'Create New Folder',
    label: 'Name',
    hint: parent == null
        ? 'New folder at the top of the mailbox'
        : 'New folder inside "${parent.displayName}"',
    confirmLabel: 'Create',
  );
  if (name == null || !context.mounted) return;
  try {
    await mail.createFolder(accountId, name, parent: parent);
    if (context.mounted) showStatusMessage(context, 'Folder "$name" created');
  } catch (e) {
    if (context.mounted) {
      showStatusMessage(context, 'Could not create the folder: $e',
          isError: true);
    }
  }
}

/// Opens the rule editor pre-filled from [message] (Outlook's "Create Rule").
Future<void> showCreateRuleDialog(
    BuildContext context, EmailMessage message) async {
  final mail = context.read<MailProvider>();
  final rule = MailRule(
    id: const Uuid().v4(),
    name: 'Messages from ${message.from.display}',
    accountId: message.accountId,
    conditions: [
      RuleCondition(field: RuleField.from, value: message.from.address),
    ],
  );
  final result = await showDialog<MailRule>(
    context: context,
    builder: (_) => RuleEditorDialog(rule: rule, isNew: true),
  );
  if (result == null || !context.mounted) return;
  mail.saveRules([...mail.rules, result]);
  final runNow = await showConfirmDialog(
    context,
    title: 'Rule Created',
    message: 'The rule "${result.name}" has been created. Run it now on '
        'messages already in the Inbox?',
    confirmLabel: 'Run Now',
  );
  if (runNow && context.mounted) {
    final inbox = mail.folderByType(message.accountId, FolderType.inbox);
    if (inbox != null) {
      final n = await mail.runRulesNow(inbox);
      if (context.mounted) {
        showStatusMessage(context, 'Rules applied to $n message(s)');
      }
    }
  }
}

/// Outlook's "Rules and Alerts" manager.
class RulesDialog extends StatefulWidget {
  const RulesDialog({super.key});

  @override
  State<RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<RulesDialog> {
  late List<MailRule> _rules;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _rules = List.of(context.read<MailProvider>().rules);
  }

  Future<void> _edit(int? index) async {
    final isNew = index == null;
    final rule = isNew
        ? MailRule(
            id: const Uuid().v4(),
            name: 'New rule',
            conditions: const [RuleCondition(field: RuleField.subject)],
          )
        : _rules[index];
    final result = await showDialog<MailRule>(
      context: context,
      builder: (_) => RuleEditorDialog(rule: rule, isNew: isNew),
    );
    if (result == null) return;
    setState(() {
      if (isNew) {
        _rules.add(result);
        _selected = _rules.length - 1;
      } else {
        _rules[index] = result;
      }
    });
  }

  void _move(int delta) {
    final i = _selected;
    if (i == null) return;
    final j = i + delta;
    if (j < 0 || j >= _rules.length) return;
    setState(() {
      final r = _rules.removeAt(i);
      _rules.insert(j, r);
      _selected = j;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mail = context.read<MailProvider>();
    return OutlookDialog(
      title: 'Rules and Alerts',
      width: 640,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () async {
            mail.saveRules(_rules);
            var total = 0;
            for (final a in mail.accounts) {
              final inbox = mail.folderByType(a.id, FolderType.inbox);
              if (inbox != null) total += await mail.runRulesNow(inbox);
            }
            if (context.mounted) {
              showStatusMessage(context, 'Rules applied to $total message(s)');
            }
          },
          child: const Text('Run Rules Now'),
        ),
        ElevatedButton(
          onPressed: () {
            mail.saveRules(_rules);
            Navigator.of(context).pop();
          },
          child: const Text('OK'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HoverButton(
                icon: Icons.add,
                label: 'New Rule...',
                onTap: () => _edit(null),
              ),
              HoverButton(
                icon: Icons.edit_outlined,
                label: 'Change Rule...',
                onTap: _selected == null ? null : () => _edit(_selected),
              ),
              HoverButton(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: _selected == null
                    ? null
                    : () => setState(() {
                          _rules.removeAt(_selected!);
                          _selected = null;
                        }),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: _selected == null ? null : () => _move(-1),
              ),
              IconButton(
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed: _selected == null ? null : () => _move(1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: OutlookTheme.dividerColor),
            ),
            child: _rules.isEmpty
                ? const Center(
                    child: Text(
                      'No rules yet. Rules run on new messages that arrive '
                      'in your Inbox.',
                      style: TextStyle(color: OutlookTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: _rules.length,
                    itemBuilder: (context, i) {
                      final r = _rules[i];
                      final account = r.accountId == null
                          ? null
                          : mail.accountById(r.accountId!);
                      return InkWell(
                        onTap: () => setState(() => _selected = i),
                        onDoubleTap: () => _edit(i),
                        child: Container(
                          color: _selected == i
                              ? OutlookTheme.selectedItemBackground
                              : null,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Checkbox(
                                value: r.isEnabled,
                                onChanged: (v) => setState(() => _rules[i] =
                                    r.copyWith(isEnabled: v ?? false)),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      '${account == null ? 'All accounts' : account.emailAddress} · ${r.summary}',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: OutlookTheme.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rules are applied in order to new messages arriving in the Inbox '
            'of each account.',
            style: TextStyle(fontSize: 11.5, color: OutlookTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Edits a single rule: conditions, account and actions.
class RuleEditorDialog extends StatefulWidget {
  final MailRule rule;
  final bool isNew;

  const RuleEditorDialog({super.key, required this.rule, this.isNew = false});

  @override
  State<RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<RuleEditorDialog> {
  late final TextEditingController _name;
  late List<RuleCondition> _conditions;
  late List<TextEditingController> _values;
  late bool _matchAll;
  String? _accountId;
  String? _moveTo;
  late bool _markRead;
  late bool _flag;
  late bool _delete;
  late bool _stop;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _name = TextEditingController(text: r.name);
    _conditions = List.of(r.conditions);
    _values = _conditions.map((c) => TextEditingController(text: c.value)).toList();
    _matchAll = r.matchAll;
    _accountId = r.accountId;
    _moveTo = r.moveToFolderPath;
    _markRead = r.markAsRead;
    _flag = r.flag;
    _delete = r.delete;
    _stop = r.stopProcessing;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final conditions = <RuleCondition>[
      for (var i = 0; i < _conditions.length; i++)
        RuleCondition(field: _conditions[i].field, value: _values[i].text.trim()),
    ];
    if (conditions.isEmpty) {
      setState(() => _error = 'Add at least one condition.');
      return;
    }
    if (conditions.any((c) => c.field.needsValue && c.value.isEmpty)) {
      setState(() => _error = 'Enter text for every condition.');
      return;
    }
    if (_moveTo == null && !_markRead && !_flag && !_delete) {
      setState(() => _error = 'Choose at least one action.');
      return;
    }
    if (_moveTo != null && _accountId == null) {
      setState(() => _error =
          'Moving to a folder needs a specific account (folders differ '
          'between accounts).');
      return;
    }
    Navigator.of(context).pop(MailRule(
      id: widget.rule.id,
      name: _name.text.trim().isEmpty ? 'Rule' : _name.text.trim(),
      isEnabled: widget.rule.isEnabled,
      accountId: _accountId,
      matchAll: _matchAll,
      conditions: conditions,
      moveToFolderPath: _delete ? null : _moveTo,
      markAsRead: _markRead,
      flag: _flag,
      delete: _delete,
      stopProcessing: _stop,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mail = context.read<MailProvider>();
    final List<EmailAccount> accounts = mail.accounts;
    final folders = _accountId == null ? <MailFolder>[] : mail.foldersOf(_accountId!);

    return OutlookDialog(
      title: widget.isNew ? 'Create Rule' : 'Change Rule',
      width: 600,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('OK')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Rule name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Apply to'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All accounts')),
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.emailAddress)),
            ],
            onChanged: (v) => setState(() {
              _accountId = v;
              _moveTo = null;
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('When a message arrives and ',
                  style: TextStyle(fontSize: 13)),
              DropdownButton<bool>(
                value: _matchAll,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: true, child: Text('all conditions match')),
                  DropdownMenuItem(value: false, child: Text('any condition matches')),
                ],
                onChanged: (v) => setState(() => _matchAll = v ?? true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _conditions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<RuleField>(
                      initialValue: _conditions[i].field,
                      isDense: true,
                      items: [
                        for (final f in RuleField.values)
                          DropdownMenuItem(
                              value: f,
                              child: Text(f.label,
                                  style: const TextStyle(fontSize: 12.5))),
                      ],
                      onChanged: (f) => setState(() =>
                          _conditions[i] = RuleCondition(field: f ?? RuleField.subject)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_conditions[i].field.needsValue) ...[
                    const Text('contains', style: TextStyle(fontSize: 12.5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _values[i],
                        decoration: const InputDecoration(hintText: 'text'),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  IconButton(
                    tooltip: 'Remove condition',
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    onPressed: () => setState(() {
                      _conditions.removeAt(i);
                      _values.removeAt(i).dispose();
                    }),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: HoverButton(
              icon: Icons.add,
              label: 'Add condition',
              onTap: () => setState(() {
                _conditions.add(const RuleCondition(field: RuleField.subject));
                _values.add(TextEditingController());
              }),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Do the following:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _moveTo != null && !_delete,
            onChanged: _delete || _accountId == null
                ? null
                : (v) => setState(() {
                      _moveTo = v == true
                          ? folders
                              .where((f) =>
                                  f.isSelectable &&
                                  f.type != FolderType.inbox &&
                                  f.type != FolderType.outbox)
                              .firstOrNull
                              ?.path
                          : null;
                    }),
            title: Row(
              children: [
                const Text('Move the item to folder',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                if (_moveTo != null && !_delete)
                  Expanded(
                    child: DropdownButton<String>(
                      value: _moveTo,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final f in folders.where((f) =>
                            f.isSelectable && f.type != FolderType.outbox))
                          DropdownMenuItem(
                            value: f.path,
                            child: Padding(
                              padding: EdgeInsets.only(left: 12.0 * f.depth),
                              child: Text(f.displayName,
                                  style: const TextStyle(fontSize: 12.5)),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _moveTo = v),
                    ),
                  ),
                if (_accountId == null)
                  const Expanded(
                    child: Text(' (choose an account above)',
                        style: TextStyle(
                            fontSize: 12, color: OutlookTheme.textMuted)),
                  ),
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _markRead,
            onChanged: (v) => setState(() => _markRead = v ?? false),
            title: const Text('Mark it as read', style: TextStyle(fontSize: 13)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _flag,
            onChanged: (v) => setState(() => _flag = v ?? false),
            title: const Text('Flag it for follow up',
                style: TextStyle(fontSize: 13)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _delete,
            onChanged: (v) => setState(() => _delete = v ?? false),
            title: const Text('Delete it', style: TextStyle(fontSize: 13)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _stop,
            onChanged: (v) => setState(() => _stop = v ?? false),
            title: const Text('Stop processing more rules',
                style: TextStyle(fontSize: 13)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(
                      fontSize: 12, color: OutlookTheme.flaggedColor)),
            ),
        ],
      ),
    );
  }
}
