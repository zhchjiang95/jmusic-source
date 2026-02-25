import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/src/rust/api/player.dart' as rust_player;
import 'package:jmusic/src/rust/api/scanner.dart' as rust_scanner;
import 'package:jmusic/src/rust/api/metadata.dart' as rust_metadata;
import 'package:jmusic/src/rust/models/song.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';

/// 播放模式枚举
enum PlayMode {
  /// 顺序播放
  sequential,

  /// 单曲循环
  singleLoop,

  /// 随机播放
  shuffle,
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
  final List<int>? coverData;
  final bool isLoading;

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
    this.coverData,
    this.isLoading = false,
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
    List<int>? coverData,
    bool? isLoading,
    bool clearLyrics = false,
    bool clearCover = false,
    bool clearSong = false,
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
      coverData: clearCover ? null : (coverData ?? this.coverData),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 播放器状态管理（Riverpod 3.x Notifier）
class PlayerNotifier extends Notifier<PlayerState> {
  Timer? _positionTimer;

  @override
  PlayerState build() {
    // 初始化时启动音频引擎
    _initEngine();
    // 清理定时器
    ref.onDispose(() {
      _positionTimer?.cancel();
      try {
        rust_player.playerStop();
      } catch (_) {}
    });
    return const PlayerState();
  }

  /// 初始化音频引擎
  void _initEngine() {
    try {
      rust_player.playerInit();
    } catch (e) {
      print('音频引擎初始化失败: $e');
    }
  }

  /// 开始定时更新播放进度
  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (state.isPlaying && state.currentSong != null) {
        final newPos = state.position + const Duration(milliseconds: 500);
        if (newPos >= state.duration) {
          _onPlaybackFinished();
        } else {
          state = state.copyWith(position: newPos);
        }
      }
    });
  }

  /// 播放结束处理
  void _onPlaybackFinished() {
    switch (state.playMode) {
      case PlayMode.singleLoop:
        if (state.currentSong != null) {
          _playFile(state.currentSong!);
        }
      case PlayMode.sequential:
        next();
      case PlayMode.shuffle:
        if (state.playlist.isNotEmpty) {
          final random =
              DateTime.now().millisecondsSinceEpoch % state.playlist.length;
          playSongAt(random);
        }
    }
  }

  /// 设置播放列表
  void setPlaylist(List<Song> songs) {
    state = state.copyWith(playlist: songs);
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
    );

    try {
      rust_player.playerPlay(filePath: song.filePath);
      rust_player.playerSetVolume(volume: state.volume);

      state = state.copyWith(
        currentSong: song,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration(seconds: song.duration.toInt()),
        isLoading: false,
      );

      _startPositionTimer();
      _fetchOnlineInfo(song);
    } catch (e) {
      state = state.copyWith(isPlaying: false, isLoading: false);
    }
  }

  /// 异步获取在线歌曲信息（歌词和封面）
  Future<void> _fetchOnlineInfo(Song song) async {
    try {
      final keyword = '${song.artist} ${song.title}';
      final results = await rust_metadata.searchSongOnline(keyword: keyword);

      if (results.isNotEmpty) {
        final match = results.first;

        // 获取歌词
        try {
          final lyrics = await rust_metadata.getLyrics(songmid: match.songmid);
          if (state.currentSong?.filePath == song.filePath) {
            state = state.copyWith(lyrics: lyrics);
          }
        } catch (_) {}

        // 获取封面
        try {
          final coverData = await rust_metadata.getCover(
            albummid: match.albummid,
          );
          if (state.currentSong?.filePath == song.filePath) {
            state = state.copyWith(coverData: coverData);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 暂停/恢复切换
  void togglePlayPause() {
    if (state.isPlaying) {
      rust_player.playerPause();
      _positionTimer?.cancel();
      state = state.copyWith(isPlaying: false);
    } else {
      rust_player.playerResume();
      _startPositionTimer();
      state = state.copyWith(isPlaying: true);
    }
  }

  /// 下一首
  void next() {
    if (state.playlist.isEmpty) return;
    int nextIndex = (state.currentIndex + 1) % state.playlist.length;
    playSongAt(nextIndex);
  }

  /// 上一首
  void previous() {
    if (state.playlist.isEmpty) return;
    int prevIndex = state.currentIndex - 1;
    if (prevIndex < 0) prevIndex = state.playlist.length - 1;
    playSongAt(prevIndex);
  }

  /// 跳转到指定位置
  void seekTo(Duration position) {
    rust_player.playerSeek(positionSecs: position.inMilliseconds / 1000.0);
    state = state.copyWith(position: position);
  }

  /// 设置音量
  void setVolume(double volume) {
    rust_player.playerSetVolume(volume: volume);
    state = state.copyWith(volume: volume);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final modes = PlayMode.values;
    final nextIndex = (state.playMode.index + 1) % modes.length;
    state = state.copyWith(playMode: modes[nextIndex]);
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

  /// 扫描音乐目录
  Future<void> scanDirectory(String dirPath) async {
    state = state.copyWith(isScanning: true, error: null);
    try {
      final library = await rust_scanner.scanAndUpdateLibrary(dirPath: dirPath);
      state = state.copyWith(songs: library.songs, isScanning: false);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: '扫描失败: $e');
    }
  }
}

/// 歌曲库全局 Provider
final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
