import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show Mode, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/vertical_feed/controller.dart';
import 'package:PiliPlus/utils/share_utils.dart';
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (controller.videos.isEmpty) {
          return _loadingOrError();
        }
        return PageView.builder(
          controller: pageController,
          scrollDirection: Axis.vertical,
          itemCount: controller.videos.length,
          onPageChanged: (index) {
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
            );
          },
        );
      }),
    );
  }

  Widget _loadingOrError() {
    return Center(
      child: Obx(() {
        if (controller.error.value != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 42),
              const SizedBox(height: 12),
              Text(
                controller.error.value!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.loadMore,
                child: const Text('重试'),
              ),
            ],
          );
        }
        return const CircularProgressIndicator();
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
  });

  final VerticalFeedController controller;
  final int index;
  final String title;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  double? _previousSpeed;
  bool _speedBoostActive = false;
  bool _showPaused = false;
  bool _showBuffering = false;
  Timer? _bufferTimer;

  // 0=无 1=设置 2=投币 3=评论
  int _panel = 0;
  bool _coinAlsoLike = true;

  VerticalFeedController get controller => widget.controller;

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

  void _showSettingsMenu() => setState(() => _panel = 1);

  void _showCoinSheet() {
    setState(() {
      _coinAlsoLike = true;
      _panel = 2;
    });
  }

  void _showComments() {
    if (controller.currentItem?.aid == null) {
      SmartDialog.showToast('无法获取视频信息');
      return;
    }
    setState(() => _panel = 3);
  }

  void _closePanel() {
    if (_panel != 0) setState(() => _panel = 0);
  }

  Widget _buildSettingsPanel() {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Text(
                  '播放设置',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('倍速', style: TextStyle(color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                            final selected = (speed - s).abs() < 0.01;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  s == 1.0 ? '1.0' : s.toString(),
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: Colors.pinkAccent,
                                backgroundColor: Colors.white12,
                                onSelected: (_) {
                                  controller.player.setPlaybackSpeed(s);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '自动连播',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: mode == VerticalFeedPlayMode.autoNext,
                  activeThumbColor: Colors.pinkAccent,
                  onChanged: (v) {
                    controller.setPlayMode(
                      v
                          ? VerticalFeedPlayMode.autoNext
                          : VerticalFeedPlayMode.loopCurrent,
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '循环当前',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: mode == VerticalFeedPlayMode.loopCurrent,
                  activeThumbColor: Colors.pinkAccent,
                  onChanged: (v) {
                    controller.setPlayMode(
                      v
                          ? VerticalFeedPlayMode.loopCurrent
                          : VerticalFeedPlayMode.autoNext,
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '显示弹幕',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: danmakuOn,
                  activeThumbColor: Colors.pinkAccent,
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

  Widget _buildCoinPanel() {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Text(
                '投币',
                style: TextStyle(
                  color: Colors.white,
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
                activeColor: Colors.pinkAccent,
                title: const Text(
                  '同时点赞',
                  style: TextStyle(color: Colors.white),
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
    if (mounted) setState(() => _showBuffering = true);
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
    _bufferTimer?.cancel();
    if (_speedBoostActive) {
      controller.player.setPlaybackSpeed(_previousSpeed ?? 1.0);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final landscape = width > height;
        final compact = height < 680 || landscape;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final progressBottom = bottomInset > 0 ? bottomInset + 8 : 24.0;

        return Stack(
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
                      if (!controller.ready.value || videoController == null) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      final vw = controller.player.width ?? 0;
                      final vh = controller.player.height ?? 0;
                      final videoLandscape = vw > vh;
                      final video = Video(
                        controller: videoController,
                        controls: NoVideoControls,
                        fit: videoLandscape ? BoxFit.contain : BoxFit.cover,
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
                      return IgnorePointer(
                        child: PlDanmaku(
                          cid: cid,
                          playerController: controller.player,
                          isPipMode: false,
                          isFullScreen: true,
                          isFileSource: false,
                          size: Size(width, height),
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
                                ClipOval(
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
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isEmpty ? 'UP主' : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: compact ? 14 : 16,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                      bottom: landscape ? 66 : (compact ? 92 : 112),
                      child: Obx(() {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _FeedIconButton(
                              icon: controller.liked.value
                                  ? Icons.thumb_up_alt
                                  : Icons.thumb_up_alt_outlined,
                              active: controller.liked.value,
                              loading: controller.liking.value,
                              label: controller.formatCount(
                                controller.likeCount.value,
                              ),
                              onTap: controller.toggleLike,
                            ),
                            SizedBox(height: compact ? 10 : 17),
                            _FeedIconButton(
                              icon: Icons.mode_comment_outlined,
                              label: controller.formatCount(
                                controller.replyCount.value,
                              ),
                              onTap: _showComments,
                            ),
                            SizedBox(height: compact ? 10 : 17),
                            _FeedIconButton(
                              icon: controller.coined.value
                                  ? Icons.monetization_on
                                  : Icons.monetization_on_outlined,
                              active: controller.coined.value,
                              loading: controller.coining.value,
                              label: controller.formatCount(
                                controller.coinCount.value,
                              ),
                              onTap: _showCoinSheet,
                            ),
                            SizedBox(height: compact ? 10 : 17),
                            _FeedIconButton(
                              icon: controller.faved.value
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              active: controller.faved.value,
                              loading: controller.faving.value,
                              label: controller.formatCount(
                                controller.favCount.value,
                              ),
                              onTap: controller.toggleFav,
                            ),
                            SizedBox(height: compact ? 10 : 17),
                            _FeedIconButton(
                              icon: Icons.share_outlined,
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
                      final buffering = controller.player.isBuffering.value;
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
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape:
                                      const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: Colors.pinkAccent,
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
            if (_panel != 0)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closePanel,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.black54),
                ),
              ),
            if (_panel == 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildSettingsPanel(),
              ),
            if (_panel == 2)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildCoinPanel(),
              ),
            if (_panel == 3)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: MediaQuery.sizeOf(context).height * 0.3,
                child: _CommentSheet(
                  aid: controller.currentItem!.aid!,
                  scrollController: ScrollController(),
                  onClose: _closePanel,
                ),
              ),
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
        );
      },
    );
  }
}

class _CoinChoice extends StatelessWidget {
  const _CoinChoice({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF3D3428),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              const Icon(
                Icons.monetization_on,
                color: Color(0xFFE8B86D),
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({
    required this.aid,
    required this.scrollController,
    this.onClose,
  });

  final int aid;
  final ScrollController scrollController;
  final VoidCallback? onClose;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final List<ReplyInfo> _replies = [];
  bool _loading = true;
  String? _error;
  Int64? _cursorNext;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ReplyGrpc.mainList(
        oid: widget.aid,
        type: 1,
        mode: Mode.MAIN_LIST_HOT,
        offset: null,
        cursorNext: _cursorNext,
      );
      if (!mounted) return;
      if (res case Success(:final response)) {
        _replies.addAll(response.replies);
        _cursorNext = response.cursor.next;
        _ended = response.cursor.isEnd;
        setState(() => _loading = false);
      } else if (res case Error(:final errMsg)) {
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  child: Text(
                    '评论',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _loading && _replies.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _replies.isEmpty
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _replies.length + (_ended ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (index >= _replies.length) {
                            if (!_loading) {
                              _load();
                            }
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final r = _replies[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipOval(
                                  child: NetworkImgLayer(
                                    src: r.member.face,
                                    width: 34,
                                    height: 34,
                                    type: ImageType.avatar,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.member.name,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        r.content.message,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool loading;
  final String? label;

  @override
  Widget build(BuildContext context) {
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
                          color: active ? Colors.pinkAccent : Colors.white,
                          size: 28,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 5),
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
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
