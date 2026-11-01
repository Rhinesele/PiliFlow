import 'dart:async';

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
late final VerticalFeedController controller =
Get.put(VerticalFeedController());

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

bool _immersive = false;
bool _showPaused = false;
bool _showBuffering = false;

Timer? _singleTapTimer;
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

final restoreSpeed = _previousSpeed ?? 1.0;
_speedBoostActive = false;
_previousSpeed = null;

if (mounted) setState(() {});
await controller.player.setPlaybackSpeed(restoreSpeed);

}

void _handleTap() {
if (_singleTapTimer?.isActive == true) {
_singleTapTimer!.cancel();
return;
}

_singleTapTimer = Timer(
  const Duration(milliseconds: 260),
  () {
    if (!mounted) return;
    setState(() {
      _immersive = !_immersive;
    });
  },
);

}

void _handleDoubleTap() {
_singleTapTimer?.cancel();

controller.togglePlayPause();

if (!mounted) return;
setState(() {
  _showPaused = controller.player.playerStatus.isPlaying;
});

Future.delayed(const Duration(milliseconds: 900), () {
  if (mounted) {
    setState(() {
      _showPaused = false;
    });
  }
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

final success = await controller.toggleLike();
if (!mounted) return;

if (success) {
  _showMessage(controller.liked.value ? '点赞成功' : '已取消点赞');
} else {
  _showMessage('点赞失败，请检查登录状态或网络连接');
}

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
  '${item.title ?? '哔哩哔哩视频'}\nhttps://www.bilibili.com/video/$bvid',
);

}

void _showActionHint(String name) {
_showMessage('$name功能尚未接入');
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
_singleTapTimer?.cancel();
_bufferTimer?.cancel();

if (_speedBoostActive) {
  controller.player.setPlaybackSpeed(_previousSpeed ?? 1.0);
  _speedBoostActive = false;
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

    final screenIsLandscape = width > height;
    final isCompact = height < 680 || screenIsLandscape;

    final actionSpacing =
        screenIsLandscape ? 5.0 : (isCompact ? 9.0 : 16.0);
    final actionBottom =
        screenIsLandscape ? 66.0 : (isCompact ? 92.0 : 112.0);
    final titleBottom = isCompact ? 66.0 : 76.0;
    final iconSize =
        screenIsLandscape ? 22.0 : (isCompact ? 25.0 : 29.0);
    final labelSize = isCompact ? 10.0 : 11.0;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final progressBottom = bottomInset > 0 ? bottomInset + 8 : 24.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onDoubleTap: _handleDoubleTap,
      onLongPressStart: (_) => _startFastPlayback(),
      onLongPressEnd: (_) => _stopFastPlayback(),
      onLongPressCancel: _stopFastPlayback,
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
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                padding: videoIsLandscape
                    ? EdgeInsets.only(
                        bottom: height * 0.16,
                        right: 64,
                      )
                    : EdgeInsets.zero,
                child: Video(
                  controller: videoController,
                  controls: NoVideoControls,
                  fit: videoIsLandscape ? BoxFit.contain : BoxFit.cover,
                ),
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

          // 正常模式下显示的界面
          if (!_immersive) ...[
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
                    size: 25,
                  ),
                ),
              ),
            ),

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

            Positioned(
              right: 8,
              bottom: actionBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  _FeedActionButton(
                    icon: Icons.mode_comment_outlined,
                    label: '评论',
                    iconSize: iconSize,
                    labelSize: labelSize,
                    compact: isCompact,
                    onTap: () => _showActionHint('评论'),
                  ),
                  SizedBox(height: actionSpacing),
                  _FeedActionButton(
                    icon: Icons.monetization_on_outlined,
                    label: '投币',
                    iconSize: iconSize,
                    labelSize: labelSize,
                    compact: isCompact,
                    onTap: () => _showActionHint('投币'),
                  ),
                  SizedBox(height: actionSpacing),
                  _FeedActionButton(
                    icon: Icons.star_border_rounded,
                    label: '收藏',
                    iconSize: iconSize,
                    labelSize: labelSize,
                    compact: isCompact,
                    onTap: () => _showActionHint('收藏'),
                  ),
                  SizedBox(height: actionSpacing),
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
          ],

          // 暂停提示
          if (_showPaused)
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pause_rounded,
                  color: Colors.white,
                  size: 54,
                ),
              ),
            ),

          // 3 倍速提示
          if (_speedBoostActive)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Text(
                  '3.0倍速中',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // 缓冲提示
          Obx(() {
            final buffering = controller.player.isBuffering.value;
            if (buffering && controller.ready.value) {
              if (!_showBuffering) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _showBuffering = true;
                    });
                  }
                });
              }
            } else if (_showBuffering && !buffering) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _showBuffering = false;
                  });
                }
              });
            }

            if (!_showBuffering) return const SizedBox.shrink();

            return const Center(
              child: Text(
                '加载中...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            );
          }),

          // 底部进度条：沉浸模式下仍然保留
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
