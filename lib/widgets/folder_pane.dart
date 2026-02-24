import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/outlook_theme.dart';
import '../models/folder.dart';
import '../providers/mail_provider.dart';

/// Outlook 2013-style folder navigation pane.
class FolderPane extends StatelessWidget {
  const FolderPane({super.key});

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final folders = mail.folders;

    // Group folders: favorites at top, then by type
    final favorites = folders.where((f) =>
        f.type == FolderType.inbox ||
        f.type == FolderType.sent ||
        f.type == FolderType.drafts).toList();
    final allFolders = folders;

    return Container(
      width: OutlookTheme.folderPaneWidth,
      decoration: OutlookTheme.folderPaneDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar at top
          _SearchBar(),
          const Divider(height: 1),
          // Folder tree
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4),
              children: [
                // Favorites section
                if (favorites.isNotEmpty) ...[
                  const _SectionHeader(title: 'Favorites'),
                  ...favorites.map((f) => _FolderItem(
                        folder: f,
                        isSelected: mail.selectedFolder?.id == f.id,
                      )),
                  const SizedBox(height: 8),
                ],
                // All folders
                const _SectionHeader(title: 'Folders'),
                ...allFolders.map((f) => _FolderItem(
                      folder: f,
                      isSelected: mail.selectedFolder?.id == f.id,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mail = context.read<MailProvider>();
    return Container(
      height: 32,
      margin: const EdgeInsets.all(8),
      child: TextField(
        onChanged: mail.setSearchQuery,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Search mail...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: OutlookTheme.textMuted,
          ),
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          border: const OutlineInputBorder(
            borderSide: BorderSide(color: OutlookTheme.dividerColor),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          isDense: true,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: OutlookTheme.fontFamily,
          fontFamilyFallback: OutlookTheme.fontFamilyFallback,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: OutlookTheme.primaryBlue,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _FolderItem extends StatefulWidget {
  final MailFolder folder;
  final bool isSelected;

  const _FolderItem({required this.folder, required this.isSelected});

  @override
  State<_FolderItem> createState() => _FolderItemState();
}

class _FolderItemState extends State<_FolderItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.folder.unreadCount > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          context.read<MailProvider>().selectFolder(widget.folder);
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? OutlookTheme.selectedItemBackground
                : _isHovered
                    ? OutlookTheme.hoverColor
                    : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                widget.folder.icon,
                size: 16,
                color: widget.isSelected
                    ? OutlookTheme.primaryBlue
                    : OutlookTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.folder.name,
                  style: hasUnread
                      ? OutlookTheme.folderLabelBoldStyle
                      : OutlookTheme.folderLabelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasUnread)
                Text(
                  '${widget.folder.unreadCount}',
                  style: const TextStyle(
                    fontFamily: OutlookTheme.fontFamily,
                    fontFamilyFallback: OutlookTheme.fontFamilyFallback,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: OutlookTheme.primaryBlue,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
