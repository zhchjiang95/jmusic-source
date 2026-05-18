import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
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
  final String? lrcText; // 原始 LRC 文本（用于保存到文件）
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
    this.lrcText,
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
    String? lrcText,
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
      lrcText: clearLyrics ? null : (lrcText ?? this.lrcText),
      coverData: clearCover ? null : (coverData ?? this.coverData),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 播放器状态管理（Riverpod 3.x Notifier）
class PlayerNotifier extends Notifier<PlayerState> {
  Timer? _positionTimer;
  bool _isSeeking = false;

  @override
  PlayerState build() {
    // 初始化时启动音频引擎
    _initEngine();
    // 初始化时设置默认的原生窗口和托盘提示
    NativeUtils.updateTitle('JMusic');
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
      // seek 期间跳过更新，防止覆盖用户设置的新位置
      if (_isSeeking) return;
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
      case PlayMode.shuffle:
        next();
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

      // 播放歌曲时更新原生托盘及窗口标题
      NativeUtils.updateTitle('${song.title} - ${song.artist}');

      _startPositionTimer();
      _fetchOnlineInfo(song);
    } catch (e) {
      state = state.copyWith(isPlaying: false, isLoading: false);
    }
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
    
    if (state.playMode == PlayMode.shuffle) {
      final random = DateTime.now().millisecondsSinceEpoch % state.playlist.length;
      playSongAt(random);
      return;
    }
    
    int nextIndex = (state.currentIndex + 1) % state.playlist.length;
    playSongAt(nextIndex);
  }

  /// 上一首
  void previous() {
    if (state.playlist.isEmpty) return;
    
    if (state.playMode == PlayMode.shuffle) {
      final random = DateTime.now().millisecondsSinceEpoch % state.playlist.length;
      playSongAt(random);
      return;
    }
    
    int prevIndex = state.currentIndex - 1;
    if (prevIndex < 0) prevIndex = state.playlist.length - 1;
    playSongAt(prevIndex);
  }

  /// 跳转到指定位置
  void seekTo(Duration position) {
    _isSeeking = true;
    state = state.copyWith(position: position);
    try {
      rust_player.playerSeek(positionSecs: position.inMilliseconds / 1000.0);
    } catch (_) {
      // seek 失败（部分格式不支持），忽略错误
    }
    // 延迟解除标志，确保定时器至少跳过一个周期
    Future.delayed(const Duration(milliseconds: 600), () {
      _isSeeking = false;
    });
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
}
