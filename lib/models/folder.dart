import 'package:flutter/material.dart';

/// Represents a mailbox folder (IMAP mailbox, Microsoft Graph mail folder,
/// or the POP3 inbox).
///
/// [path] is the IMAP path; for Graph folders it is the display path
/// ("Inbox/Projects"), so the folder tree, move dialogs and rules work the
/// same, and [remoteId] holds the Graph folder id.
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

  /// Hierarchy delimiter reported by the server (usually `/` or `.`).
  final String delimiter;

  /// False for `\Noselect` containers that cannot hold messages.
  final bool isSelectable;

  /// IMAP UIDVALIDITY; when it changes all cached UIDs are invalid.
  final int? uidValidity;

  /// Server id of the folder where the path isn't one (Microsoft Graph).
  final String? remoteId;

  /// Where incremental sync continues (a Graph delta link).
  final String? syncState;

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
    this.delimiter = '/',
    this.isSelectable = true,
    this.uidValidity,
    this.remoteId,
    this.syncState,
  });

  /// Stable id for a folder of an account.
  static String makeId(String accountId, String path) => '$accountId|$path';

  /// Nesting depth derived from the path (0 for top-level folders).
  int get depth {
    if (delimiter.isEmpty) return 0;
    return delimiter.allMatches(path).length;
  }

  /// Path of the parent folder, or null for top-level folders.
  String? get parentPath {
    if (delimiter.isEmpty) return null;
    final idx = path.lastIndexOf(delimiter);
    return idx > 0 ? path.substring(0, idx) : null;
  }

  /// Outlook-style display name for special folders.
  String get displayName {
    switch (type) {
      case FolderType.inbox:
        return 'Inbox';
      case FolderType.sent:
        return name.toLowerCase().contains('sent') ? name : 'Sent Items';
      case FolderType.trash:
        return name;
      default:
        return name;
    }
  }

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
    String? delimiter,
    bool? isSelectable,
    int? uidValidity,
    String? remoteId,
    String? syncState,
    bool clearSyncState = false,
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
      delimiter: delimiter ?? this.delimiter,
      isSelectable: isSelectable ?? this.isSelectable,
      uidValidity: uidValidity ?? this.uidValidity,
      remoteId: remoteId ?? this.remoteId,
      syncState: clearSyncState ? null : syncState ?? this.syncState,
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
      case FolderType.outbox:
        return Icons.outbox;
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
        'delimiter': delimiter,
        'isSelectable': isSelectable ? 1 : 0,
        'uidValidity': uidValidity,
        'remoteId': ?remoteId,
        'syncState': ?syncState,
      };

  factory MailFolder.fromMap(Map<String, dynamic> map) => MailFolder(
        id: map['id'] as String,
        accountId: map['accountId'] as String,
        name: map['name'] as String,
        path: map['path'] as String,
        type: FolderType.values.asNameMap()[map['type'] as String? ?? ''] ??
            FolderType.other,
        parentId: map['parentId'] as String?,
        unreadCount: map['unreadCount'] as int? ?? 0,
        totalCount: map['totalCount'] as int? ?? 0,
        isSubscribed: (map['isSubscribed'] as int? ?? 1) == 1,
        delimiter: map['delimiter'] as String? ?? '/',
        isSelectable: (map['isSelectable'] as int? ?? 1) == 1,
        uidValidity: map['uidValidity'] as int?,
        remoteId: map['remoteId'] as String?,
        syncState: map['syncState'] as String?,
      );

  /// Try to detect folder type from its name/path.
  static FolderType detectType(String name) {
    final lower = name.toLowerCase();
    if (lower == 'inbox') return FolderType.inbox;
    if (lower.contains('sent')) return FolderType.sent;
    if (lower.contains('draft')) return FolderType.drafts;
    if (lower.contains('trash') ||
        lower.contains('deleted') ||
        lower == 'bin') {
      return FolderType.trash;
    }
    if (lower.contains('spam') || lower.contains('junk')) {
      return FolderType.spam;
    }
    if (lower.contains('archive') || lower == 'all mail') {
      return FolderType.archive;
    }
    if (lower.contains('starred') || lower.contains('flagged')) {
      return FolderType.starred;
    }
    if (lower == 'outbox') return FolderType.outbox;
    return FolderType.other;
  }

  /// Sort key placing special folders first in Outlook order.
  int get sortRank {
    switch (type) {
      case FolderType.inbox:
        return 0;
      case FolderType.drafts:
        return 1;
      case FolderType.sent:
        return 2;
      case FolderType.trash:
        return 3;
      case FolderType.spam:
        return 4;
      case FolderType.archive:
        return 5;
      case FolderType.outbox:
        return 6;
      case FolderType.starred:
        return 7;
      case FolderType.other:
        return 10;
    }
  }

  /// Sorts folders so that each parent is followed by its children, with
  /// special folders first at the top level.
  static List<MailFolder> sortHierarchically(List<MailFolder> folders) {
    final byParent = <String?, List<MailFolder>>{};
    final paths = folders.map((f) => f.path).toSet();
    for (final f in folders) {
      var parent = f.parentPath;
      // Attach orphans (parent not listed) to the top level.
      if (parent != null && !paths.contains(parent)) parent = null;
      byParent.putIfAbsent(parent, () => []).add(f);
    }
    int compare(MailFolder a, MailFolder b) {
      final rank = a.sortRank.compareTo(b.sortRank);
      if (rank != 0) return rank;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    final result = <MailFolder>[];
    void visit(String? parent) {
      final children = byParent[parent];
      if (children == null) return;
      children.sort(compare);
      for (final child in children) {
        result.add(child);
        visit(child.path);
      }
    }

    visit(null);
    return result;
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
  outbox,
  other,
}
