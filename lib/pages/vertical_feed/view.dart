import 'package:PiliPlus/pages/vertical_feed/controller.dart';
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

  void _showActionHint(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name功能正在接入'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            final isLandscape = videoWidth > videoHeight;

            return IgnorePointer(
              child: Video(
                controller: videoController,
                controls: NoVideoControls,
                fit: isLandscape ? BoxFit.contain : BoxFit.cover,
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
            bottom: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.owner.isNotEmpty)
                  Text(
                    '@${widget.owner}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                const SizedBox(height: 8),

                Text(
                  widget.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          // 右侧五个互动按钮
          Positioned(
            right: 10,
            bottom: 112,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FeedActionButton(
                  icon: Icons.thumb_up_alt_outlined,
                  label: '点赞',
                  onTap: () => _showActionHint('点赞'),
                ),

                const SizedBox(height: 18),

                _FeedActionButton(
                  icon: Icons.mode_comment_outlined,
                  label: '评论',
                  onTap: () => _showActionHint('评论'),
                ),

                const SizedBox(height: 18),

                _FeedActionButton(
                  icon: Icons.monetization_on_outlined,
                  label: '投币',
                  onTap: () => _showActionHint('投币'),
                ),

                const SizedBox(height: 18),

                _FeedActionButton(
                  icon: Icons.star_border_rounded,
                  label: '收藏',
                  onTap: () => _showActionHint('收藏'),
                ),

                const SizedBox(height: 18),

                _FeedActionButton(
                  icon: Icons.share_outlined,
                  label: '分享',
                  onTap: () => _showActionHint('分享'),
                ),
              ],
            ),
          ),

          // 底部常驻播放进度条
          Positioned(
            left: 12,
            right: 12,
            bottom: 32,
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
  }
}

// 竖屏视频流互动按钮
class _FeedActionButton extends StatelessWidget {
  const _FeedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 30,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 29,
            ),

            const SizedBox(height: 4),

            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
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
    );
  }
}
