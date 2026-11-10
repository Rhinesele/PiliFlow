import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/member.dart';
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
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum VerticalFeedPlayMode {
  autoNext,
  loopCurrent,
  stop,
}

class VerticalFeedController extends GetxController with ScrollOrRefreshMixin {
  final videos = <RcmdVideoItemAppModel>[].obs;
  final currentIndex = 0.obs;
  final ready = false.obs;
  final loading = false.obs;
  final muted = false.obs;
  final error = RxnString();

  final liked = false.obs;
  final liking = false.obs;
  final coined = false.obs;
  final coining = false.obs;

  final ownerFace = ''.obs;
  final ownerFans = 0.obs;
  final ownerName = ''.obs;
  final ownerMid = 0.obs;

  final playMode = VerticalFeedPlayMode.autoNext.obs;

  final Map<String, bool> _likeCache = {};
  final Map<String, bool> _coinCache = {};
  final Map<int, ({String face, int fans, String name})> _ownerCache = {};

  @override
  final ScrollController scrollController = ScrollController();

  late final PlPlayerController player = PlPlayerController.getInstance();

  VideoController? get videoController => player.videoController;

  int _freshIdx = 0;
  int _loadToken = 0;
  bool _disposed = false;
  bool _handlingCompletion = false;

  bool get isLogin => Accounts.main.isLogin;

  RcmdVideoItemAppModel? get currentItem {
    if (currentIndex.value < 0 || currentIndex.value >= videos.length) {
      return null;
    }
    return videos[currentIndex.value];
  }

  @override
  void onInit() {
    super.onInit();
    player.isVertical = true;
    player.addStatusLister(_onPlayerStatus);
    loadMore();
  }

  void setPlayMode(VerticalFeedPlayMode mode) {
    playMode.value = mode;
  }

  void _onPlayerStatus(PlayerStatus status) {
    if (status != PlayerStatus.completed || _disposed || _handlingCompletion) {
      return;
    }
    unawaited(_handleCompleted());
  }

  Future<void> _handleCompleted() async {
    if (_disposed || _handlingCompletion) return;
    _handlingCompletion = true;
    try {
      switch (playMode.value) {
        case VerticalFeedPlayMode.autoNext:
          await _playNextVideo();
        case VerticalFeedPlayMode.loopCurrent:
          await player.seekTo(Duration.zero);
          if (!_disposed) await player.play();
        case VerticalFeedPlayMode.stop:
          await player.pause();
      }
    } catch (_) {
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
    _coinCache.clear();
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
    liking.value = false;
    coining.value = false;

    final token = ++_loadToken;
    final item = videos[index];
    final bvid = item.bvid;
    final cid = item.cid;

    ownerName.value = item.owner?.name ?? '';
    ownerMid.value = item.owner?.mid ?? 0;
    ownerFace.value = '';
    ownerFans.value = 0;

    if (bvid == null || cid == null) {
      error.value = '该视频缺少播放信息';
      return;
    }

    liked.value = _likeCache[bvid] ?? false;
    coined.value = _coinCache[bvid] ?? false;

    unawaited(_loadRelation(bvid, token));
    unawaited(_loadOwnerInfo(item.owner?.mid, token));

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
        final video =
            dash?.video?.isNotEmpty == true ? dash!.video!.first : null;
        final audio =
            dash?.audio?.isNotEmpty == true ? dash!.audio!.first : null;

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
      if (!_disposed && token == _loadToken) {
        error.value = e.toString();
      }
    }
  }

  Future<void> _loadRelation(String bvid, int token) async {
    try {
      final res = await VideoHttp.videoRelation(bvid: bvid);
      if (_disposed || token != _loadToken) return;
      if (res case Success(:final response)) {
        final like = response.like ?? false;
        final coin = (response.coin ?? 0) > 0;
        _likeCache[bvid] = like;
        _coinCache[bvid] = coin;
        liked.value = like;
        coined.value = coin;
      }
    } catch (_) {}
  }

  Future<void> _loadOwnerInfo(int? mid, int token) async {
    if (mid == null || mid <= 0) return;

    final cached = _ownerCache[mid];
    if (cached != null) {
      if (!_disposed && token == _loadToken) {
        ownerFace.value = cached.face;
        ownerFans.value = cached.fans;
        if (cached.name.isNotEmpty) ownerName.value = cached.name;
      }
      return;
    }

    try {
      final res = await MemberHttp.memberCardInfo(mid: mid);
      if (_disposed || token != _loadToken) return;
      if (res case Success(:final response)) {
        final face = response.card?.face ?? '';
        final fans = response.follower ?? 0;
        final name = response.card?.name ?? ownerName.value;
        _ownerCache[mid] = (face: face, fans: fans, name: name);
        ownerFace.value = face;
        ownerFans.value = fans;
        if (name.isNotEmpty) ownerName.value = name;
      }
    } catch (_) {}
  }

  Future<void> toggleLike() async {
    if (liking.value) return;
    if (!isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }
    final item = currentItem;
    final bvid = item?.bvid;
    if (bvid == null || bvid.isEmpty) {
      SmartDialog.showToast('无法获取视频信息');
      return;
    }

    liking.value = true;
    try {
      final newVal = !liked.value;
      final res = await VideoHttp.likeVideo(bvid: bvid, type: newVal);
      if (_disposed) return;
      if (res case Success(:final response)) {
        liked.value = newVal;
        _likeCache[bvid] = newVal;
        SmartDialog.showToast(
          newVal ? (response.isNotEmpty ? response : '点赞成功') : '取消赞',
        );
      } else if (res case Error(:final errMsg)) {
        SmartDialog.showToast(errMsg ?? '操作失败');
      }
    } catch (e) {
      SmartDialog.showToast(e.toString());
    } finally {
      if (!_disposed) liking.value = false;
    }
  }

  Future<void> coin(int multiply, {bool alsoLike = false}) async {
    if (coining.value) return;
    if (!isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }
    if (coined.value) {
      SmartDialog.showToast('已经投过币了');
      return;
    }
    final item = currentItem;
    final bvid = item?.bvid;
    if (bvid == null || bvid.isEmpty) {
      SmartDialog.showToast('无法获取视频信息');
      return;
    }

    coining.value = true;
    try {
      final res = await VideoHttp.coinVideo(
        bvid: bvid,
        multiply: multiply,
        selectLike: alsoLike ? 1 : 0,
      );
      if (_disposed) return;
      if (res case Success()) {
        coined.value = true;
        _coinCache[bvid] = true;
        if (alsoLike && !liked.value) {
          liked.value = true;
          _likeCache[bvid] = true;
        }
        SmartDialog.showToast('投币成功');
      } else if (res case Error(:final errMsg)) {
        SmartDialog.showToast(errMsg ?? '投币失败');
      }
    } catch (e) {
      SmartDialog.showToast(e.toString());
    } finally {
      if (!_disposed) coining.value = false;
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
