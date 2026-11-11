import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show Mode, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/vertical_feed/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:PiliPlus/pages/video/reply_new/view.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VerticalFeedPage extends StatefulWidget {
  const VerticalFeedPage({super.key});

  @override
  State<VerticalFeedPage> createState() => _VerticalFeedPageState();
}

class _VerticalFeedPageState extends State<VerticalFeedPage>
    with AutomaticKeepAliveClientMixin {
  late final VerticalFeedController controller =
      Get.put(VerticalFeedController());

  final PageController pageController = PageController();

  // 二级回复面板打开时，允许路由先处理 MiniScaffold 的 LocalHistoryEntry。
  final RxBool _replyPanelOpen = false.obs;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    controller.onCompleted = (index) {
      if (pageController.hasClients) {
        pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    };
  }

  @override
  void dispose() {
    controller.onCompleted = null;
    pageController.dispose();
    if (Get.isRegistered<VerticalFeedController>()) {
      Get.delete<VerticalFeedController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() {
      final panelOpen = controller.panelOpen.value;
      return PopScope(
        canPop: !panelOpen || _replyPanelOpen.value,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop &&
              controller.panelOpen.value &&
              !_replyPanelOpen.value) {
            controller.panelOpen.value = false;
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: controller.videos.isEmpty
              ? _loadingOrError()
              : PageView.builder(
                  controller: pageController,
                  scrollDirection: Axis.vertical,
                  physics: panelOpen
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: controller.videos.length,
                  onPageChanged: (index) {
                    controller.closePanel();
                    controller.playIndex(index);
                    if (index >= controller.videos.length - 3) {
                      controller.loadMore();
                    }
                  },
                  itemBuilder: (context, index) {
                    final item = controller.videos[index];
                    return _VideoPage(
                      key: ValueKey(item.bvid ?? item.aid),
                      controller: controller,
                      index: index,
                      title: item.title ?? '',
                      replyPanelOpen: _replyPanelOpen,
                    );
                  },
                ),
        ),
      );
    });
  }

  Widget _loadingOrError() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Obx(() {
        if (controller.error.value != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: scheme.onSurface, size: 42),
              const SizedBox(height: 12),
              Text(
                controller.error.value!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.loadMore,
                child: const Text('重试'),
              ),
            ],
          );
        }
        return CircularProgressIndicator(color: scheme.primary);
      }),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.controller,
    required this.index,
    required this.title,
    required this.replyPanelOpen,
  });

  final VerticalFeedController controller;
  final int index;
  final String title;
  final RxBool replyPanelOpen;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  Worker? _panelWorker;
  Worker? _indexWorker;

  double? _previousSpeed;
  bool _speedBoostActive = false;
  bool _showPaused = false;
  bool _showBuffering = false;
  Timer? _bufferTimer;

  int _panel = 0;
  bool _coinAlsoLike = true;

  final GlobalKey<_CommentSheetState> _commentKey =
      GlobalKey<_CommentSheetState>();

  final GlobalKey<MiniScaffoldState> _replyMiniScaffoldKey =
      GlobalKey<MiniScaffoldState>();
  dynamic _replyReplySheet;

  VerticalFeedController get controller => widget.controller;

  @override
  void initState() {
    super.initState();

    _panelWorker = ever(controller.panelOpen, (open) {
      if (!open) {
        _closeReplyReplyPanel();
        if (_panel != 0 && mounted) {
          setState(() => _panel = 0);
        }
      }
    });

    _indexWorker = ever(controller.currentIndex, (index) {
      if (index != widget.index) {
        _closeReplyReplyPanel();
        if (_panel != 0 && mounted) {
          setState(() => _panel = 0);
        }
      }
    });
  }

  Future<void> _startFastPlayback() async {
    if (_speedBoostActive || !controller.ready.value) return;
    if (!controller.player.playerStatus.isPlaying) return;

    _previousSpeed = controller.player.playbackSpeed;
    _speedBoostActive = true;

    if (mounted) setState(() {});

    await controller.player.setPlaybackSpeed(3.0);
  }

  Future<void> _stopFastPlayback() async {
    if (!_speedBoostActive) return;

    final speed = _previousSpeed ?? 1.0;

    _speedBoostActive = false;
    _previousSpeed = null;

    if (mounted) setState(() {});

    await controller.player.setPlaybackSpeed(speed);
  }

  Future<void> _handleDoubleTap() async {
    final wasPlaying = controller.player.playerStatus.isPlaying;

    await controller.togglePlayPause();

    if (!mounted) return;

    setState(() => _showPaused = wasPlaying);
  }

  Future<void> _shareVideo() async {
    final item = controller.currentItem;
    final bvid = item?.bvid;

    if (bvid == null || bvid.isEmpty) {
      SmartDialog.showToast('无法获取视频链接');
      return;
    }

    await ShareUtils.shareText(
      '${item?.title ?? '哔哩哔哩视频'}\nhttps://www.bilibili.com/video/$bvid',
    );
  }

  void _setPanel(int v) {
    setState(() => _panel = v);
    controller.panelOpen.value = v != 0;
  }

  void _showSettingsMenu() => _setPanel(1);

  void _showCoinSheet() {
    _coinAlsoLike = true;
    _setPanel(2);
  }

  void _showComments() {
    if (controller.currentItem?.aid == null) {
      SmartDialog.showToast('无法获取视频信息');
      return;
    }
    _setPanel(3);
  }

  void _closePanel() {
    if (_panel != 0) {
      _setPanel(0);
    }
  }

  void _openReplyEditor({
    ReplyInfo? replyItem,
    void Function(ReplyInfo info)? onPosted,
  }) {
    final aid = controller.currentItem?.aid;

    if (aid == null) {
      SmartDialog.showToast('无法获取视频信息');
      return;
    }

    if (!controller.isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }

    Get.key.currentState
        ?.push(
      PublishRoute(
        pageBuilder: (context, animation, secondaryAnimation) {
          return ReplyPage(
            oid: aid,
            root: replyItem?.id.toInt() ?? 0,
            parent: replyItem?.id.toInt() ?? 0,
            replyType: 1,
            replyItem: replyItem,
          );
        },
      ),
    )
        .then((result) {
      if (result is ReplyInfo) {
        onPosted?.call(result);
      }
    });
  }

  // 在当前竖屏视频页上方打开原版二级回复面板。
  // 一级评论仍留在原位置，视频不会因打开回复面板而暂停。
  void _openReplyReply(ReplyInfo item, int? id) {
    if (widget.replyPanelOpen.value) return;

    final miniScaffold = _replyMiniScaffoldKey.currentState;
    if (miniScaffold == null) {
      SmartDialog.showToast('回复面板尚未准备好');
      return;
    }

    late final dynamic sheet;
    try {
      sheet = miniScaffold.showBottomSheet(
        (context) => VideoReplyReplyPanel(
          enableSlide: false,
          oid: item.oid.toInt(),
          rpid: item.id.toInt(),
          id: id,
          firstFloor: item,
          replyType: 1,
          isVideoDetail: true,
          isNested: true,
          upMid: Int64(controller.ownerMid.value),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        enableDrag: true,
      );
    } catch (e) {
      SmartDialog.showToast('无法打开回复面板：$e');
      return;
    }

    _replyReplySheet = sheet;
    widget.replyPanelOpen.value = true;

    sheet.completer.future.whenComplete(() {
      if (identical(_replyReplySheet, sheet)) {
        _replyReplySheet = null;
        widget.replyPanelOpen.value = false;
      }
    });
  }

  void _closeReplyReplyPanel() {
    final sheet = _replyReplySheet;
    if (sheet != null) {
      sheet.close();
    } else if (widget.replyPanelOpen.value) {
      widget.replyPanelOpen.value = false;
    }
  }

  static const Color _panelDarkBg = Color(0xFF1C1C1E);

  Color _panelBg(ColorScheme scheme, Brightness brightness) =>
      _panelDarkBg;

  Widget _buildSettingsPanel(ColorScheme scheme) {
    const onPanel = Colors.white;

    return Material(
      color: _panelDarkBg,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(16),
      ),
      child: SafeArea(
        top: false,
        child: Obx(() {
          final speed = controller.player.playbackSpeed;
          final danmakuOn = controller.player.enableShowDanmaku.value;
          final mode = controller.playMode.value;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _closePanel,
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Text(
                  '播放设置',
                  style: TextStyle(
                    color: onPanel,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '倍速',
                    style: TextStyle(
                      color: onPanel,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                    final selected = (speed - s).abs() < 0.01;
                    final label = s == 1.0 ? '1.0x' : '${s}x';

                    return Material(
                      color: selected
                          ? scheme.primary
                          : const Color(0xFF3A3A3C),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () => controller.player.setPlaybackSpeed(s),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: selected ? scheme.onPrimary : onPanel,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '播放模式',
                    style: TextStyle(
                      color: onPanel,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    (VerticalFeedPlayMode.autoNext, '自动连播'),
                    (VerticalFeedPlayMode.loopCurrent, '循环当前'),
                    (VerticalFeedPlayMode.stop, '播完暂停'),
                  ].map((e) {
                    final selected = mode == e.$1;

                    return Material(
                      color: selected
                          ? scheme.primary
                          : const Color(0xFF3A3A3C),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () => controller.setPlayMode(e.$1),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            e.$2,
                            style: TextStyle(
                              color: selected ? scheme.onPrimary : onPanel,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '显示弹幕',
                    style: TextStyle(color: onPanel),
                  ),
                  value: danmakuOn,
                  activeThumbColor: scheme.primary,
                  onChanged: (v) {
                    controller.player.enableShowDanmaku.value = v;
                  },
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCoinPanel(ColorScheme scheme) {
    const onPanel = Colors.white;

    return Material(
      color: _panelDarkBg,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(16),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _closePanel,
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Text(
                '投币',
                style: TextStyle(
                  color: onPanel,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _CoinChoice(
                      label: '1 硬币',
                      scheme: scheme,
                      onTap: () {
                        final also = _coinAlsoLike;
                        _closePanel();
                        controller.coin(1, alsoLike: also);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CoinChoice(
                      label: '2 硬币',
                      scheme: scheme,
                      onTap: () {
                        final also = _coinAlsoLike;
                        _closePanel();
                        controller.coin(2, alsoLike: also);
                      },
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _coinAlsoLike,
                activeColor: scheme.primary,
                title: const Text(
                  '同时点赞',
                  style: TextStyle(color: onPanel),
                ),
                onChanged: (v) {
                  setState(() => _coinAlsoLike = v ?? true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    return '${duration.inMinutes}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String _formatFans(int n) {
    if (n >= 10000) {
      final v = n / 10000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}万粉丝';
    }
    return '$n粉丝';
  }

  void _onSeekStart(double value) {
    controller.player.isSeeking.value = true;
    controller.player.seekPosition.value = value.round();

    _bufferTimer?.cancel();

    if (mounted) {
      setState(() => _showBuffering = true);
    }
  }

  void _onSeekEnd(double value) {
    controller.player.isSeeking.value = false;
    controller.player.seekTo(Duration(seconds: value.round()));

    _bufferTimer?.cancel();

    _bufferTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !controller.player.isBuffering.value) {
        setState(() => _showBuffering = false);
      }
    });
  }

  @override
  void dispose() {
    _panelWorker?.dispose();
    _indexWorker?.dispose();
    _bufferTimer?.cancel();

    if (_speedBoostActive) {
      controller.player.setPlaybackSpeed(_previousSpeed ?? 1.0);
    }

    final replySheet = _replyReplySheet;
    if (replySheet != null) {
      replySheet.close();
      _replyReplySheet = null;
      widget.replyPanelOpen.value = false;
    }

    if (controller.panelOpen.value) {
      controller.panelOpen.value = false;
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final landscape = width > height;
        final compact = height < 680 || landscape;

        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final topInset = MediaQuery.paddingOf(context).top;

        final progressBottom =
            bottomInset > 0 ? bottomInset + 8 : 24.0;

        final danmakuTop = topInset + 48.0;

        return MiniScaffold(
          key: _replyMiniScaffoldKey,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _handleDoubleTap,
                  onLongPressStart: (_) => _startFastPlayback(),
                  onLongPressEnd: (_) => _stopFastPlayback(),
                  onLongPressCancel: _stopFastPlayback,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Obx(() {
                        if (controller.currentIndex.value != widget.index) {
                          return const SizedBox.shrink();
                        }

                        final videoController = controller.videoController;

                        if (!controller.ready.value ||
                            videoController == null) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: primary,
                            ),
                          );
                        }

                        final vw = controller.player.width ?? 0;
                        final vh = controller.player.height ?? 0;
                        final videoLandscape = vw > vh;

                        final video = Video(
                          controller: videoController,
                          controls: NoVideoControls,
                          fit: videoLandscape
                              ? BoxFit.contain
                              : BoxFit.cover,
                        );

                        if (!videoLandscape) {
                          return IgnorePointer(child: video);
                        }

                        return IgnorePointer(
                          child: Transform.translate(
                            offset: Offset(0, -height * 0.08),
                            child: video,
                          ),
                        );
                      }),
                      Obx(() {
                        if (controller.currentIndex.value != widget.index ||
                            !controller.ready.value ||
                            controller.videoController == null) {
                          return const SizedBox.shrink();
                        }

                        final cid = controller.videos[widget.index].cid;

                        if (cid == null || cid <= 0) {
                          return const SizedBox.shrink();
                        }

                        return Positioned(
                          left: 0,
                          right: 0,
                          top: danmakuTop,
                          bottom: 0,
                          child: IgnorePointer(
                            child: PlDanmaku(
                              cid: cid,
                              playerController: controller.player,
                              isPipMode: false,
                              isFullScreen: false,
                              isFileSource: false,
                              size: Size(width, height - danmakuTop),
                            ),
                          ),
                        );
                      }),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.18),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.65),
                                ],
                                stops: const [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 76,
                        bottom: compact ? 66 : 76,
                        child: Obx(() {
                          final face = controller.ownerFace.value;
                          final name = controller.ownerName.value;
                          final fans = controller.ownerFans.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      final mid = controller.ownerMid.value;
                                      if (mid > 0) {
                                        Get.toNamed('/member?mid=$mid');
                                      }
                                    },
                                    child: ClipOval(
                                      child: face.isNotEmpty
                                          ? NetworkImgLayer(
                                              src: face,
                                              width: 36,
                                              height: 36,
                                              type: ImageType.avatar,
                                            )
                                          : Container(
                                              width: 36,
                                              height: 36,
                                              color: Colors.white24,
                                              child: const Icon(
                                                Icons.person,
                                                color: Colors.white70,
                                                size: 22,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: GestureDetector(
                                      onTap: () {
                                        final mid = controller.ownerMid.value;
                                        if (mid > 0) {
                                          Get.toNamed('/member?mid=$mid');
                                        }
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  name.isEmpty ? 'UP主' : name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize:
                                                        compact ? 14 : 16,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Obx(() {
                                                final followed =
                                                    controller.followed.value;
                                                final loading =
                                                    controller.following.value;

                                                return Material(
                                                  color: followed
                                                      ? Colors.white24
                                                      : primary,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  child: InkWell(
                                                    onTap: loading
                                                        ? null
                                                        : controller
                                                            .toggleFollow,
                                                    borderRadius:
                                                        BorderRadius.circular(14),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                      child: loading
                                                          ? const SizedBox(
                                                              width: 12,
                                                              height: 12,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color:
                                                                    Colors.white,
                                                              ),
                                                            )
                                                          : Text(
                                                              followed
                                                                  ? '已关注'
                                                                  : '关注',
                                                              style:
                                                                  const TextStyle(
                                                                color:
                                                                    Colors.white,
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                          if (fans > 0)
                                            Text(
                                              _formatFans(fans),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.title,
                                maxLines: compact ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 13 : 15,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                      Positioned(
                        right: 8,
                        bottom: landscape
                            ? 66
                            : (compact ? 92 : 112),
                        child: Obx(() {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _FeedIconButton(
                                icon: controller.liked.value
                                    ? FontAwesomeIcons.solidThumbsUp
                                    : FontAwesomeIcons.thumbsUp,
                                active: controller.liked.value,
                                loading: controller.liking.value,
                                activeColor: primary,
                                label: controller.formatCount(
                                  controller.likeCount.value,
                                ),
                                onTap: controller.toggleLike,
                              ),
                              SizedBox(height: compact ? 10 : 17),
                              _FeedIconButton(
                                icon: Icons.mode_comment_outlined,
                                activeColor: primary,
                                label: controller.formatCount(
                                  controller.replyCount.value,
                                ),
                                onTap: _showComments,
                              ),
                              SizedBox(height: compact ? 10 : 17),
                              _FeedIconButton(
                                icon: FontAwesomeIcons.b,
                                active: controller.coined.value,
                                loading: controller.coining.value,
                                activeColor: primary,
                                label: controller.formatCount(
                                  controller.coinCount.value,
                                ),
                                onTap: _showCoinSheet,
                              ),
                              SizedBox(height: compact ? 10 : 17),
                              _FeedIconButton(
                                icon: controller.faved.value
                                    ? FontAwesomeIcons.solidStar
                                    : FontAwesomeIcons.star,
                                active: controller.faved.value,
                                loading: controller.faving.value,
                                activeColor: primary,
                                label: controller.formatCount(
                                  controller.favCount.value,
                                ),
                                onTap: controller.toggleFav,
                              ),
                              SizedBox(height: compact ? 10 : 17),
                              _FeedIconButton(
                                icon: FontAwesomeIcons.shareFromSquare,
                                activeColor: primary,
                                label: controller.formatCount(
                                  controller.shareCount.value,
                                ),
                                onTap: _shareVideo,
                              ),
                            ],
                          );
                        }),
                      ),
                      if (_showPaused)
                        const Center(
                          child: Icon(
                            Icons.pause_circle_filled,
                            color: Colors.white70,
                            size: 72,
                          ),
                        ),
                      if (_speedBoostActive)
                        Positioned(
                          top: 80,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                '3倍速中',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Obx(() {
                        final buffering =
                            controller.player.isBuffering.value;

                        if (buffering &&
                            controller.ready.value &&
                            !_showBuffering) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _showBuffering = true);
                            }
                          });
                        } else if (!buffering && _showBuffering) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _showBuffering = false);
                            }
                          });
                        }

                        if (!_showBuffering) {
                          return const SizedBox.shrink();
                        }

                        return const Center(
                          child: Text(
                            '加载中...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: progressBottom,
                        child: Obx(() {
                          final player = controller.player;
                          final duration = player.duration.value;
                          final progress = player.progress;

                          if (controller.currentIndex.value != widget.index ||
                              !controller.ready.value ||
                              duration <= 0) {
                            return const SizedBox(height: 18);
                          }

                          return Row(
                            children: [
                              Text(
                                _formatDuration(progress),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape:
                                        const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape:
                                        const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                    activeTrackColor: primary,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: duration.toDouble(),
                                    value: progress
                                        .clamp(0, duration)
                                        .toDouble(),
                                    onChangeStart: _onSeekStart,
                                    onChanged: (value) {
                                      player.seekPosition.value =
                                          value.round();
                                    },
                                    onChangeEnd: _onSeekEnd,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),

              // 评论、投币、播放设置面板。
              // 评论面板仅在打开时创建，关闭后立即从 Widget 树移除。
              Obx(() {
                if (controller.currentIndex.value != widget.index) {
                  return const SizedBox.shrink();
                }

                return Stack(
                  children: [
                    IgnorePointer(
                      ignoring: _panel == 0,
                      child: AnimatedOpacity(
                        opacity: _panel == 0 ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        child: GestureDetector(
                          onTap: _closePanel,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: _panel != 1,
                      child: AnimatedSlide(
                        offset: _panel == 1
                            ? Offset.zero
                            : const Offset(0, 1),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _buildSettingsPanel(scheme),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: _panel != 2,
                      child: AnimatedSlide(
                        offset: _panel == 2
                            ? Offset.zero
                            : const Offset(0, 1),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _buildCoinPanel(scheme),
                        ),
                      ),
                    ),

                    if (_panel == 3)
                      TweenAnimationBuilder<Offset>(
                        tween: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        builder: (context, offset, child) {
                          return FractionalTranslation(
                            translation: offset,
                            child: child,
                          );
                        },
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            height: height * 0.72,
                            child: _CommentSheet(
                              key: _commentKey,
                              aid: controller.currentItem?.aid ?? 0,
                              scheme: scheme,
                              onClose: _closePanel,
                              onOpenReplyReply: _openReplyReply,
                              upMid: Int64(controller.ownerMid.value),
                              onReply: ([item]) => _openReplyEditor(
                                replyItem: item,
                                onPosted: (info) {
                                  _commentKey.currentState?.insertReply(info);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: () {
                          if (_panel != 0) {
                            _closePanel();
                            return;
                          }

                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            Get.back();
                          }
                        },
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '播放设置',
                        onPressed: _showSettingsMenu,
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ],
            ),
        );
      },
    );
  }
}

class _CoinChoice extends StatelessWidget {
  const _CoinChoice({
    required this.label,
    required this.onTap,
    required this.scheme,
  });

  final String label;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF3A3A3C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(
                Icons.monetization_on,
                color: scheme.primary,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({
    super.key,
    required this.aid,
    required this.scheme,
    required this.onClose,
    required this.onOpenReplyReply,
    required this.upMid,
    this.onReply,
  });

  final int aid;
  final ColorScheme scheme;
  final VoidCallback onClose;
  final void Function(ReplyInfo item, int? id) onOpenReplyReply;
  final Int64 upMid;
  final void Function([ReplyInfo? replyItem])? onReply;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final List<ReplyInfo> _replies = [];
  final ScrollController _scrollController = ScrollController();

  bool _loading = false;
  String? _error;

  Int64? _cursorNext;
  bool _ended = false;

  // 每次请求都有独立编号。
  // 旧请求返回时，如果编号已经过期，就忽略结果。
  int _requestGeneration = 0;

  int _activeAid = 0;

  Mode _mode = Mode.MAIN_LIST_HOT;

  @override
  void initState() {
    super.initState();

    _activeAid = widget.aid;

    _scrollController.addListener(_onScroll);

    if (widget.aid > 0) {
      _load(refresh: true);
    }
  }

  @override
  void didUpdateWidget(covariant _CommentSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.aid != oldWidget.aid) {
      // 视频发生变化时，使旧请求失效。
      _requestGeneration++;

      _activeAid = widget.aid;

      _replies.clear();
      _cursorNext = null;
      _ended = false;
      _error = null;
      _loading = false;

      if (widget.aid > 0) {
        _load(refresh: true);
      }
    }
  }

  @override
  void dispose() {
    // 页面销毁后，所有未完成请求都视为过期。
    _requestGeneration++;

    _scrollController
      ..removeListener(_onScroll)
      ..dispose();

    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _ended ||
        widget.aid <= 0) {
      return;
    }

    final position = _scrollController.position;

    if (position.extentAfter < 500) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final aid = widget.aid;

    if (aid <= 0) return;

    // 普通分页请求不允许重复启动。
    // 刷新请求可以覆盖正在进行的旧请求。
    if (_loading && !refresh) return;

    if (!refresh && _ended) return;

    final generation = ++_requestGeneration;
    final requestMode = _mode;
    final requestCursor = refresh ? null : _cursorNext;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ReplyGrpc.mainList(
        oid: aid,
        type: 1,
        mode: requestMode,
        offset: null,
        cursorNext: requestCursor,
      );

      // 防止旧视频、旧排序或旧刷新请求覆盖当前列表。
      if (!mounted ||
          generation != _requestGeneration ||
          aid != widget.aid ||
          aid != _activeAid) {
        return;
      }

      if (res case Success(:final response)) {
        final incoming = response.replies;

        setState(() {
          if (refresh) {
            // 刷新成功后才替换列表。
            // 请求期间保留旧数据，避免评论区域闪空。
            _replies
              ..clear()
              ..addAll(incoming);
          } else {
            // 分页时去重，防止接口返回重复评论。
            final existingIds = _replies.map((e) => e.id).toSet();

            for (final reply in incoming) {
              if (existingIds.add(reply.id)) {
                _replies.add(reply);
              }
            }
          }

          _cursorNext = response.cursor.next;
          _ended = response.cursor.isEnd;

          _loading = false;
          _error = null;
        });
      } else if (res case Error(:final errMsg)) {
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      }
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _toggleSort() {
    setState(() {
      _mode = _mode == Mode.MAIN_LIST_HOT
          ? Mode.MAIN_LIST_TIME
          : Mode.MAIN_LIST_HOT;
    });

    _load(refresh: true);
  }

  void insertReply(ReplyInfo info) {
    if (!mounted) return;

    setState(() {
      _replies.removeWhere((e) => e.id == info.id);
      _replies.insert(0, info);
    });
  }

  void removeReply(ReplyInfo item, int? subIndex) {
    if (!mounted) return;

    setState(() {
      _replies.removeWhere((e) => e.id == item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 评论区直接使用当前系统主题，不再强制深色。
    final baseTheme = Theme.of(context);
    final scheme = baseTheme.colorScheme;

    return Theme(
      data: baseTheme.copyWith(
        brightness: baseTheme.brightness,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        cardColor: scheme.surface,
        canvasColor: scheme.surface,
        dividerColor: scheme.outlineVariant,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
        iconTheme: baseTheme.iconTheme.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _toggleSort,
                        child: Text(
                          _mode == Mode.MAIN_LIST_HOT ? '最热' : '最新',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '评论',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
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
                  color: scheme.outlineVariant,
                ),
                Expanded(
                  child: widget.aid <= 0
                      ? Center(
                          child: Text(
                            '暂无视频信息',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : _loading && _replies.isEmpty
                          ? Center(
                              child: CircularProgressIndicator(
                                color: scheme.primary,
                              ),
                            )
                          : _error != null && _replies.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _error!,
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            _load(refresh: true),
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  color: scheme.primary,
                                  onRefresh: () =>
                                      _load(refresh: true),
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(
                                      bottom: 88,
                                    ),
                                    itemCount: _replies.length +
                                        (!_ended ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index >= _replies.length) {
                                        return Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Center(
                                            child: _loading
                                                ? const CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )
                                                : TextButton(
                                                    onPressed: () => _load(),
                                                    child: const Text(
                                                      '加载更多',
                                                    ),
                                                  ),
                                          ),
                                        );
                                      }

                                      final reply = _replies[index];

                                      return ReplyItemGrpc(
                                        replyItem: reply,
                                        replyLevel: 1,
                                        upMid: widget.upMid,
                                        replyReply:
                                            widget.onOpenReplyReply,
                                        onReply: (item) {
                                          widget.onReply?.call(item);
                                        },
                                        onDelete: (item, subIndex) {
                                          removeReply(item, subIndex);
                                        },
                                        needDivider: true,
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: FloatingActionButton(
                heroTag: 'vf_reply_fab',
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                onPressed: () => widget.onReply?.call(),
                child: const Icon(Icons.reply_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedIconButton extends StatelessWidget {
  const _FeedIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.loading = false,
    this.label,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool loading;
  final String? label;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (activeColor ?? Theme.of(context).colorScheme.primary)
        : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: loading ? null : onTap,
        radius: 28,
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 40,
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          icon,
                          color: color,
                          size: 28,
                          shadows: const [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 5,
                            ),
                          ],
                        ),
                ),
              ),
              if (label != null && label!.isNotEmpty)
                Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.1,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
