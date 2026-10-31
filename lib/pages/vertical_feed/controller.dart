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

class VerticalFeedController extends GetxController
    with ScrollOrRefreshMixin {
  final videos = <RcmdVideoItemAppModel>[].obs;
  final currentIndex = 0.obs;
  final ready = false.obs;
  final loading = false.obs;
  final muted = false.obs;
  final error = RxnString();

  @override
  final ScrollController scrollController = ScrollController();

  late final PlPlayerController player = PlPlayerController.getInstance();
  VideoController? get videoController => player.videoController;

  int _freshIdx = 0;
  int _loadToken = 0;
  bool _disposed = false;

  @override
  void onInit() {
    super.onInit();
    player.isVertical = true;
    player.addStatusLister(_onPlayerStatus);
    loadMore();
  }

  void _onPlayerStatus(PlayerStatus status) {
    if (status == PlayerStatus.completed && !_disposed) {
      final next = currentIndex.value + 1;
      if (next < videos.length) {
        onCompleted?.call(next);
      } else {
        loadMore().then((_) {
          if (!_disposed && currentIndex.value + 1 < videos.length) {
            onCompleted?.call(currentIndex.value + 1);
          }
        });
      }
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
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading.value || _disposed) return;
    loading.value = true;
    error.value = null;
    try {
      final res = await VideoHttp.rcmdVideoListApp(freshIdx: _freshIdx);
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
      if (!_disposed) error.value = e.toString();
    } finally {
      if (!_disposed) loading.value = false;
    }
  }

  Future<void> playIndex(int index) async {
    if (_disposed || index < 0 || index >= videos.length) return;
    currentIndex.value = index;
    ready.value = false;
    final token = ++_loadToken;
    final item = videos[index];
    final bvid = item.bvid;
    final cid = item.cid;
    if (bvid == null || cid == null) {
      error.value = '该视频缺少播放信息';
      return;
    }

    try {
      await player.pause(notify: false, isInterrupt: true);
      final res = await VideoHttp.videoUrl(
        avid: item.aid,
        bvid: bvid,
        cid: cid,
        qn: Pref.defaultVideoQa,
        tryLook: !Accounts.get(AccountType.video).isLogin && Pref.p1080,
        videoType: VideoType.ugc,
      );
      if (_disposed || token != _loadToken) return;

      if (res case Success(:final response)) {
        final dash = response.dash;
        final video = dash?.video?.isNotEmpty == true ? dash!.video!.first : null;
        final audio = dash?.audio?.isNotEmpty == true ? dash!.audio!.first : null;
        if (video == null) {
          error.value = '该视频没有可用的视频流';
          return;
        }
        final videoUrl = VideoUtils.getCdnUrl(video.playUrls);
        final audioUrl = audio == null
            ? null
            : VideoUtils.getCdnUrl(audio.playUrls, isAudio: true);
        if (videoUrl == null || videoUrl.isEmpty) {
          error.value = '视频地址获取失败';
          return;
        }

        await player.setDataSource(
          NetworkSource(videoSource: videoUrl, audioSource: audioUrl),
          duration: response.timeLength == null
              ? null
              : Duration(milliseconds: response.timeLength!),
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
          await player.setVolume(0, showIndicator: false);
        }
        await player.play();
      } else if (res case Error(:final errMsg)) {
        error.value = errMsg;
      }
    } catch (e) {
      if (!_disposed && token == _loadToken) error.value = e.toString();
    }
  }

  Future<void> toggleMute() async {
    muted.toggle();
    await player.setVolume(muted.value ? 0 : 1, showIndicator: false);
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
