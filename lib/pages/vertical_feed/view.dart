import 'dart:async';

import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/vertical_feed/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:flutter/material.dart';
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
              owner: item.owner?.name ?? '',
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
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 42,
              ),
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
    required this.owner,
  });

  final VerticalFeedController controller;
  final int index;
  final String title;
  final String owner;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  double? _previousSpeed;

  bool _speedBoostActive = false;
  bool _showPaused = false;
  bool _showBuffering = false;

  Timer? _bufferTimer;

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

  void _handleTap() {}

  Future<void> _handleDoubleTap() async {
    final wasPlaying = controller.player.playerStatus.isPlaying;
    await controller.togglePlayPause();
    if (!mounted) return;
    setState(() {
      _showPaused = wasPlaying;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _toggleLike() async {
    if (controller.liking.value) return;

    if (!Accounts.video.isLogin) {
      _showMessage('请先登录哔哩哔哩账号');
      return;
    }

    final success = await controller.toggleLike();
    if (!mounted) return;

    _showMessage(
      success
          ? (controller.liked.value ? '点赞成功' : '已取消点赞')
          : '操作失败，请检查网络',
    );
  }

  Future<void> _shareVideo() async {
    if (widget.index < 0 || widget.index >= controller.videos.length) {
      _showMessage('无法获取视频信息');
      return;
    }

    final item = controller.videos[widget.index];
    final bvid = item.bvid;
    if (bvid == null || bvid.isEmpty) {
      _showMessage('无法获取视频链接');
      return;
    }

    await ShareUtils.shareText(
      '${item.title ?? '哔哩哔哩视频'}\n'
      'https://www.bilibili.com/video/$bvid',
    );
  }

  void _showSettingsMenu() {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF202020),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Obx(() {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '播放设置',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text(
                    '显示弹幕',
                    style: TextStyle(color: Colors.white),
                  ),
                  secondary: const Icon(
                    Icons.subtitles_outlined,
                    color: Colors.white,
                  ),
                  value: controller.player.enableShowDanmaku.value,
                  activeThumbColor: Colors.pinkAccent,
                  onChanged: (value) {
                    controller.player.enableShowDanmaku.value = value;
                  },
                ),
                const Divider(color: Colors.white12),
                _modeTile(
                  sheetContext,
                  '自动连播',
                  VerticalFeedPlayMode.autoNext,
                ),
                _modeTile(
                  sheetContext,
                  '循环当前视频',
                  VerticalFeedPlayMode.loopCurrent,
                ),
                _modeTile(
                  sheetContext,
                  '播完停止',
                  VerticalFeedPlayMode.stop,
                ),
                const SizedBox(height: 12),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _modeTile(
    BuildContext context,
    String title,
    VerticalFeedPlayMode mode,
  ) {
    final selected = controller.playMode.value == mode;

    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: selected ? Colors.pinkAccent : Colors.white,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: Colors.pinkAccent)
          : null,
      onTap: () {
        controller.setPlayMode(mode);
        Navigator.of(context).pop();
      },
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    return '${duration.inMinutes}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _onSeekStart(double value) {
    controller.player.isSeeking.value = true;
    controller.player.seekPosition.value = value.round();
    _bufferTimer?.cancel();
    if (mounted) {
      setState(() {
        _showBuffering = true;
      });
    }
  }

  void _onSeekEnd(double value) {
    controller.player.isSeeking.value = false;
    controller.player.seekTo(Duration(seconds: value.round()));
    _bufferTimer?.cancel();
    _bufferTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !controller.player.isBuffering.value) {
        setState(() {
          _showBuffering = false;
        });
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
                onTap: _handleTap,
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

                      final videoWidth = controller.player.width ?? 0;
                      final videoHeight = controller.player.height ?? 0;
                      final videoLandscape = videoWidth > videoHeight;

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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.owner.isNotEmpty)
                            Text(
                              '@${widget.owner}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 14 : 16,
                                fontWeight: FontWeight.w600,
                              ),
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
                      ),
                    ),

                    Positioned(
                      right: 8,
                      bottom: landscape ? 66 : (compact ? 92 : 112),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Obx(() {
                            return _FeedIconButton(
                              icon: controller.liked.value
                                  ? Icons.thumb_up_alt
                                  : Icons.thumb_up_alt_outlined,
                              active: controller.liked.value,
                              loading: controller.liking.value,
                              onTap: _toggleLike,
                            );
                          }),
                          SizedBox(height: compact ? 10 : 17),
                          _FeedIconButton(
                            icon: Icons.mode_comment_outlined,
                            onTap: () => _showMessage('评论面板尚未接入'),
                          ),
                          SizedBox(height: compact ? 10 : 17),
                          _FeedIconButton(
                            icon: Icons.monetization_on_outlined,
                            onTap: () => _showMessage('投币功能尚未接入'),
                          ),
                          SizedBox(height: compact ? 10 : 17),
                          _FeedIconButton(
                            icon: Icons.star_border_rounded,
                            onTap: () => _showMessage('收藏功能尚未接入'),
                          ),
                          SizedBox(height: compact ? 10 : 17),
                          _FeedIconButton(
                            icon: Icons.share_outlined,
                            onTap: _shareVideo,
                          ),
                        ],
                      ),
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
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: Colors.pinkAccent,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  min: 0,
                                  max: duration.toDouble(),
                                  value:
                                      progress.clamp(0, duration).toDouble(),
                                  onChangeStart: _onSeekStart,
                                  onChanged: (value) {
                                    player.seekPosition.value = value.round();
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

            // 顶栏在手势层外面，保证可点
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: IconButton(
                  tooltip: '返回',
                  onPressed: Get.back,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            Positioned(
              top: 0,
              right: 4,
              child: SafeArea(
                child: IconButton(
                  tooltip: '播放设置',
                  onPressed: _showSettingsMenu,
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeedIconButton extends StatelessWidget {
  const _FeedIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: loading ? null : onTap,
        radius: 28,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    icon,
                    color: active ? Colors.pinkAccent : Colors.white,
                    size: 29,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 5),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
