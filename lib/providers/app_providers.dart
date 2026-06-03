import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/spectrum.dart';
import 'package:jmusic/src/rust/api/player.dart' as rust_player;
import 'package:jmusic/src/rust/api/scanner.dart' as rust_scanner;
import 'package:jmusic/src/rust/api/metadata.dart' as rust_metadata;
import 'package:jmusic/src/rust/api/play_stats.dart' as rust_play_stats;
import 'package:jmusic/src/rust/api/media_session.dart' as rust_media_session;
import 'package:jmusic/src/rust/models/song.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';
import 'package:jmusic/providers/webdav_provider.dart';
import 'package:jmusic/services/listening_calendar_service.dart';
import 'package:jmusic/services/play_history_service.dart';
import 'package:jmusic/services/achievement_service.dart';
import 'package:jmusic/providers/playback_speed.dart';

/// 播放模式枚举
enum PlayMode {
  /// 顺序播放
  sequential,

  /// 单曲循环
  singleLoop,

  /// 随机播放
  shuffle,
}

/// A-B 复读循环状态
enum ABLoopState {
  /// 未激活
  off,

  /// 已设置 A 点，等待设置 B 点
  setA,

  /// A-B 循环激活中
  active,
}

/// 播放器完整状态
class PlayerState {
  final Song? currentSong;
  final int currentIndex;
  final List<Song> playlist;
  final bool isPlaying;
  final double volume;
  final PlayMode playMode;
  final Duration position;
  final Duration duration;
  final Lyrics? lyrics;
  final String? lrcText; // 原始 LRC 文本（用于保存到文件）
  final List<int>? coverData;
  final bool isLoading;
  final String? error; // 播放错误信息
  final List<double> spectrum; // 64-bin 频谱数据 (0.0~1.0)
  final ABLoopState abLoopState; // A-B 复读状态
  final Duration? loopStart; // A 点
  final Duration? loopEnd; // B 点
  final List<Song> queue; // 播放队列（优先于 playlist 的临时队列）

  const PlayerState({
    this.currentSong,
    this.currentIndex = -1,
    this.playlist = const [],
    this.isPlaying = false,
    this.volume = 0.8,
    this.playMode = PlayMode.sequential,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.lyrics,
    this.lrcText,
    this.coverData,
    this.isLoading = false,
    this.error,
    this.spectrum = const [],
    this.abLoopState = ABLoopState.off,
    this.loopStart,
    this.loopEnd,
    this.queue = const [],
  });

  PlayerState copyWith({
    Song? currentSong,
    int? currentIndex,
    List<Song>? playlist,
    bool? isPlaying,
    double? volume,
    PlayMode? playMode,
    Duration? position,
    Duration? duration,
    Lyrics? lyrics,
    String? lrcText,
    List<int>? coverData,
    bool? isLoading,
    String? error,
    List<double>? spectrum,
    ABLoopState? abLoopState,
    Duration? loopStart,
    Duration? loopEnd,
    List<Song>? queue,
    bool clearLyrics = false,
    bool clearCover = false,
    bool clearSong = false,
    bool clearError = false,
    bool clearLoop = false,
  }) {
    return PlayerState(
      currentSong: clearSong ? null : (currentSong ?? this.currentSong),
      currentIndex: currentIndex ?? this.currentIndex,
      playlist: playlist ?? this.playlist,
      isPlaying: isPlaying ?? this.isPlaying,
      volume: volume ?? this.volume,
      playMode: playMode ?? this.playMode,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      lyrics: clearLyrics ? null : (lyrics ?? this.lyrics),
      lrcText: clearLyrics ? null : (lrcText ?? this.lrcText),
      coverData: clearCover ? null : (coverData ?? this.coverData),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      spectrum: spectrum ?? this.spectrum,
      abLoopState: clearLoop ? ABLoopState.off : (abLoopState ?? this.abLoopState),
      loopStart: clearLoop ? null : (loopStart ?? this.loopStart),
      loopEnd: clearLoop ? null : (loopEnd ?? this.loopEnd),
      queue: queue ?? this.queue,
    );
  }
}

/// 播放器状态管理（Riverpod 3.x Notifier）
class PlayerNotifier extends Notifier<PlayerState> {
  Timer? _positionTimer;
  Timer? _spectrumTimer;
  Timer? _mediaEventTimer;
  bool _isSeeking = false;

  @override
  PlayerState build() {
    // 初始化时启动音频引擎
    _initEngine();
    // 初始化系统媒体会话
    _initMediaSession();
    // 初始化时设置默认的原生窗口和托盘提示
    NativeUtils.updateTitle('JMusic');
    // 注册托盘播放控制回调
    _registerTrayHandler();
    // 加载听歌日历数据
    ListeningCalendarService.instance.load();
    // 加载播放历史数据
    PlayHistoryService.instance.load();
    // 加载成就数据
    AchievementService.instance.load();
    // 清理定时器
    ref.onDispose(() {
      _positionTimer?.cancel();
      _spectrumTimer?.cancel();
      _mediaEventTimer?.cancel();
      // 退出时保存听歌日历
      ListeningCalendarService.instance.save();
      try {
        if (!Platform.isAndroid) {
          rust_player.playerStop();
        }
      } catch (_) {}
    });
    return const PlayerState();
  }

  /// 启动频谱轮询定时器
  void _startSpectrumTimer() {
    _spectrumTimer?.cancel();
    _spectrumTimer = Timer.periodic(kSpectrumPollInterval, (_) async {
      if (!state.isPlaying) return;
      try {
        if (Platform.isAndroid) {
          // Android: 从原生 Visualizer 获取频谱数据
          final result = await _playerChannel.invokeMethod('getSpectrum');
          if (result == null) return;
          final List<dynamic> raw = result;
          final List<double> safe = List<double>.generate(
            kSpectrumBins,
            (i) => i < raw.length ? (raw[i] as num).toDouble().clamp(0.0, 1.0) : 0.0,
          );
          state = state.copyWith(spectrum: safe);
        } else {
          // 桌面端：从 Rust 引擎获取频谱数据
          final frame = rust_player.playerGetSpectrum();
          if (frame == null) return;
          final List<double> safe;
          if (frame.length == kSpectrumBins) {
            safe = List<double>.generate(
                kSpectrumBins, (i) => frame[i].clamp(0.0, 1.0));
          } else {
            safe = List<double>.generate(kSpectrumBins,
                (i) => i < frame.length ? frame[i].toDouble().clamp(0.0, 1.0) : 0.0);
          }
          state = state.copyWith(spectrum: safe);
        }
      } catch (_) {}
    });
  }

  /// 停止频谱轮询定时器
  void _stopSpectrumTimer() {
    _spectrumTimer?.cancel();
    _spectrumTimer = null;
    state = state.copyWith(spectrum: emptySpectrum());
  }

  /// 注册原生托盘菜单的播放控制回调
  void _registerTrayHandler() {
    if (!Platform.isWindows) return;
    const channel = MethodChannel('com.jmusic.app/tray');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onTrayAction') {
        final action = call.arguments as String?;
        switch (action) {
          case 'togglePlayPause':
            togglePlayPause();
            break;
          case 'previous':
            previous();
            break;
          case 'next':
            next();
            break;
          case 'togglePlayMode':
            togglePlayMode();
            break;
        }
      }
    });
  }

  /// 初始化系统媒体会话（Windows SMTC / macOS Now Playing / Android MediaSession）
  void _initMediaSession() {
    if (Platform.isAndroid) {
      // Android: 注册来自 MusicService 的媒体控制事件回调
      _registerAndroidMediaHandler();
      return;
    }

    // 桌面端：异步获取 HWND（Windows）或直接初始化（macOS）
    Future(() async {
      int hwnd = 0;
      if (Platform.isWindows) {
        try {
          const channel = MethodChannel('com.jmusic.app/tray');
          hwnd = await channel.invokeMethod<int>('getHwnd') ?? 0;
        } catch (e) {
          print('获取窗口句柄失败: $e');
          return;
        }
      }

      try {
        rust_media_session.mediaSessionInit(hwnd: hwnd);
        print('系统媒体会话初始化成功');
        // 启动媒体事件轮询
        _startMediaEventPolling();
      } catch (e) {
        print('系统媒体会话初始化失败: $e');
      }
    });
  }

  /// 注册 Android 端 MusicService 的媒体控制事件回调
  void _registerAndroidMediaHandler() {
    const channel = MethodChannel('com.jmusic.app/player');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onMediaAction') {
        final action = call.arguments as String?;
        if (action == null) return;

        if (action.startsWith('seek:')) {
          final posMs = int.tryParse(action.substring(5)) ?? 0;
          seekTo(Duration(milliseconds: posMs));
        } else {
          switch (action) {
            case 'play':
              if (!state.isPlaying) togglePlayPause();
              break;
            case 'pause':
              if (state.isPlaying) togglePlayPause();
              break;
            case 'next':
              next();
              break;
            case 'previous':
              previous();
              break;
            case 'stop':
              _stopPlayback();
              break;
          }
        }
      }
    });
  }

  /// 启动系统媒体控制事件轮询
  void _startMediaEventPolling() {
    _mediaEventTimer?.cancel();
    _mediaEventTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _pollMediaEvents();
    });
  }

  /// 轮询并处理系统媒体控制事件
  void _pollMediaEvents() {
    if (Platform.isAndroid) return;
    try {
      final event = rust_media_session.mediaSessionPollEvent();
      if (event == null) return;

      switch (event.action) {
        case 'play':
        case 'toggle':
          togglePlayPause();
          break;
        case 'pause':
          if (state.isPlaying) togglePlayPause();
          break;
        case 'next':
          next();
          break;
        case 'previous':
          previous();
          break;
        case 'stop':
          _stopPlayback();
          break;
        case 'seek':
          seekTo(Duration(
            milliseconds: (event.positionSecs * 1000).toInt(),
          ));
          break;
      }
    } catch (_) {}
  }

  /// 停止播放
  void _stopPlayback() {
    if (Platform.isAndroid) {
      _androidPlayer('stop', '');
    } else {
      rust_player.playerStop();
    }
    _positionTimer?.cancel();
    _stopSpectrumTimer();
    state = state.copyWith(isPlaying: false, position: Duration.zero);
    _updateMediaSessionStopped();
  }

  /// 同步更新系统媒体会话的元数据
  void _updateMediaSessionMetadata(Song song) {
    if (Platform.isAndroid) {
      // Android: 通过 MethodChannel 发送元数据给 MusicService
      try {
        const channel = MethodChannel('com.jmusic.app/player');
        final metadata = '${song.title}\n${song.artist}\n${song.album}\n${song.duration}';
        channel.invokeMethod('updateMetadata', metadata);
      } catch (_) {}
      return;
    }
    try {
      rust_media_session.mediaSessionUpdateMetadata(
        title: song.title,
        artist: song.artist,
        album: song.album,
        durationSecs: song.duration,
      );
    } catch (_) {}
  }

  /// 同步更新系统媒体会话的播放状态
  void _updateMediaSessionPlayback(bool isPlaying, Duration position) {
    if (Platform.isAndroid) return;
    try {
      rust_media_session.mediaSessionUpdatePlayback(
        isPlaying: isPlaying,
        positionSecs: position.inMilliseconds / 1000.0,
      );
    } catch (_) {}
  }

  /// 同步更新系统媒体会话为停止状态
  void _updateMediaSessionStopped() {
    if (Platform.isAndroid) return;
    try {
      rust_media_session.mediaSessionUpdateStopped();
    } catch (_) {}
  }

  /// 初始化音频引擎
  void _initEngine() {
    if (Platform.isAndroid) {
      // Android 上使用原生 MediaPlayer，不需要初始化 Rust 音频引擎
      print('Android: 使用原生 MediaPlayer');
      return;
    }
    try {
      rust_player.playerInit();
      print('音频引擎初始化成功');
    } catch (e) {
      print('音频引擎初始化失败: $e');
    }
  }

  /// 开始定时更新播放进度
  void _startPositionTimer() {
    _positionTimer?.cancel();
    int tickCount = 0;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // seek 期间跳过更新，防止覆盖用户设置的新位置
      if (_isSeeking) return;
      if (state.isPlaying && state.currentSong != null) {
        final newPos = state.position + const Duration(milliseconds: 500);

        // A-B 复读循环：到达 B 点时自动跳回 A 点
        if (state.abLoopState == ABLoopState.active &&
            state.loopStart != null &&
            state.loopEnd != null &&
            newPos >= state.loopEnd!) {
          seekTo(state.loopStart!);
          return;
        }

        if (newPos >= state.duration) {
          _onPlaybackFinished();
        } else {
          state = state.copyWith(position: newPos);
          // 同步更新桌面悬浮歌词
          _updateOverlayLyrics(newPos.inMilliseconds);
          // 每 5 秒同步一次系统媒体会话的播放进度
          tickCount++;
          if (tickCount % 10 == 0) {
            _updateMediaSessionPlayback(true, newPos);
          }
          // 每 30 秒累加听歌日历时长（60 ticks × 500ms = 30s）
          if (tickCount % 60 == 0) {
            ListeningCalendarService.instance.addListeningDuration(30);
          }
          // 每 5 分钟持久化一次日历数据（600 ticks × 500ms = 5min）
          if (tickCount % 600 == 0) {
            ListeningCalendarService.instance.save();
          }
        }
      }
    });
  }

  /// 构造无歌词时的默认显示文本：歌曲名 - 歌手
  String _defaultOverlayText([Song? song]) {
    final s = song ?? state.currentSong;
    if (s == null) return 'JMusic - 本地音乐播放器';
    final title = s.title.trim();
    final artist = s.artist.trim();
    if (title.isEmpty && artist.isEmpty) return 'JMusic - 本地音乐播放器';
    if (artist.isEmpty) return title;
    if (title.isEmpty) return artist;
    return '$title - $artist';
  }

  /// 更新桌面悬浮歌词显示内容
  void _updateOverlayLyrics(int currentMs) {
    final lyrics = state.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      NativeUtils.updateLyricsOverlay(_defaultOverlayText(), '');
      return;
    }

    // 找到当前歌词行索引
    int currentLineIndex = -1;
    for (int i = lyrics.lines.length - 1; i >= 0; i--) {
      if (lyrics.lines[i].timeMs.toInt() <= currentMs) {
        currentLineIndex = i;
        break;
      }
    }

    String currentLine = '';
    String nextLine = '';

    if (currentLineIndex >= 0) {
      currentLine = lyrics.lines[currentLineIndex].text;
    }
    if (currentLineIndex + 1 < lyrics.lines.length) {
      nextLine = lyrics.lines[currentLineIndex + 1].text;
    }

    // 如果当前行和下一行都为空（可能歌词还没开始），显示默认文本
    if (currentLine.isEmpty && nextLine.isEmpty) {
      NativeUtils.updateLyricsOverlay(_defaultOverlayText(), '');
      return;
    }

    NativeUtils.updateLyricsOverlay(currentLine, nextLine);
  }

  /// 播放结束处理
  void _onPlaybackFinished() {
    switch (state.playMode) {
      case PlayMode.singleLoop:
        if (state.currentSong != null) {
          _playFile(state.currentSong!);
        }
      case PlayMode.sequential:
      case PlayMode.shuffle:
        next();
    }
  }

  /// 设置播放列表
  ///
  /// 同步更新当前歌曲在新列表中的索引：
  /// - 当前歌曲仍在新列表中，更新 currentIndex 指向新位置；
  /// - 当前歌曲不在新列表中，currentIndex 重置为 -1，
  ///   下次 next()/previous() 会从列表头开始。
  void setPlaylist(List<Song> songs) {
    final cur = state.currentSong;
    int newIndex = state.currentIndex;
    if (cur != null) {
      newIndex = songs.indexWhere((s) => s.filePath == cur.filePath);
    }
    state = state.copyWith(playlist: songs, currentIndex: newIndex);
  }

  /// 播放列表中指定位置的歌曲
  void playSongAt(int index) {
    if (index < 0 || index >= state.playlist.length) return;
    final song = state.playlist[index];
    state = state.copyWith(currentIndex: index);
    _playFile(song);
  }

  /// 播放指定歌曲文件
  void _playFile(Song song) async {
    state = state.copyWith(
      isLoading: true,
      clearLyrics: true,
      clearCover: true,
      clearError: true,
      clearLoop: true,
    );

    // 切歌时显示默认文本
    NativeUtils.updateLyricsOverlay(_defaultOverlayText(song), '');

    try {
      // WebDAV 文件需要先下载到本地缓存
      String playPath = song.filePath;
      if (playPath.startsWith('webdav://')) {
        final webDav = ref.read(webDavProvider.notifier);
        playPath = await webDav.ensureLocalFile(song);
      }

      if (Platform.isAndroid) {
        await _androidPlayer('play', playPath);
        await _androidPlayer('setVolume', state.volume.toString());
      } else {
        rust_player.playerPlay(filePath: playPath);
        rust_player.playerSetVolume(volume: state.volume);
      }

      // 恢复当前播放速度
      final speed = ref.read(playbackSpeedProvider);
      if (speed != 1.0) {
        if (Platform.isAndroid) {
          _androidPlayer('setSpeed', speed.toString());
        } else {
          rust_player.playerSetSpeed(speed: speed);
        }
      }

      state = state.copyWith(
        currentSong: song,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration(seconds: song.duration.toInt()),
        isLoading: false,
      );

      // 记录播放次数
      rust_play_stats.recordPlay(
        filePath: song.filePath,
        title: song.title,
        artist: song.artist,
      );

      // 记录听歌日历打卡
      ListeningCalendarService.instance.recordPlay();

      // 记录播放历史
      PlayHistoryService.instance.recordPlay(
        filePath: song.filePath,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
      );
      PlayHistoryService.instance.save();

      // 检查成就解锁
      AchievementService.instance.checkAndUnlock();

      // 播放歌曲时更新原生托盘及窗口标题
      NativeUtils.updateTitle('${song.title} - ${song.artist}');

      // 更新系统媒体会话
      _updateMediaSessionMetadata(song);
      _updateMediaSessionPlayback(true, Duration.zero);

      _startPositionTimer();
      _startSpectrumTimer();
      _fetchOnlineInfo(song);
    } catch (e) {
      print('播放失败: $e');
      state = state.copyWith(
        isPlaying: false,
        isLoading: false,
        error: '播放失败: $e',
      );
    }
  }

  static const _playerChannel = MethodChannel('com.jmusic.app/player');

  Future<dynamic> _androidPlayer(String method, String arg) async {
    return await _playerChannel.invokeMethod(method, arg);
  }

  /// 获取歌曲信息：优先读源文件嵌入数据，无则在线获取
  Future<void> _fetchOnlineInfo(Song song) async {
    bool hasLyrics = false;
    bool hasCover = false;

    // —— 先读源文件嵌入数据 ——
    try {
      final embeddedCover = await rust_scanner.readEmbeddedCover(
        filePath: song.filePath,
      );
      if (embeddedCover != null &&
          state.currentSong?.filePath == song.filePath) {
        state = state.copyWith(coverData: embeddedCover);
        hasCover = true;
      }
    } catch (_) {}

    try {
      final embeddedLrc = await rust_scanner.readEmbeddedLyrics(
        filePath: song.filePath,
      );
      if (embeddedLrc != null && state.currentSong?.filePath == song.filePath) {
        final lyrics = rust_metadata.parseLrcText(lrcText: embeddedLrc);
        state = state.copyWith(lyrics: lyrics, lrcText: embeddedLrc);
        hasLyrics = true;
      }
    } catch (_) {}

    // 如果嵌入数据已齐全，无需在线获取
    if (hasLyrics && hasCover) return;

    // —— 在线获取缺失的数据 ——
    try {
      var results = await rust_metadata.searchSongOnline(
        keyword: '${song.artist} ${song.title}',
      );
      if (results.isEmpty) {
        results = await rust_metadata.searchSongOnline(keyword: song.title);
      }

      if (results.isNotEmpty) {
        final match = results.first;

        // 用在线信息补全/更新当前歌曲的基本信息
        if (state.currentSong?.filePath == song.filePath) {
          final oldSong = state.currentSong!;
          final artistName = match.singer.isNotEmpty
              ? match.singer.map((s) => s.name).join('/')
              : oldSong.artist;

          final updatedSong = Song(
            filePath: oldSong.filePath,
            title: match.songname.isNotEmpty ? match.songname : oldSong.title,
            artist: artistName,
            album: match.albumname.isNotEmpty ? match.albumname : oldSong.album,
            duration: oldSong.duration,
            fileSize: oldSong.fileSize,
            format: oldSong.format,
            songmid: match.songmid,
            albummid: match.albummid,
            modifiedAt: oldSong.modifiedAt,
          );
          state = state.copyWith(currentSong: updatedSong);
          // 在线更新了歌曲或歌手信息后，同步刷新原生托盘和窗口标题
          NativeUtils.updateTitle('${updatedSong.title} - ${updatedSong.artist}');
          // 同步更新系统媒体会话元数据
          _updateMediaSessionMetadata(updatedSong);
        }

        // 歌词（嵌入数据没有时才在线获取）
        if (!hasLyrics) {
          try {
            final lyrics = await rust_metadata.getLyrics(
              songmid: match.songmid,
            );
            if (state.currentSong?.filePath == song.filePath) {
              state = state.copyWith(lyrics: lyrics);
            }
          } catch (_) {}
        }

        // 封面（嵌入数据没有时才在线获取）
        if (!hasCover) {
          try {
            final coverData = await rust_metadata.getCover(
              albummid: match.albummid,
            );
            if (state.currentSong?.filePath == song.filePath) {
              state = state.copyWith(coverData: coverData);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 暂停/恢复切换
  void togglePlayPause() {
    if (state.currentSong == null) {
      // 没有正在播放的歌曲时，随机开始播放一首
      _playRandom();
      return;
    }
    if (state.isPlaying) {
      if (Platform.isAndroid) {
        _androidPlayer('pause', '');
      } else {
        rust_player.playerPause();
      }
      _positionTimer?.cancel();
      _spectrumTimer?.cancel();
      state = state.copyWith(isPlaying: false, spectrum: emptySpectrum());
      _updateMediaSessionPlayback(false, state.position);
    } else {
      if (Platform.isAndroid) {
        _androidPlayer('resume', '');
      } else {
        rust_player.playerResume();
      }
      _startPositionTimer();
      _startSpectrumTimer();
      state = state.copyWith(isPlaying: true);
      _updateMediaSessionPlayback(true, state.position);
    }
  }

  /// 下一首
  void next() {
    if (state.playlist.isEmpty && state.queue.isEmpty) return;

    // 队列优先：如果有播放队列，从队列头部取出播放
    if (state.queue.isNotEmpty) {
      final nextSong = state.queue.first;
      final remaining = List<Song>.from(state.queue)..removeAt(0);
      state = state.copyWith(queue: remaining);
      _playFile(nextSong);
      return;
    }

    if (state.currentSong == null) {
      _playRandom();
      return;
    }
    
    if (state.playMode == PlayMode.shuffle) {
      final random = Random().nextInt(state.playlist.length);
      playSongAt(random);
      return;
    }
    
    int nextIndex = (state.currentIndex + 1) % state.playlist.length;
    playSongAt(nextIndex);
  }

  /// 上一首
  void previous() {
    if (state.playlist.isEmpty) return;

    if (state.currentSong == null) {
      _playRandom();
      return;
    }
    
    if (state.playMode == PlayMode.shuffle) {
      final random = Random().nextInt(state.playlist.length);
      playSongAt(random);
      return;
    }
    
    int prevIndex = state.currentIndex - 1;
    if (prevIndex < 0) prevIndex = state.playlist.length - 1;
    playSongAt(prevIndex);
  }

  /// 随机播放一首歌（用于没有正在播放歌曲时的首次启动）
  void _playRandom() {
    if (state.playlist.isEmpty) return;
    final index = Random().nextInt(state.playlist.length);
    playSongAt(index);
  }

  /// 跳转到指定位置
  void seekTo(Duration position) {
    _isSeeking = true;
    state = state.copyWith(position: position);
    try {
      if (Platform.isAndroid) {
        _androidPlayer('seek', (position.inMilliseconds / 1000.0).toString());
      } else {
        rust_player.playerSeek(positionSecs: position.inMilliseconds / 1000.0);
      }
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 600), () {
      _isSeeking = false;
    });
  }

  /// 设置音量
  void setVolume(double volume) {
    if (Platform.isAndroid) {
      _androidPlayer('setVolume', volume.toString());
    } else {
      rust_player.playerSetVolume(volume: volume);
    }
    state = state.copyWith(volume: volume);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final modes = PlayMode.values;
    final nextIndex = (state.playMode.index + 1) % modes.length;
    final newMode = modes[nextIndex];
    state = state.copyWith(playMode: newMode);
    NativeUtils.updatePlayMode(newMode);
  }

  /// A-B 复读循环：切换状态
  /// off -> setA（标记当前位置为 A 点）
  /// setA -> active（标记当前位置为 B 点，开始循环）
  /// active -> off（清除循环）
  void toggleABLoop() {
    switch (state.abLoopState) {
      case ABLoopState.off:
        // 设置 A 点
        state = state.copyWith(
          abLoopState: ABLoopState.setA,
          loopStart: state.position,
        );
        break;
      case ABLoopState.setA:
        // 设置 B 点，激活循环
        final loopEnd = state.position;
        // B 点必须在 A 点之后
        if (loopEnd > (state.loopStart ?? Duration.zero)) {
          state = state.copyWith(
            abLoopState: ABLoopState.active,
            loopEnd: loopEnd,
          );
        } else {
          // B 点在 A 点之前，重新设置 A 点为当前位置
          state = state.copyWith(
            loopStart: state.position,
          );
        }
        break;
      case ABLoopState.active:
        // 清除循环
        state = state.copyWith(clearLoop: true);
        break;
    }
  }

  /// 清除 A-B 循环
  void clearABLoop() {
    state = state.copyWith(clearLoop: true);
  }

  // ─── 播放队列管理 ─────────────────────────────────────────────────────

  /// 下一首播放（插入队列头部）
  void playNextInQueue(Song song) {
    final queue = List<Song>.from(state.queue);
    queue.insert(0, song);
    state = state.copyWith(queue: queue);
  }

  /// 添加到队列末尾
  void addToQueue(Song song) {
    final queue = List<Song>.from(state.queue)..add(song);
    state = state.copyWith(queue: queue);
  }

  /// 从队列中移除指定位置
  void removeFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;
    final queue = List<Song>.from(state.queue)..removeAt(index);
    state = state.copyWith(queue: queue);
  }

  /// 清空播放队列
  void clearQueue() {
    state = state.copyWith(queue: []);
  }

  // ─── 播放历史 ─────────────────────────────────────────────────────────

  /// 获取最近播放历史
  List<PlayHistoryEntry> getPlayHistory() {
    return PlayHistoryService.instance.entries;
  }

  /// 清除播放历史
  void clearPlayHistory() {
    PlayHistoryService.instance.clear();
    PlayHistoryService.instance.save();
  }

  /// 更新当前播放歌曲的元数据和歌词（主要用于导入歌词后的实时同步）
  void updateCurrentSongLyrics({required Song song, String? lyricsText}) {
    if (state.currentSong?.filePath != song.filePath) return;

    Lyrics? lyrics;
    if (lyricsText != null && lyricsText.isNotEmpty) {
      lyrics = rust_metadata.parseLrcText(lrcText: lyricsText);
    }

    state = state.copyWith(
      currentSong: song,
      lyrics: lyrics,
      lrcText: lyricsText,
      clearLyrics: lyrics == null,
    );

    // 同步更新原生窗口和托盘标题
    NativeUtils.updateTitle('${song.title} - ${song.artist}');
  }
}

/// 播放器全局 Provider
final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);

/// 歌曲库状态
class LibraryState {
  final List<Song> songs;
  final bool isScanning;
  final String? error;

  const LibraryState({
    this.songs = const [],
    this.isScanning = false,
    this.error,
  });

  LibraryState copyWith({List<Song>? songs, bool? isScanning, String? error}) {
    return LibraryState(
      songs: songs ?? this.songs,
      isScanning: isScanning ?? this.isScanning,
      error: error,
    );
  }
}

/// 歌曲库状态管理
class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    // 延迟加载，确保 build() 先返回初始状态后再操作 state
    Future.microtask(() => _loadLibrary());
    return const LibraryState();
  }

  /// 加载本地歌曲库
  void _loadLibrary() {
    try {
      final library = rust_scanner.getLibrary();
      state = state.copyWith(songs: library.songs);
      // 同步播放列表到 PlayerNotifier
      if (library.songs.isNotEmpty) {
        ref.read(playerProvider.notifier).setPlaylist(library.songs);
      }
    } catch (e) {
      state = state.copyWith(error: '加载歌曲库失败: $e');
    }
  }

  /// 扫描音乐目录（累加模式）
  Future<void> scanDirectory(String dirPath) async {
    state = state.copyWith(isScanning: true, error: null);
    try {
      final library = await rust_scanner.scanAndUpdateLibrary(dirPath: dirPath);
      state = state.copyWith(songs: library.songs, isScanning: false);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: '扫描失败: $e');
    }
  }

  /// 扫描音乐目录（覆盖模式）
  Future<void> scanDirectoryReplace(String dirPath) async {
    state = state.copyWith(isScanning: true, error: null);
    try {
      final library = await rust_scanner.scanAndReplaceLibrary(dirPath: dirPath);
      state = state.copyWith(songs: library.songs, isScanning: false);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: '扫描失败: $e');
    }
  }

  /// 更新歌曲元数据（写入文件标签 + 刷新本地状态）
  Future<void> updateSongInfo({
    required String filePath,
    required String title,
    required String artist,
    required String album,
  }) async {
    // 调用 Rust 端写入文件标签并更新 library.json
    await rust_scanner.updateSongMetadata(
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
    );

    // 更新本地状态
    final updatedSongs = state.songs.map((song) {
      if (song.filePath == filePath) {
        return Song(
          filePath: song.filePath,
          title: title,
          artist: artist,
          album: album,
          duration: song.duration,
          fileSize: song.fileSize,
          format: song.format,
          songmid: song.songmid,
          albummid: song.albummid,
          modifiedAt: song.modifiedAt,
        );
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs);

    // 同步到播放列表
    ref.read(playerProvider.notifier).setPlaylist(updatedSongs);
  }

  /// 完整保存歌曲信息、歌词和封面，并刷新本地状态
  Future<void> saveAllMetadataAndUpdate({
    required Song song,
    String? lyricsText,
    List<int>? coverData,
  }) async {
    // 调用 Rust 端写入文件标签并更新 library.json
    await rust_scanner.saveAllMetadata(
      filePath: song.filePath,
      title: song.title,
      artist: song.artist,
      album: song.album,
      lyricsText: lyricsText,
      coverData: coverData != null ? Uint8List.fromList(coverData) : null,
    );

    // 更新本地状态（song已经是更新好基本信息的对象）
    final updatedSongs = state.songs.map((s) {
      if (s.filePath == song.filePath) {
        return song;
      }
      return s;
    }).toList();

    state = state.copyWith(songs: updatedSongs);

    // 同步到播放列表
    ref.read(playerProvider.notifier).setPlaylist(updatedSongs);

    // 如果当前正在播放这首歌，同步更新播放器状态
    final playerNotifier = ref.read(playerProvider.notifier);
    final playerState = ref.read(playerProvider);
    if (playerState.currentSong?.filePath == song.filePath) {
      playerNotifier.updateCurrentSongLyrics(
        song: song,
        lyricsText: lyricsText,
      );
    }
  }
}

/// 歌曲库全局 Provider
final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);

/// 原生系统通信工具类，用于更新系统窗口和托盘的显示状态
class NativeUtils {
  static const _channel = MethodChannel('com.jmusic.app/tray');

  /// 更新原生窗口和系统托盘标题提示（仅在 Windows 平台执行）
  static Future<void> updateTitle(String title) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('updateTitle', title);
    } catch (e) {
      print('更新原生托盘和任务栏标题失败: $e');
    }
  }

  /// 显示桌面悬浮歌词
  static Future<void> showLyricsOverlay() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('showLyricsOverlay');
    } catch (e) {
      print('显示桌面歌词失败: $e');
    }
  }

  /// 隐藏桌面悬浮歌词
  static Future<void> hideLyricsOverlay() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('hideLyricsOverlay');
    } catch (e) {
      print('隐藏桌面歌词失败: $e');
    }
  }

  /// 更新桌面悬浮歌词文本
  static Future<void> updateLyricsOverlay(String currentLine, String nextLine) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('updateLyrics', {
        'current': currentLine,
        'next': nextLine,
      });
    } catch (e) {
      // 静默失败，避免频繁打印
    }
  }

  /// 查询桌面歌词是否可见
  static Future<bool> isLyricsOverlayVisible() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod('isLyricsOverlayVisible');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 更新托盘菜单中显示的播放模式文本
  static Future<void> updatePlayMode(PlayMode mode) async {
    if (!Platform.isWindows) return;
    String label;
    switch (mode) {
      case PlayMode.sequential:
        label = '顺序播放';
      case PlayMode.shuffle:
        label = '随机播放';
      case PlayMode.singleLoop:
        label = '单曲循环';
    }
    try {
      await _channel.invokeMethod('updatePlayMode', label);
    } catch (_) {}
  }
}
