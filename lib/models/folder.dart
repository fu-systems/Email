import 'package:flutter/material.dart';

/// Represents a mailbox folder (IMAP mailbox).
class MailFolder {
  final String id;
  final String accountId;
  final String name;
  final String path;
  final FolderType type;
  final String? parentId;
  final int unreadCount;
  final int totalCount;
  final bool isSubscribed;
  final List<MailFolder> children;

  const MailFolder({
    required this.id,
    required this.accountId,
    required this.name,
    required this.path,
    this.type = FolderType.other,
    this.parentId,
    this.unreadCount = 0,
    this.totalCount = 0,
    this.isSubscribed = true,
    this.children = const [],
  });

  MailFolder copyWith({
    String? id,
    String? accountId,
    String? name,
    String? path,
    FolderType? type,
    String? parentId,
    int? unreadCount,
    int? totalCount,
    bool? isSubscribed,
    List<MailFolder>? children,
  }) {
    return MailFolder(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      unreadCount: unreadCount ?? this.unreadCount,
      totalCount: totalCount ?? this.totalCount,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      children: children ?? this.children,
    );
  }

  IconData get icon {
    switch (type) {
      case FolderType.inbox:
        return Icons.inbox;
      case FolderType.sent:
        return Icons.send;
      case FolderType.drafts:
        return Icons.drafts;
      case FolderType.trash:
        return Icons.delete;
      case FolderType.spam:
        return Icons.report;
      case FolderType.archive:
        return Icons.archive;
      case FolderType.starred:
        return Icons.star;
      case FolderType.other:
        return Icons.folder;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'accountId': accountId,
        'name': name,
        'path': path,
        'type': type.name,
        'parentId': parentId,
        'unreadCount': unreadCount,
        'totalCount': totalCount,
        'isSubscribed': isSubscribed ? 1 : 0,
      };

  factory MailFolder.fromMap(Map<String, dynamic> map) => MailFolder(
        id: map['id'] as String,
        accountId: map['accountId'] as String,
        name: map['name'] as String,
        path: map['path'] as String,
        type: FolderType.values.byName(map['type'] as String),
        parentId: map['parentId'] as String?,
        unreadCount: map['unreadCount'] as int? ?? 0,
        totalCount: map['totalCount'] as int? ?? 0,
        isSubscribed: (map['isSubscribed'] as int?) == 1,
      );

  /// Try to detect folder type from its name/path.
  static FolderType detectType(String name) {
    final lower = name.toLowerCase();
    if (lower == 'inbox') return FolderType.inbox;
    if (lower.contains('sent')) return FolderType.sent;
    if (lower.contains('draft')) return FolderType.drafts;
    if (lower.contains('trash') || lower.contains('deleted')) {
      return FolderType.trash;
    }
    if (lower.contains('spam') || lower.contains('junk')) {
      return FolderType.spam;
    }
    if (lower.contains('archive')) return FolderType.archive;
    if (lower.contains('starred') || lower.contains('flagged')) {
      return FolderType.starred;
    }
    return FolderType.other;
  }
}

enum FolderType {
  inbox,
  sent,
  drafts,
  trash,
  spam,
  archive,
  starred,
  other,
}
