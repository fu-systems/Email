import 'email_message.dart';

/// A mail rule (Outlook "Rules and Alerts"): when a new message arrives in an
/// inbox and matches the conditions, the actions are applied.
class MailRule {
  final String id;
  final String name;
  final bool isEnabled;

  /// Account the rule applies to, or null for all accounts.
  final String? accountId;

  /// When true every condition must match; otherwise any condition.
  final bool matchAll;
  final List<RuleCondition> conditions;

  // Actions
  /// Folder path (on the message's account) to move the message to.
  final String? moveToFolderPath;
  final bool markAsRead;
  final bool flag;
  final bool delete;

  /// Stop evaluating later rules after this one matched.
  final bool stopProcessing;

  const MailRule({
    required this.id,
    required this.name,
    this.isEnabled = true,
    this.accountId,
    this.matchAll = true,
    this.conditions = const [],
    this.moveToFolderPath,
    this.markAsRead = false,
    this.flag = false,
    this.delete = false,
    this.stopProcessing = false,
  });

  bool get hasActions =>
      moveToFolderPath != null || markAsRead || flag || delete;

  /// Whether this rule applies to [message].
  bool matches(EmailMessage message) {
    if (!isEnabled || conditions.isEmpty) return false;
    if (accountId != null && accountId != message.accountId) return false;
    return matchAll
        ? conditions.every((c) => c.matches(message))
        : conditions.any((c) => c.matches(message));
  }

  /// Human-readable summary, e.g. for the rules list.
  String get summary {
    final conds = conditions.map((c) => c.describe()).join(
          matchAll ? ' and ' : ' or ',
        );
    final actions = <String>[
      if (moveToFolderPath != null) 'move to "$moveToFolderPath"',
      if (markAsRead) 'mark as read',
      if (flag) 'flag',
      if (delete) 'delete',
    ];
    return 'If $conds then ${actions.isEmpty ? 'do nothing' : actions.join(', ')}';
  }

  MailRule copyWith({
    String? name,
    bool? isEnabled,
    String? accountId,
    bool clearAccount = false,
    bool? matchAll,
    List<RuleCondition>? conditions,
    String? moveToFolderPath,
    bool clearMoveTo = false,
    bool? markAsRead,
    bool? flag,
    bool? delete,
    bool? stopProcessing,
  }) {
    return MailRule(
      id: id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      accountId: clearAccount ? null : (accountId ?? this.accountId),
      matchAll: matchAll ?? this.matchAll,
      conditions: conditions ?? this.conditions,
      moveToFolderPath:
          clearMoveTo ? null : (moveToFolderPath ?? this.moveToFolderPath),
      markAsRead: markAsRead ?? this.markAsRead,
      flag: flag ?? this.flag,
      delete: delete ?? this.delete,
      stopProcessing: stopProcessing ?? this.stopProcessing,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'isEnabled': isEnabled,
        'accountId': accountId,
        'matchAll': matchAll,
        'conditions': conditions.map((c) => c.toMap()).toList(),
        'moveToFolderPath': moveToFolderPath,
        'markAsRead': markAsRead,
        'flag': flag,
        'delete': delete,
        'stopProcessing': stopProcessing,
      };

  factory MailRule.fromMap(Map<String, dynamic> map) => MailRule(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Rule',
        isEnabled: map['isEnabled'] != false,
        accountId: map['accountId'] as String?,
        matchAll: map['matchAll'] != false,
        conditions: (map['conditions'] as List? ?? const [])
            .map((c) => RuleCondition.fromMap((c as Map).cast<String, dynamic>()))
            .toList(),
        moveToFolderPath: map['moveToFolderPath'] as String?,
        markAsRead: map['markAsRead'] == true,
        flag: map['flag'] == true,
        delete: map['delete'] == true,
        stopProcessing: map['stopProcessing'] == true,
      );
}

enum RuleField {
  from,
  to,
  subject,
  body,
  hasAttachment,
  importanceHigh;

  String get label {
    switch (this) {
      case RuleField.from:
        return 'From';
      case RuleField.to:
        return 'Sent to (To/Cc)';
      case RuleField.subject:
        return 'Subject';
      case RuleField.body:
        return 'Body';
      case RuleField.hasAttachment:
        return 'Has attachment';
      case RuleField.importanceHigh:
        return 'Marked as high importance';
    }
  }

  /// Fields that take a text value (the others are simple predicates).
  bool get needsValue =>
      this == RuleField.from ||
      this == RuleField.to ||
      this == RuleField.subject ||
      this == RuleField.body;
}

/// A single "field contains text" condition (case-insensitive).
class RuleCondition {
  final RuleField field;
  final String value;

  const RuleCondition({required this.field, this.value = ''});

  bool matches(EmailMessage m) {
    final needle = value.trim().toLowerCase();
    bool contains(String haystack) =>
        needle.isNotEmpty && haystack.toLowerCase().contains(needle);

    switch (field) {
      case RuleField.from:
        return contains('${m.from.displayName ?? ''} ${m.from.address}');
      case RuleField.to:
        return [...m.to, ...m.cc]
            .any((a) => contains('${a.displayName ?? ''} ${a.address}'));
      case RuleField.subject:
        return contains(m.subject);
      case RuleField.body:
        return contains('${m.textBody ?? m.preview} ${m.htmlBody ?? ''}');
      case RuleField.hasAttachment:
        return m.hasAttachments;
      case RuleField.importanceHigh:
        return m.importance == MessageImportance.high;
    }
  }

  String describe() => field.needsValue
      ? '${field.label.toLowerCase()} contains "$value"'
      : field.label.toLowerCase();

  Map<String, dynamic> toMap() => {'field': field.name, 'value': value};

  factory RuleCondition.fromMap(Map<String, dynamic> map) => RuleCondition(
        field: RuleField.values.asNameMap()[map['field']] ?? RuleField.subject,
        value: map['value'] as String? ?? '',
      );
}

/// The combined effect of all matching rules on one message.
class RuleOutcome {
  final List<MailRule> matchedRules;
  final String? moveToFolderPath;
  final bool markAsRead;
  final bool flag;
  final bool delete;

  const RuleOutcome({
    this.matchedRules = const [],
    this.moveToFolderPath,
    this.markAsRead = false,
    this.flag = false,
    this.delete = false,
  });

  bool get isEmpty => matchedRules.isEmpty;

  /// Evaluates [rules] in order against [message]. The first move target
  /// wins; flags accumulate; a rule with stopProcessing ends evaluation.
  static RuleOutcome evaluate(List<MailRule> rules, EmailMessage message) {
    final matched = <MailRule>[];
    String? moveTo;
    var read = false;
    var flag = false;
    var delete = false;
    for (final rule in rules) {
      if (!rule.matches(message)) continue;
      matched.add(rule);
      moveTo ??= rule.moveToFolderPath;
      read |= rule.markAsRead;
      flag |= rule.flag;
      delete |= rule.delete;
      if (rule.stopProcessing) break;
    }
    return RuleOutcome(
      matchedRules: matched,
      moveToFolderPath: delete ? null : moveTo,
      markAsRead: read,
      flag: flag,
      delete: delete,
    );
  }
}
