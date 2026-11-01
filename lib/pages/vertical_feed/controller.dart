import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum VerticalFeedPlayMode {
  autoNext,
  loopCurrent,
  stop,
}

class VerticalFeedController extends GetxController
    with ScrollOrRefreshMixin {
  final videos = <RcmdVideoItemAppModel>[].obs;
  final currentIndex = 0.obs;
  final ready = false.obs;
  final loading = false.obs;
  final muted = false.obs;
  final error = RxnString();

  final liked = false.obs;
  final liking = false.obs;
  final playMode = VerticalFeedPlayMode.autoNext.obs;

  final Map<String, bool> _likeCache = {};

  @override
  final ScrollController scrollController = ScrollController();

  late final PlPlayerController player =
      PlPlayerController.getInstance();

  VideoController? get videoController => player.videoController;

  int _freshIdx = 0;
  int _loadToken = 0;
  bool _disposed = false;
  bool _handlingCompletion = false;

  @override
  void onInit() {
    super.onInit();
    player.isVertical = true;
    player.addStatusLister(_onPlayerStatus);
    loadMore();
  }

  String get playModeName {
    switch (playMode.value) {
      case VerticalFeedPlayMode.autoNext:
        return '自动连播';
      case VerticalFeedPlayMode.loopCurrent:
        return '循环当前';
      case VerticalFeedPlayMode.stop:
        return '播完停止';
    }
  }

  void setPlayMode(VerticalFeedPlayMode mode) {
    playMode.value = mode;
  }

  // 这里必须是同步回调，不能写成 Future<void>。
  void _onPlayerStatus(PlayerStatus status) {
    if (status != PlayerStatus.completed ||
        _disposed ||
        _handlingCompletion) {
      return;
    }

    unawaited(_handleCompleted());
  }

  // 真正的异步播放结束处理放在这里。
  Future<void> _handleCompleted() async {
    if (_disposed || _handlingCompletion) return;

    _handlingCompletion = true;

    try {
      switch (playMode.value) {
        case VerticalFeedPlayMode.autoNext:
          await _playNextVideo();
          break;

        case VerticalFeedPlayMode.loopCurrent:
          await player.seekTo(Duration.zero);
          if (!_disposed) {
            await player.play();
          }
          break;

        case VerticalFeedPlayMode.stop:
          await player.pause();
          break;
      }
    } catch (_) {
      // 播放结束后的操作失败时，不让监听器崩溃。
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> _playNextVideo() async {
    if (_disposed) return;

    final next = currentIndex.value + 1;

    if (next < videos.length) {
      onCompleted?.call(next);
      return;
    }

    await loadMore();

    if (_disposed) return;

    if (currentIndex.value + 1 < videos.length) {
      onCompleted?.call(currentIndex.value + 1);
    }
  }

  void Function(int)? onCompleted;

  @override
  Future<void> onRefresh() async {
    videos.clear();
    currentIndex.value = 0;
    _freshIdx = 0;
    ready.value = false;
    error.value = null;
    _likeCache.clear();

    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading.value || _disposed) return;

    loading.value = true;
    error.value = null;

    try {
      final res = await VideoHttp.rcmdVideoListApp(
        freshIdx: _freshIdx,
      );

      if (_disposed) return;

      if (res case Success(:final response)) {
        if (response.isNotEmpty) {
          final wasEmpty = videos.isEmpty;

          videos.addAll(response);
          _freshIdx += response.length;

          if (wasEmpty) {
            unawaited(playIndex(0));
          }
        }
      } else if (res case Error(:final errMsg)) {
        error.value = errMsg;
      }
    } catch (e) {
      if (!_disposed) {
        error.value = e.toString();
      }
    } finally {
      if (!_disposed) {
        loading.value = false;
      }
    }
  }

  Future<void> playIndex(int index) async {
    if (_disposed || index < 0 || index >= videos.length) {
      return;
    }

    currentIndex.value = index;
    ready.value = false;
    liking.value = false;

    final token = ++_loadToken;
    final item = videos[index];
    final bvid = item.bvid;
    final cid = item.cid;

    if (bvid == null || cid == null) {
      error.value = '该视频缺少播放信息';
      return;
    }

    liked.value = _likeCache[bvid] ?? false;
    unawaited(_loadLikeStatus(bvid, token));

    try {
      await player.pause(
        notify: false,
        isInterrupt: true,
      );

      final res = await VideoHttp.videoUrl(
        avid: item.aid,
        bvid: bvid,
        cid: cid,
        qn: Pref.defaultVideoQa,
        tryLook: !Accounts.get(AccountType.video).isLogin &&
            Pref.p1080,
        videoType: VideoType.ugc,
      );

      if (_disposed || token != _loadToken) return;

      if (res case Success(:final response)) {
        final dash = response.dash;

        final video = dash?.video?.isNotEmpty == true
            ? dash!.video!.first
            : null;

        final audio = dash?.audio?.isNotEmpty == true
            ? dash!.audio!.first
            : null;

        if (video == null) {
          error.value = '该视频没有可用的视频流';
          return;
        }

        final videoUrl = VideoUtils.getCdnUrl(
          video.playUrls,
        );

        final audioUrl = audio == null
            ? null
            : VideoUtils.getCdnUrl(
                audio.playUrls,
                isAudio: true,
              );

        if (videoUrl == null || videoUrl.isEmpty) {
          error.value = '视频地址获取失败';
          return;
        }

        await player.setDataSource(
          NetworkSource(
            videoSource: videoUrl,
            audioSource: audioUrl,
          ),
          duration: response.timeLength == null
              ? null
              : Duration(
                  milliseconds: response.timeLength!,
                ),
          isVertical: true,
          aid: item.aid,
          bvid: bvid,
          cid: cid,
          autoplay: true,
          videoType: VideoType.ugc,
          width: video.width,
          height: video.height,
        );

        if (_disposed || token != _loadToken) return;

        ready.value = true;

        if (muted.value) {
          await player.setVolume(
            0,
            showIndicator: false,
          );
        }

        await player.play();
      } else if (res case Error(:final errMsg)) {
        error.value = errMsg;
      }
    } catch (e) {
      if (!_disposed && token == _loadToken) {
        error.value = e.toString();
      }
    }
  }

  Future<void> _loadLikeStatus(
    String bvid,
    int token,
  ) async {
    try {
      final res = await VideoHttp.videoRelation(
        bvid: bvid,
      );

      if (_disposed ||
          token != _loadToken ||
          currentIndex.value < 0 ||
          currentIndex.value >= videos.length) {
        return;
      }

      if (res case Success(:final response)) {
        final value = response.like ?? false;
        _likeCache[bvid] = value;
        liked.value = value;
      }
    } catch (_) {
      // 网络读取失败时保留原状态。
    }
  }

  Future<bool> toggleLike() async {
    if (liking.value) return false;

    if (!Accounts.get(AccountType.video).isLogin) {
      return false;
    }

    if (currentIndex.value < 0 ||
        currentIndex.value >= videos.length) {
      return false;
    }

    final bvid = videos[currentIndex.value].bvid;

    if (bvid == null || bvid.isEmpty) {
      return false;
    }

    liking.value = true;

    try {
      final oldValue = liked.value;

      final res = await VideoHttp.likeVideo(
        bvid: bvid,
        type: oldValue,
      );

      if (_disposed) return false;

      if (res case Success()) {
        final newValue = !oldValue;
        liked.value = newValue;
        _likeCache[bvid] = newValue;
        return true;
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) {
        liking.value = false;
      }
    }
  }

  Future<void> toggleMute() async {
    muted.toggle();

    await player.setVolume(
      muted.value ? 0 : 1,
      showIndicator: false,
    );
  }

  Future<void> togglePlayPause() async {
    if (player.videoPlayerController == null) return;

    if (player.playerStatus.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void disposePlayer() {
    if (_disposed) return;

    _disposed = true;

    player.removeStatusLister(_onPlayerStatus);
    player.dispose();
  }

  @override
  void onClose() {
    disposePlayer();
    scrollController.dispose();
    super.onClose();
  }
}
