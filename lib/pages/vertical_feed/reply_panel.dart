import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Vertical feed comments use PiliPlus's original ReplyController pagination,
/// refresh, sorting, posting, delete and moderation behavior.
class _VerticalFeedReplyController extends ReplyController<MainListReply> {
  _VerticalFeedReplyController({
    required this.aid,
    this.replyType = 1,
  });

  final int aid;
  final int replyType;

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() {
    return ReplyGrpc.mainList(
      oid: aid,
      type: replyType,
      mode: mode,
      cursorNext: cursorNext,
      offset: paginationReply?.nextOffset,
    );
  }
}

class VerticalFeedReplyPanel extends StatefulWidget {
  const VerticalFeedReplyPanel({
    super.key,
    required this.aid,
    required this.upMid,
    required this.enabled,
    required this.onClose,
    required this.onOpenReplyReply,
  });

  final int aid;
  final Int64 upMid;
  final bool enabled;
  final VoidCallback onClose;
  final void Function(ReplyInfo item, int? id) onOpenReplyReply;

  @override
  State<VerticalFeedReplyPanel> createState() =>
      _VerticalFeedReplyPanelState();
}

class _VerticalFeedReplyPanelState extends State<VerticalFeedReplyPanel> {
  late final String _tag;
  late final _VerticalFeedReplyController _replyController;
  bool _requestedInitialData = false;

  @override
  void initState() {
    super.initState();
    _tag = 'vertical_feed_reply_${identityHashCode(this)}';
    _replyController = Get.put(
      _VerticalFeedReplyController(aid: widget.aid),
      tag: _tag,
    );
    if (widget.enabled) {
      _requestInitialData();
    }
  }

  @override
  void didUpdateWidget(covariant VerticalFeedReplyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _requestInitialData();
    }
  }

  void _requestInitialData() {
    if (_requestedInitialData) return;
    _requestedInitialData = true;
    _replyController.queryData();
  }

  @override
  void dispose() {
    Get.delete<_VerticalFeedReplyController>(tag: _tag);
    super.dispose();
  }

  Widget _buildLoading(ColorScheme scheme) {
    return Center(
      child: CircularProgressIndicator(color: scheme.primary),
    );
  }

  Widget _buildError(ColorScheme scheme, String? message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              message?.isNotEmpty == true ? message! : '评论加载失败',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _replyController.onReload,
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentList(
    ColorScheme scheme,
    List<ReplyInfo> replies,
  ) {
    final itemCount = replies.isEmpty
        ? 1
        : replies.length + (_replyController.isEnd ? 0 : 1);

    return refreshIndicator(
      onRefresh: _replyController.onRefresh,
      child: ListView.builder(
        controller: _replyController.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 92 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (replies.isEmpty) {
            return SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  '还没有评论，下拉刷新试试',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }

          if (index >= replies.length) {
            if (!_replyController.isLoading && !_replyController.isEnd) {
              _replyController.onLoadMore();
            }
            return SizedBox(
              height: 64,
              child: Center(
                child: Text(
                  _replyController.isEnd ? '没有更多评论了' : '正在加载更多…',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }

          final item = replies[index];
          return ReplyItemGrpc(
            replyItem: item,
            replyLevel: 1,
            upMid: _replyController.upMid ?? widget.upMid,
            replyReply: widget.onOpenReplyReply,
            onReply: (reply) => _replyController.onReply(reply),
            onDelete: (reply, subIndex) {
              _replyController.onRemove(index, reply, subIndex);
            },
            onCheckReply: _replyController.onCheckReply,
            onToggleTop: (reply) {
              _replyController.onToggleTop(
                reply,
                index,
                widget.aid,
                1,
              );
            },
            needDivider: true,
          );
        },
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    final state = _replyController.loadingState.value;

    if (state is Loading) {
      return _buildLoading(scheme);
    }

    if (state is Error) {
      return _buildError(scheme, state.errMsg);
    }

    if (state is Success<List<ReplyInfo>?>) {
      return _buildCommentList(scheme, state.response ?? const []);
    }

    return _buildLoading(scheme);
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final scheme = baseTheme.colorScheme;

    final commentTheme = baseTheme.copyWith(
      brightness: scheme.brightness,
      colorScheme: scheme,
      canvasColor: scheme.surface,
      scaffoldBackgroundColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dividerColor: scheme.outlineVariant,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      iconTheme: baseTheme.iconTheme.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    return Theme(
      data: commentTheme,
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
              child: Row(
                children: [
                  Obx(() {
                    final sort = _replyController.sortType.value;
                    return Text(
                      sort.desc,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface,
                      ),
                    );
                  }),
                  const Spacer(),
                  Obx(() {
                    final sort = _replyController.sortType.value;
                    return TextButton.icon(
                      onPressed: _replyController.queryBySort,
                      icon: Icon(
                        Icons.sort,
                        size: 16,
                        color: scheme.secondary,
                      ),
                      label: Text(
                        sort.descShort,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.secondary,
                        ),
                      ),
                    );
                  }),
                  IconButton(
                    tooltip: '关闭评论',
                    onPressed: widget.onClose,
                    icon: Icon(
                      Icons.close,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
            Expanded(
              child: Obx(() => _buildBody(scheme)),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 12,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: FloatingActionButton(
                  heroTag: 'vf_reply_fab_${widget.aid}',
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  tooltip: '发表评论',
                  onPressed: () {
                    _replyController.onReply(
                      null,
                      oid: widget.aid,
                      replyType: 1,
                    );
                  },
                  child: const Icon(Icons.reply_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
