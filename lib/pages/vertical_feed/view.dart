import 'package:PiliPlus/pages/vertical_feed/controller.dart';
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
  late final VerticalFeedController controller = Get.put(
    VerticalFeedController(),
  );

  final pageController = PageController();

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
      body: Stack(
        children: [
          Obx(() {
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

          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                tooltip: '返回主页',
                onPressed: Get.back,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ),
          ),
        ],
      ),
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

  VerticalFeedController get controller => widget.controller;

  Future<void> _startFastPlayback() async {
    if (_speedBoostActive || !controller.ready.value) return;
    if (!controller.player.playerStatus.isPlaying) return;

    _previousSpeed = controller.player.playbackSpeed;
    _speedBoostActive = true;

    await controller.player.setPlaybackSpeed(3.0);
  }

  Future<void> _stopFastPlayback() async {
    if (!_speedBoostActive) return;

    final restoreSpeed = _previousSpeed ?? 1.0;

    _speedBoostActive = false;
    _previousSpeed = null;

    await controller.player.setPlaybackSpeed(restoreSpeed);
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds % 60;

    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
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

    final success = await controller.toggleLike();

    if (!mounted) return;

    if (success) {
      _showMessage(
        controller.liked.value ? '点赞成功' : '已取消点赞',
      );
    } else {
      _showMessage('点赞失败，请检查登录状态或网络连接');
    }
  }

  Future<void> _shareVideo() async {
    if (widget.index < 0 ||
        widget.index >= controller.videos.length) {
      _showMessage('无法获取视频信息');
      return;
    }

    final item = controller.videos[widget.index];
    final bvid = item.bvid;

    if (bvid == null || bvid.isEmpty) {
      _showMessage('无法获取视频链接');
      return;
    }

    final title = item.title ?? '哔哩哔哩视频';
    final url = 'https://www.bilibili.com/video/$bvid';

    await ShareUtils.shareText('$title\n$url');
  }

  void _showActionHint(String name) {
    _showMessage('$name功能尚未接入');
  }

  @override
  void dispose() {
    if (_speedBoostActive) {
      _speedBoostActive = false;
      controller.player.setPlaybackSpeed(_previousSpeed ?? 1.0);
      _previousSpeed = null;
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        final isLandscape = width > height;
        final isCompact = height < 680 || isLandscape;

        final actionSpacing = isLandscape ? 5.0 : (isCompact ? 9.0 : 16.0);
        final actionBottom = isLandscape ? 66.0 : (isCompact ? 92.0 : 112.0);
        final titleBottom = isCompact ? 66.0 : 76.0;
        final iconSize = isLandscape ? 22.0 : (isCompact ? 25.0 : 29.0);
        final labelSize = isCompact ? 10.0 : 11.0;

        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final progressBottom = bottomInset > 0
            ? bottomInset + 8
            : 24.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: controller.togglePlayPause,
          onLongPressStart: (_) {
            _startFastPlayback();
          },
          onLongPressEnd: (_) {
            _stopFastPlayback();
          },
          onLongPressCancel: () {
            _stopFastPlayback();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频画面
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
                final videoIsLandscape = videoWidth > videoHeight;

                return IgnorePointer(
                  child: Video(
                    controller: videoController,
                    controls: NoVideoControls,
                    fit: videoIsLandscape ? BoxFit.contain : BoxFit.cover,
                  ),
                );
              }),

              // 渐变遮罩
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

              // 视频标题和UP主
              Positioned(
                left: 16,
                right: 76,
                bottom: titleBottom,
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
                          fontSize: isCompact ? 14 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      maxLines: isCompact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 13 : 15,
                      ),
                    ),
                  ],
                ),
              ),

              // 右侧五个互动按钮
              Positioned(
                right: 8,
                bottom: actionBottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 点赞：连接真实 API
                    Obx(() {
                      final isLiked = controller.liked.value;
                      final isLiking = controller.liking.value;

                      return _FeedActionButton(
                        icon: isLiked
                            ? Icons.thumb_up_alt
                            : Icons.thumb_up_alt_outlined,
                        label: '点赞',
                        iconSize: iconSize,
                        labelSize: labelSize,
                        compact: isCompact,
                        active: isLiked,
                        loading: isLiking,
                        onTap: _toggleLike,
                      );
                    }),

                    SizedBox(height: actionSpacing),

                    // 评论：待接入
                    _FeedActionButton(
                      icon: Icons.mode_comment_outlined,
                      label: '评论',
                      iconSize: iconSize,
                      labelSize: labelSize,
                      compact: isCompact,
                      onTap: () => _showActionHint('评论'),
                    ),

                    SizedBox(height: actionSpacing),

                    // 投币：待接入
                    _FeedActionButton(
                      icon: Icons.monetization_on_outlined,
                      label: '投币',
                      iconSize: iconSize,
                      labelSize: labelSize,
                      compact: isCompact,
                      onTap: () => _showActionHint('投币'),
                    ),

                    SizedBox(height: actionSpacing),

                    // 收藏：待接入
                    _FeedActionButton(
                      icon: Icons.star_border_rounded,
                      label: '收藏',
                      iconSize: iconSize,
                      labelSize: labelSize,
                      compact: isCompact,
                      onTap: () => _showActionHint('收藏'),
                    ),

                    SizedBox(height: actionSpacing),

                    // 分享：调用系统分享面板
                    _FeedActionButton(
                      icon: Icons.share_outlined,
                      label: '分享',
                      iconSize: iconSize,
                      labelSize: labelSize,
                      compact: isCompact,
                      onTap: _shareVideo,
                    ),
                  ],
                ),
              ),

              // 底部常驻播放进度条
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

                  final value = progress.clamp(0, duration).toDouble();

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
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white38,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white24,
                          ),
                          child: Slider(
                            min: 0,
                            max: duration.toDouble(),
                            value: value,
                            onChangeStart: (value) {
                              player.isSeeking.value = true;
                              player.seekPosition.value = value.round();
                            },
                            onChanged: (value) {
                              player.seekPosition.value = value.round();
                            },
                            onChangeEnd: (value) {
                              player.isSeeking.value = false;
                              player.seekTo(
                                Duration(seconds: value.round()),
                              );
                            },
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
        );
      },
    );
  }
}

class _FeedActionButton extends StatelessWidget {
  const _FeedActionButton({
    required this.icon,
    required this.label,
    required this.iconSize,
    required this.labelSize,
    required this.compact,
    required this.onTap,
    this.active = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final double iconSize;
  final double labelSize;
  final bool compact;
  final bool active;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: loading ? null : onTap,
      radius: 28,
      child: SizedBox(
        width: compact ? 44 : 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                icon,
                color: active ? Colors.pinkAccent : Colors.white,
                size: iconSize,
              ),
            SizedBox(height: compact ? 2 : 4),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.pinkAccent : Colors.white,
                fontSize: labelSize,
                shadows: const [
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
    );
  }
}
