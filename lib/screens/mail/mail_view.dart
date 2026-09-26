import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/mail_provider.dart';
import '../../services/data_store.dart';
import '../../theme/outlook_theme.dart';
import '../../widgets/folder_pane.dart';
import '../../widgets/message_list.dart';
import '../../widgets/reading_pane.dart';

export 'compose_screen.dart' show ComposeScreen, ComposeMode;

/// The Mail module: folder pane | message list | reading pane, with
/// draggable splitters and the reading pane on the right, bottom or off.
class MailView extends StatefulWidget {
  final FocusNode? searchFocus;

  const MailView({super.key, this.searchFocus});

  @override
  State<MailView> createState() => _MailViewState();
}

class _MailViewState extends State<MailView> {
  late double _folderWidth;
  late double _listWidth;
  late double _listHeight;

  DataStore get _store => context.read<MailProvider>().store;

  @override
  void initState() {
    super.initState();
    final store = context.read<MailProvider>().store;
    _folderWidth =
        store.getInt('layout.folderWidth', defaultValue: 230).toDouble();
    _listWidth = store.getInt('layout.listWidth', defaultValue: 360).toDouble();
    _listHeight =
        store.getInt('layout.listHeight', defaultValue: 300).toDouble();
  }

  void _persist() {
    _store.setInt('layout.folderWidth', _folderWidth.round());
    _store.setInt('layout.listWidth', _listWidth.round());
    _store.setInt('layout.listHeight', _listHeight.round());
  }

  @override
  Widget build(BuildContext context) {
    final mail = context.watch<MailProvider>();
    final position = mail.readingPanePosition;

    return LayoutBuilder(builder: (context, constraints) {
      final maxFolder = (constraints.maxWidth * 0.35).clamp(160.0, 420.0);
      final folderWidth = _folderWidth.clamp(160.0, maxFolder);
      final remaining =
          constraints.maxWidth - (mail.showFolderPane ? folderWidth + 5 : 0);
      final listWidth =
          _listWidth.clamp(260.0, (remaining - 260).clamp(260.0, 900.0));
      final listHeight = _listHeight.clamp(
          120.0, (constraints.maxHeight - 160).clamp(120.0, 2000.0));

      final list = MessageList(searchFocus: widget.searchFocus);
      Widget content;
      switch (position) {
        case ReadingPanePosition.right:
          content = Row(
            children: [
              SizedBox(width: listWidth, child: list),
              _Splitter(
                axis: Axis.horizontal,
                onDrag: (d) => setState(() => _listWidth = listWidth + d),
                onEnd: _persist,
              ),
              const Expanded(child: ReadingPane()),
            ],
          );
          break;
        case ReadingPanePosition.bottom:
          content = Column(
            children: [
              SizedBox(height: listHeight, child: list),
              _Splitter(
                axis: Axis.vertical,
                onDrag: (d) => setState(() => _listHeight = listHeight + d),
                onEnd: _persist,
              ),
              const Expanded(child: ReadingPane()),
            ],
          );
          break;
        case ReadingPanePosition.off:
          content = list;
          break;
      }

      return Row(
        children: [
          if (mail.showFolderPane) ...[
            SizedBox(width: folderWidth, child: const FolderPane()),
            _Splitter(
              axis: Axis.horizontal,
              onDrag: (d) => setState(() => _folderWidth = folderWidth + d),
              onEnd: _persist,
            ),
          ],
          Expanded(child: content),
        ],
      );
    });
  }
}

/// A thin draggable divider between panes.
class _Splitter extends StatelessWidget {
  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  const _Splitter({
    required this.axis,
    required this.onDrag,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal ? (d) => onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: horizontal ? (_) => onEnd() : null,
        onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
        onVerticalDragEnd: horizontal ? null : (_) => onEnd(),
        child: SizedBox(
          width: horizontal ? 5 : double.infinity,
          height: horizontal ? double.infinity : 5,
          child: Center(
            child: Container(
              width: horizontal ? 1 : double.infinity,
              height: horizontal ? double.infinity : 1,
              color: OutlookTheme.dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
