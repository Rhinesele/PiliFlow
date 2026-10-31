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
    // 不要在这里 delete controller，因为作为 Tab 需要保持状态
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

class _VideoPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: controller.togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Obx(() {
            if (controller.currentIndex.value != index) {
              return const SizedBox.shrink();
            }
            final videoController = controller.videoController;
            if (!controller.ready.value || videoController == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Video(
              controller: videoController,
              controls: NoVideoControls,
              fit: BoxFit.cover,
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
            right: 72,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (owner.isNotEmpty)
                  Text(
                    '@$owner',
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
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 86,
            child: Obx(
              () => Material(
                color: Colors.black.withValues(alpha: 0.38),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: controller.muted.value ? '取消静音' : '静音',
                  color: Colors.white,
                  onPressed: controller.toggleMute,
                  icon: Icon(
                    controller.muted.value
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
