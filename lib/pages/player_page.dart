import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/lyrics_alignment.dart';
import 'package:jmusic/providers/playback_speed.dart';
import 'package:jmusic/providers/player_style.dart';
import 'package:jmusic/providers/sleep_timer.dart';
import 'package:jmusic/pages/lyrics_editor_page.dart';
import 'package:jmusic/widgets/lyrics_view.dart';
import 'package:jmusic/widgets/particles_bg.dart';
import 'package:jmusic/widgets/cast_sheet.dart';
import 'package:jmusic/widgets/sleep_timer_sheet.dart';
import 'package:jmusic/widgets/speed_control_sheet.dart';
import 'package:jmusic/widgets/spectrum_view.dart';
import 'package:jmusic/widgets/vinyl_disc.dart';
import 'package:jmusic/providers/cast_provider.dart';
import 'package:jmusic/providers/wakelock_provider.dart';

/// 先锋双栏空间声学播放页
///
/// 核心设计：
/// 1. 左右双栏空间布局：左侧为「3D 视差封面舞台 + 融合频谱声学控制台」，右侧为「杂志风歌曲抬头 + 全尺寸逐字歌词舞台」。
/// 2. 封面支持鼠标 3D 空间视差倾斜（Parallax Tilt）、光泽反射与随低频频谱呼吸的动态弥散光晕（Audio-Reactive Glow）。
/// 3. 页内支持一键无缝切换「双栏舞台 ↔ 纯享全屏歌词模式」（平滑收起/展开左栏，快捷键 L）。
/// 4. 智能净空模式（Auto-Hide Controls）：无论在双栏播放页还是纯享歌词界面，鼠标静止 3 秒或移出窗口后自动平滑隐藏所有操作按钮与控制面板，保持画面纯粹干净；鼠标移入或移动时立即恢复显示。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 是否处于页内“纯享全屏歌词”模式（收起左侧封面舞台，歌词居中铺满）
  bool _isPureLyricsMode = false;

  /// 操作按钮与控制栏是否可见（静止 3 秒或鼠标移出窗口后自动隐藏）
  bool _controlsVisible = true;

  /// 自动隐藏计时器
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  /// 启动或重置 3 秒无操作自动隐藏计时器
  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  /// 鼠标移入、移动、点击或滚轮操作时唤醒全部控制按钮
  void _onUserPointerActivity() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _startHideTimer();
  }

  /// 鼠标移出窗口时立即隐藏操作按钮，保持画面纯粹干净
  void _onPointerExit() {
    _hideTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() {
        _controlsVisible = false;
      });
    }
  }

  void _togglePureLyricsMode() {
    setState(() {
      _isPureLyricsMode = !_isPureLyricsMode;
    });
    _onUserPointerActivity();
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final playMode = ref.watch(playerProvider.select((s) => s.playMode));
    final volume = ref.watch(playerProvider.select((s) => s.volume));
    final visualStyle = ref.watch(playerVisualStyleProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(playerProvider.notifier);

    return KeepScreenAwake(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () {
            notifier.togglePlayPause();
            _onUserPointerActivity();
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            notifier.next();
            _onUserPointerActivity();
          },
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            notifier.previous();
            _onUserPointerActivity();
          },
          const SingleActivator(LogicalKeyboardKey.keyL):
              _togglePureLyricsMode,
          const SingleActivator(LogicalKeyboardKey.keyA): () {
            ref.read(lyricsAlignmentProvider.notifier).cycle();
            _onUserPointerActivity();
          },
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_isPureLyricsMode) {
              setState(() => _isPureLyricsMode = false);
              _onUserPointerActivity();
            } else {
              Navigator.of(context).pop();
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFF08080E),
            body: MouseRegion(
              cursor: _controlsVisible
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onEnter: (_) => _onUserPointerActivity(),
              onHover: (_) => _onUserPointerActivity(),
              onExit: (_) => _onPointerExit(),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerHover: (_) => _onUserPointerActivity(),
                onPointerMove: (_) => _onUserPointerActivity(),
                onPointerDown: (_) => _onUserPointerActivity(),
                onPointerSignal: (_) => _onUserPointerActivity(),
                child: Stack(
                  children: [
                    // 1. 多层流体模糊与声学光影背景
                    Positioned.fill(
                      child: _buildBackground(ref, visualStyle, theme),
                    ),

                    // 2. 粒子氛围层（黑胶风格下激活）
                    if (visualStyle == PlayerVisualStyle.vinyl)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ParticlesBackground(
                            color: theme.colorScheme.primary,
                            active: isPlaying,
                          ),
                        ),
                      ),

                    // 3. 主体双栏响应式舞台
                    SafeArea(
                      child: Column(
                        children: [
                          // 顶部工具栏（静止后自动平滑上移淡出，保留占位高度避免布局跳动）
                          IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              offset: _controlsVisible
                                  ? Offset.zero
                                  : const Offset(0, -0.45),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                opacity: _controlsVisible ? 1.0 : 0.0,
                                child: _buildTopBar(
                                  context,
                                  ref,
                                  visualStyle,
                                  theme,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 740;
                                if (!isWide) {
                                  return _buildCompactVerticalStage(
                                    context: context,
                                    ref: ref,
                                    currentSong: currentSong,
                                    visualStyle: visualStyle,
                                    isPlaying: isPlaying,
                                    playMode: playMode,
                                    volume: volume,
                                    theme: theme,
                                  );
                                }

                                return _buildSplitSpatialStage(
                                  context: context,
                                  ref: ref,
                                  constraints: constraints,
                                  currentSong: currentSong,
                                  visualStyle: visualStyle,
                                  isPlaying: isPlaying,
                                  playMode: playMode,
                                  volume: volume,
                                  theme: theme,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建宽屏左右双栏空间舞台（支持平滑收起左栏进入纯享歌词态，且支持自动隐藏操作按钮）
  Widget _buildSplitSpatialStage({
    required BuildContext context,
    required WidgetRef ref,
    required BoxConstraints constraints,
    required dynamic currentSong,
    required PlayerVisualStyle visualStyle,
    required bool isPlaying,
    required PlayMode playMode,
    required double volume,
    required ThemeData theme,
  }) {
    final leftPanelWidth = _isPureLyricsMode
        ? 0.0
        : (constraints.maxWidth * 0.44).clamp(320.0, 520.0);

    final showFloatingDock = _isPureLyricsMode && _controlsVisible;

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左栏：3D 视差专辑舞台 + 融合频谱控制台
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutQuart,
              width: leftPanelWidth,
              child: ClipRect(
                clipBehavior: _isPureLyricsMode ? Clip.hardEdge : Clip.none,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 280),
                  opacity: _isPureLyricsMode ? 0.0 : 1.0,
                  child: OverflowBox(
                    minWidth: 320,
                    maxWidth: 520,
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 8, 20, 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 专辑封面 / 黑胶舞台（自适应剩余高度）
                          Flexible(
                            flex: 6,
                            child: Center(
                              child: _InteractiveAlbumStage(
                                style: visualStyle,
                                isPlaying: isPlaying,
                                controlsVisible: true,
                                onTap: () => ref
                                    .read(playerVisualStyleProvider.notifier)
                                    .next(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          // 声学频谱进度与主控舱（常驻显示，鼠标静止隐藏顶部按钮时透明度同步降为 0.6）
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            opacity: _controlsVisible ? 1.0 : 0.3,
                            child: _buildAcousticControlDeck(
                              context: context,
                              ref: ref,
                              isPlaying: isPlaying,
                              playMode: playMode,
                              volume: volume,
                              theme: theme,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 中间微光分割线（仅在双栏且显示操作控件时微弱显现）
            if (!_isPureLyricsMode)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _controlsVisible ? 1.0 : 0.3,
                child: Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                ),
              ),

            // 右栏：先锋杂志风歌曲抬头 + 完整逐字渐变歌词流
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _isPureLyricsMode ? 48 : 28,
                  8,
                  _isPureLyricsMode ? 48 : 36,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 杂志级歌曲头部信息
                    _buildEditorialHeader(
                      context: context,
                      ref: ref,
                      currentSong: currentSong,
                      theme: theme,
                    ),
                    const SizedBox(height: 12),
                    // 完整滚动歌词（支持逐字颜色渐变、层次透明度、点击跳转）
                    Expanded(
                      child: LyricsView(
                        isFullScreen: true,
                        isExpandedStage: _isPureLyricsMode,
                        controlsVisible: _controlsVisible,
                        onSearchLyrics: currentSong != null
                            ? () => _showSearchLyricsOptions(
                                  context,
                                  currentSong.title,
                                )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // 纯享全屏歌词模式下底部浮现的轻量级悬浮胶囊控制条（静止 3 秒后同样自动隐藏）
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !showFloatingDock,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              offset: showFloatingDock ? Offset.zero : const Offset(0, 0.7),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: showFloatingDock ? 1.0 : 0.0,
                child: Center(
                  child: _buildFloatingPureModeDock(
                    context: context,
                    ref: ref,
                    isPlaying: isPlaying,
                    theme: theme,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 窄窗口响应式紧凑布局（窗口宽度 < 740px 时优雅降级）
  Widget _buildCompactVerticalStage({
    required BuildContext context,
    required WidgetRef ref,
    required dynamic currentSong,
    required PlayerVisualStyle visualStyle,
    required bool isPlaying,
    required PlayMode playMode,
    required double volume,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          // 紧凑型头部：小封面 + 歌曲信息
          if (!_isPureLyricsMode)
            Row(
              children: [
                GestureDetector(
                  onTap: () =>
                      ref.read(playerVisualStyleProvider.notifier).next(),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: _InteractiveAlbumStage(
                      style: visualStyle,
                      isPlaying: isPlaying,
                      controlsVisible: _controlsVisible,
                      maxStageSize: 76,
                      onTap: () =>
                          ref.read(playerVisualStyleProvider.notifier).next(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildEditorialHeader(
                    context: context,
                    ref: ref,
                    currentSong: currentSong,
                    theme: theme,
                    isCompact: true,
                  ),
                ),
              ],
            )
          else
            _buildEditorialHeader(
              context: context,
              ref: ref,
              currentSong: currentSong,
              theme: theme,
              isCompact: true,
            ),
          const SizedBox(height: 10),
          // 中部完整逐字歌词
          Expanded(
            child: LyricsView(
              isFullScreen: true,
              isExpandedStage: _isPureLyricsMode,
              controlsVisible: _controlsVisible,
              onSearchLyrics: currentSong != null
                  ? () => _showSearchLyricsOptions(context, currentSong.title)
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          // 底部声学控制舱（常驻显示，鼠标静止隐藏顶部按钮时透明度同步降为 0.6）
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            opacity: _controlsVisible ? 1.0 : 0.3,
            child: _buildAcousticControlDeck(
              context: context,
              ref: ref,
              isPlaying: isPlaying,
              playMode: playMode,
              volume: volume,
              theme: theme,
              isCompact: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 背景层 — 多层动态封面高斯模糊 + 呼吸暗角
  Widget _buildBackground(
    WidgetRef ref,
    PlayerVisualStyle style,
    ThemeData theme,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final coverData = ref.watch(playerProvider.select((s) => s.coverData));
        final spectrum = ref.watch(playerProvider.select((s) => s.spectrum));

        // 提取低频能量驱动背景氛围光斑呼吸
        double bassEnergy = 0.0;
        if (spectrum.isNotEmpty) {
          final count = math.min(8, spectrum.length);
          double sum = 0;
          for (int i = 0; i < count; i++) {
            sum += spectrum[i];
          }
          bassEnergy = (sum / count).clamp(0.0, 1.0);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 底层深邃渐变
            _defaultGradientBg(theme),

            // 封面流体模糊层（blur 与 standard 下均提供不同浓度的空间染色）
            if (coverData != null && style != PlayerVisualStyle.vinyl)
              Opacity(
                opacity: style == PlayerVisualStyle.blur ? 0.65 : 0.25,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: Transform.scale(
                    scale: 1.25,
                    child: Image.memory(
                      Uint8List.fromList(coverData),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),

            // 随低频律动的柔和环境光晕（使用同色相 0 透明度收尾，消除生硬边界）
            Positioned(
              left: -180,
              bottom: -180,
              width: 720 + bassEnergy * 120,
              height: 720 + bassEnergy * 120,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        theme.colorScheme.primary.withValues(
                          alpha: (0.09 + bassEnergy * 0.10).clamp(0.0, 0.22),
                        ),
                        theme.colorScheme.primary.withValues(alpha: 0.03),
                        theme.colorScheme.primary.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 全局均匀柔化暗罩（保证歌词高对比度，且避免左右明暗割裂）
            Container(
              color: Colors.black.withValues(alpha: 0.42),
            ),
          ],
        );
      },
    );
  }

  Widget _defaultGradientBg(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.36, 0.72, 1.0],
          colors: [
            Color.lerp(const Color(0xFF0B0B14), primary, 0.18)!,
            Color.lerp(const Color(0xFF0A0A12), primary, 0.10)!,
            Color.lerp(const Color(0xFF08080F), primary, 0.04)!,
            const Color(0xFF07070C),
          ],
        ),
      ),
    );
  }

  /// 顶部先锋导航与模式工具栏（严格避让 macOS 交通灯）
  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    PlayerVisualStyle visualStyle,
    ThemeData theme,
  ) {
    final topPadding = Platform.isMacOS ? 12.0 : 8.0;
    final leftPadding = Platform.isMacOS ? 84.0 : 20.0;
    final rightPadding = 24.0;

    final styleLabel = switch (visualStyle) {
      PlayerVisualStyle.blur => '流光模糊',
      PlayerVisualStyle.vinyl => '黑胶唱盘',
      PlayerVisualStyle.standard => '深邃极简',
    };

    final styleIcon = switch (visualStyle) {
      PlayerVisualStyle.blur => Icons.blur_on_rounded,
      PlayerVisualStyle.vinyl => Icons.album_rounded,
      PlayerVisualStyle.standard => Icons.auto_awesome_rounded,
    };

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: 6.0,
        left: leftPadding,
        right: rightPadding,
      ),
      child: Row(
        children: [
          // 收起播放页胶囊按钮
          _buildGlassPillButton(
            onTap: () => Navigator.of(context).pop(),
            icon: Icons.keyboard_arrow_down_rounded,
            label: '收起',
            tooltip: '收起播放页 (Esc)',
          ),
          const SizedBox(width: 10),
          // 视觉风格切换胶囊
          _buildGlassPillButton(
            onTap: () => ref.read(playerVisualStyleProvider.notifier).next(),
            icon: styleIcon,
            label: styleLabel,
            tooltip: '点击切换视觉舞台风格',
          ),

          const Spacer(),

          // 页内纯享歌词 / 双栏舞台切换按钮
          _buildGlassPillButton(
            onTap: _togglePureLyricsMode,
            icon: _isPureLyricsMode
                ? Icons.view_sidebar_rounded
                : Icons.fullscreen_rounded,
            label: _isPureLyricsMode ? '双栏舞台' : '纯享歌词',
            tooltip: _isPureLyricsMode
                ? '展开左侧封面舞台 (快捷键 L)'
                : '收起封面，纯享全屏歌词 (快捷键 L)',
            isActive: _isPureLyricsMode,
            activeColor: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),

          // 歌词对齐方式切换按钮
          Consumer(
            builder: (context, ref, _) {
              final alignment = ref.watch(lyricsAlignmentProvider);
              return _buildGlassIconButton(
                onTap: () =>
                    ref.read(lyricsAlignmentProvider.notifier).cycle(),
                icon: alignment.icon,
                tooltip: '歌词对齐: ${alignment.label} (快捷键 A)',
              );
            },
          ),
          const SizedBox(width: 8),

          // 歌词编辑器快捷入口
          _buildGlassIconButton(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LyricsEditorPage(),
                ),
              );
            },
            icon: Icons.edit_note_rounded,
            tooltip: '歌词编辑器 / 逐字打轴',
          ),
          const SizedBox(width: 8),

          // 更多选项入口（带投放或定时状态徽标）
          Consumer(
            builder: (context, ref, _) {
              final isCasting = ref.watch(
                castProvider.select((s) => s.isCasting),
              );
              final timerActive = ref.watch(
                sleepTimerProvider.select((s) => s.isActive),
              );
              final hasActiveState = isCasting || timerActive;

              return Badge(
                isLabelVisible: hasActiveState,
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
                child: _buildGlassIconButton(
                  onTap: () => _showMoreOptionsSheet(context, ref),
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多选项（投屏 / 睡眠定时）',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 右侧顶部：杂志级先锋排版歌曲头部（Editorial Header）
  Widget _buildEditorialHeader({
    required BuildContext context,
    required WidgetRef ref,
    required dynamic currentSong,
    required ThemeData theme,
    bool isCompact = false,
  }) {
    final lyrics = ref.watch(playerProvider.select((s) => s.lyrics));
    final alignment = ref.watch(lyricsAlignmentProvider);

    final hasWordSync = lyrics != null &&
        lyrics.lines.any((l) => l.words != null && l.words!.isNotEmpty);

    final String formatUpper =
        (currentSong?.format ?? '').toString().toUpperCase();
    final bool isLossless =
        formatUpper == 'FLAC' || formatUpper == 'WAV' || formatUpper == 'APE';

    final String albumName = (currentSong?.album ?? '').toString().trim();

    final crossAlign = alignment.crossAxisAlignment;
    final textAlign = alignment.textAlign;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: crossAlign,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 顶部声学规格与元数据徽章栏 (Eyebrow Badges)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (formatUpper.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isLossless
                        ? Colors.amber.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isLossless
                          ? Colors.amber.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.14),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isLossless ? 'HI-RES · $formatUpper' : formatUpper,
                    style: TextStyle(
                      color: isLossless ? Colors.amberAccent : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              if (hasWordSync)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 11,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '逐字流光歌词',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (albumName.isNotEmpty)
                Text(
                  '💿 $albumName',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          SizedBox(height: isCompact ? 4 : 8),

          // 2. 大字重先锋歌曲主标题
          Text(
            currentSong?.title ?? '未在播放',
            textAlign: textAlign,
            style: TextStyle(
              fontSize: isCompact ? 22 : (_isPureLyricsMode ? 34 : 30),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.4,
              height: 1.2,
            ),
            maxLines: isCompact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),

          // 3. 歌手名与快捷搜索歌词入口（搜索歌词按钮随无操作自动淡出并释放水平占位）
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Wrap(
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: switch (crossAlign) {
                CrossAxisAlignment.center => WrapAlignment.center,
                CrossAxisAlignment.end => WrapAlignment.end,
                _ => WrapAlignment.start,
              },
              children: [
                Text(
                  currentSong?.artist ?? '未知艺术家',
                  textAlign: textAlign,
                  style: TextStyle(
                    fontSize: isCompact ? 13.5 : 15.5,
                    color: Colors.white.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (currentSong != null &&
                    (currentSong.title as String).isNotEmpty)
                  IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: ClipRect(
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.centerLeft,
                        widthFactor: _controlsVisible ? 1.0 : 0.0,
                        heightFactor: 1.0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 240),
                          opacity: _controlsVisible ? 1.0 : 0.0,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: InkWell(
                              onTap: () => _showSearchLyricsOptions(
                                context,
                                currentSong.title,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_rounded,
                                      size: 12,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '搜索歌词',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 左侧下方：融合频谱进度条与声学控制舱（紧凑精致尺寸，常驻不自动隐藏）
  Widget _buildAcousticControlDeck({
    required BuildContext context,
    required WidgetRef ref,
    required bool isPlaying,
    required PlayMode playMode,
    required double volume,
    required ThemeData theme,
    bool isCompact = false,
  }) {
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final spectrum = ref.watch(playerProvider.select((s) => s.spectrum));
    final abLoopState = ref.watch(playerProvider.select((s) => s.abLoopState));
    final loopStart = ref.watch(playerProvider.select((s) => s.loopStart));
    final loopEnd = ref.watch(playerProvider.select((s) => s.loopEnd));
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 20),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 实时 64 柱音频频谱图
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 6),
              child: SizedBox(
                height: 28,
                width: double.infinity,
                child: SpectrumView(spectrum: spectrum, opacity: 0.8),
              ),
            ),

          // 2. 进度滑块 + A-B 复读高亮区间
          SizedBox(
            height: 24,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (abLoopState != ABLoopState.off &&
                        loopStart != null &&
                        duration.inMilliseconds > 0)
                      Positioned(
                        left: (loopStart.inMilliseconds /
                                duration.inMilliseconds) *
                            constraints.maxWidth,
                        right: loopEnd != null
                            ? (1 -
                                    loopEnd.inMilliseconds /
                                        duration.inMilliseconds) *
                                constraints.maxWidth
                            : 0,
                        top: 7,
                        bottom: 7,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5.5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 11,
                        ),
                        activeTrackColor: theme.colorScheme.primary,
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.14,
                        ),
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (value) {
                          final newPos = Duration(
                            milliseconds:
                                (value * duration.inMilliseconds).toInt(),
                          );
                          ref.read(playerProvider.notifier).seekTo(newPos);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 3. 时间刻度与 A-B 复读胶囊
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
                _buildABLoopButton(
                  ref,
                  abLoopState,
                  loopStart,
                  loopEnd,
                  theme,
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // 4. 核心播放控制阵列
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 播放模式切换
              IconButton(
                onPressed: () =>
                    ref.read(playerProvider.notifier).togglePlayMode(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                icon: Icon(
                  _getPlayModeIcon(playMode),
                  color: Colors.white70,
                  size: 21,
                ),
                tooltip: _getPlayModeLabel(playMode),
              ),
              // 上一首
              IconButton(
                onPressed: () => ref.read(playerProvider.notifier).previous(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 29,
                ),
                tooltip: '上一首',
              ),
              // 主播放/暂停发光圆钮
              Container(
                width: isCompact ? 46 : 52,
                height: isCompact ? 46 : 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.45),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      ref.read(playerProvider.notifier).togglePlayPause(),
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: isCompact ? 26 : 30,
                  ),
                  tooltip: isPlaying ? '暂停 (Space)' : '播放 (Space)',
                ),
              ),
              // 下一首
              IconButton(
                onPressed: () => ref.read(playerProvider.notifier).next(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 29,
                ),
                tooltip: '下一首',
              ),
              // 播放倍速按钮
              Consumer(
                builder: (context, ref, _) {
                  final speed = ref.watch(playbackSpeedProvider);
                  final isDefault = (speed - 1.0).abs() < 0.01;
                  return InkWell(
                    onTap: () => SpeedControlSheet.show(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDefault
                            ? Colors.white.withValues(alpha: 0.06)
                            : theme.colorScheme.primary.withValues(alpha: 0.22),
                        border: Border.all(
                          color: isDefault
                              ? Colors.white.withValues(alpha: 0.1)
                              : theme.colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 1 : 2)}x',
                        style: TextStyle(
                          color: isDefault
                              ? Colors.white70
                              : theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          // 5. 底部轻量级音量滑杆与状态提示
          if (!isCompact) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Icon(
                    volume <= 0.01
                        ? Icons.volume_off_rounded
                        : (volume < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded),
                    size: 17,
                    color: Colors.white38,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 4.5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        activeTrackColor: Colors.white54,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white70,
                      ),
                      child: Slider(
                        value: volume.clamp(0.0, 1.0),
                        onChanged: (v) =>
                            ref.read(playerProvider.notifier).setVolume(v),
                      ),
                    ),
                  ),
                  Text(
                    '${(volume * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 纯享全屏歌词模式下的底部悬浮胶囊控制栏
  Widget _buildFloatingPureModeDock({
    required BuildContext context,
    required WidgetRef ref,
    required bool isPlaying,
    required ThemeData theme,
  }) {
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));

    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => ref.read(playerProvider.notifier).previous(),
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white70,
                  size: 26,
                ),
                tooltip: '上一首',
              ),
              const SizedBox(width: 6),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
                child: IconButton(
                  onPressed: () =>
                      ref.read(playerProvider.notifier).togglePlayPause(),
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => ref.read(playerProvider.notifier).next(),
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white70,
                  size: 26,
                ),
                tooltip: '下一首',
              ),
              const SizedBox(width: 12),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 1,
                height: 18,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _togglePureLyricsMode,
                icon: const Icon(
                  Icons.fullscreen_exit_rounded,
                  color: Colors.white70,
                  size: 22,
                ),
                tooltip: '返回双栏视图 (快捷键 L)',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建毛玻璃胶囊按钮
  Widget _buildGlassPillButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    String? tooltip,
    bool isActive = false,
    Color? activeColor,
  }) {
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive && activeColor != null
              ? activeColor.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive && activeColor != null
                ? activeColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive && activeColor != null
                  ? activeColor
                  : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive && activeColor != null
                    ? Colors.white
                    : Colors.white70,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: child);
    }
    return child;
  }

  /// 构建圆形毛玻璃图标按钮
  Widget _buildGlassIconButton({
    required VoidCallback onTap,
    required IconData icon,
    String? tooltip,
  }) {
    final btn = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  /// 显示“更多选项”底部抽屉菜单
  void _showMoreOptionsSheet(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '更多选项',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 1. DLNA 投放选项
                Consumer(
                  builder: (context, ref, _) {
                    final isCasting = ref.watch(
                      castProvider.select((s) => s.isCasting),
                    );
                    final activeDevice = ref.watch(
                      castProvider.select((s) => s.activeDevice?.friendlyName),
                    );

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCasting
                              ? theme.colorScheme.primary.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isCasting
                              ? Icons.cast_connected_rounded
                              : Icons.cast_rounded,
                          color: isCasting
                              ? theme.colorScheme.primary
                              : Colors.white70,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        '投放到设备',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      subtitle: Text(
                        isCasting
                            ? '正在投放 (${activeDevice ?? '已连接'})'
                            : '将音乐投放到局域网电视或音箱',
                        style: TextStyle(
                          color: isCasting
                              ? theme.colorScheme.primary
                              : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white38,
                      ),
                      onTap: () {
                        Navigator.pop(modalContext);
                        showCastSheet(context);
                      },
                    );
                  },
                ),

                // 2. 睡前定时选项
                Consumer(
                  builder: (context, ref, _) {
                    final timer = ref.watch(sleepTimerProvider);

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: timer.isActive
                              ? theme.colorScheme.primary.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.bedtime_outlined,
                          color: timer.isActive
                              ? theme.colorScheme.primary
                              : Colors.white70,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        '睡前定时',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      subtitle: Text(
                        timer.isActive
                            ? '定时中 (倒计时 ${timer.remainingFormatted})'
                            : '开启定时停止播放',
                        style: TextStyle(
                          color: timer.isActive
                              ? theme.colorScheme.primary
                              : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white38,
                      ),
                      onTap: () {
                        Navigator.pop(modalContext);
                        SleepTimerSheet.show(context);
                      },
                    );
                  },
                ),

                // 3. 歌词编辑器选项
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: Colors.white70,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    '歌词编辑器',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  subtitle: const Text(
                    '编辑与打轴当前歌曲的 LRC 逐字歌词',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                  onTap: () {
                    Navigator.pop(modalContext);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LyricsEditorPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示搜索歌词渠道选项
  void _showSearchLyricsOptions(BuildContext context, String songTitle) {
    final encoded = Uri.encodeComponent(songTitle);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '搜索歌词',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language, color: Colors.white70),
                  title: const Text(
                    '酷歌词 - kugeci.com',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openUrl(
                      'https://www.kugeci.com/search?q=$encoded',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search, color: Colors.white70),
                  title: const Text(
                    '渠道1 - lrc.64h.cn',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openUrl(
                      'https://cn.bing.com/search?q=$encoded%20site%3Alrc.64h.cn',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search, color: Colors.white70),
                  title: const Text(
                    '渠道2 - music.163.com',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openUrl(
                      'https://cn.bing.com/search?q=$encoded%20site%3Amusic.163.com',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search, color: Colors.white70),
                  title: const Text(
                    '渠道3 - 1ting.com',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openUrl(
                      'https://cn.bing.com/search?q=$encoded%20site%3A1ting.com',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 使用默认浏览器打开URL
  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// A-B 复读循环按钮
  Widget _buildABLoopButton(
    WidgetRef ref,
    ABLoopState abLoopState,
    Duration? loopStart,
    Duration? loopEnd,
    ThemeData theme,
  ) {
    String label;
    Color color;
    switch (abLoopState) {
      case ABLoopState.off:
        label = 'A-B 复读';
        color = Colors.white38;
        break;
      case ABLoopState.setA:
        label = 'A: ${_formatDuration(loopStart ?? Duration.zero)}';
        color = theme.colorScheme.primary.withValues(alpha: 0.85);
        break;
      case ABLoopState.active:
        label =
            '${_formatDuration(loopStart ?? Duration.zero)} ↔ ${_formatDuration(loopEnd ?? Duration.zero)}';
        color = theme.colorScheme.primary;
        break;
    }

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).toggleABLoop(),
      onLongPress: () => ref.read(playerProvider.notifier).clearABLoop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: abLoopState == ABLoopState.active
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: abLoopState != ABLoopState.off
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: abLoopState != ABLoopState.off
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return Icons.repeat_rounded;
      case PlayMode.singleLoop:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  String _getPlayModeLabel(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.singleLoop:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

/// 具备 3D 鼠标视差倾斜（Parallax Tilt）与音频低频呼吸光晕的专辑封面舞台
class _InteractiveAlbumStage extends ConsumerStatefulWidget {
  final PlayerVisualStyle style;
  final bool isPlaying;
  final bool controlsVisible;
  final VoidCallback onTap;
  final double? maxStageSize;

  const _InteractiveAlbumStage({
    required this.style,
    required this.isPlaying,
    required this.controlsVisible,
    required this.onTap,
    this.maxStageSize,
  });

  @override
  ConsumerState<_InteractiveAlbumStage> createState() =>
      _InteractiveAlbumStageState();
}

class _InteractiveAlbumStageState
    extends ConsumerState<_InteractiveAlbumStage> {
  /// 归一化的鼠标偏移坐标 [-1.0, 1.0]，用于计算 3D 旋转与高光反射
  Offset _normalizedHover = Offset.zero;
  bool _isHovered = false;

  void _onHover(PointerHoverEvent event, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final dx = ((event.localPosition.dx / size.width) * 2.0 - 1.0).clamp(
      -1.0,
      1.0,
    );
    final dy = ((event.localPosition.dy / size.height) * 2.0 - 1.0).clamp(
      -1.0,
      1.0,
    );
    setState(() {
      _isHovered = true;
      _normalizedHover = Offset(dx, dy);
    });
  }

  void _onExit(PointerExitEvent event) {
    setState(() {
      _isHovered = false;
      _normalizedHover = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverData = ref.watch(playerProvider.select((s) => s.coverData));
    final spectrum = ref.watch(playerProvider.select((s) => s.spectrum));

    // 计算低频能量（0.0 ~ 1.0），驱动封面背后弥散光晕随节奏呼吸
    double bassPulse = 0.0;
    if (widget.isPlaying && spectrum.isNotEmpty) {
      final count = math.min(8, spectrum.length);
      double sum = 0;
      for (int i = 0; i < count; i++) {
        sum += spectrum[i];
      }
      bassPulse = (sum / count).clamp(0.0, 1.0);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortest = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        // 预留四周发光扩散余量，防止外发光触碰父级容器边界被裁切
        final stageSize =
            (widget.maxStageSize ?? (shortest * 0.82)).clamp(64.0, 290.0);

        return MouseRegion(
          cursor: widget.controlsVisible
              ? SystemMouseCursors.click
              : SystemMouseCursors.none,
          onHover: (e) => _onHover(e, Size(stageSize, stageSize)),
          onExit: _onExit,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: widget.isPlaying
                  ? (_isHovered ? 1.03 : 1.0)
                  : (_isHovered ? 0.96 : 0.92),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              child: TweenAnimationBuilder<Offset>(
                tween: Tween<Offset>(
                  begin: Offset.zero,
                  end: _normalizedHover,
                ),
                duration: Duration(milliseconds: _isHovered ? 90 : 380),
                curve: Curves.easeOutCubic,
                builder: (context, animOffset, child) {
                  final smoothMatrix = Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(-animOffset.dy * 0.16)
                    ..rotateY(animOffset.dx * 0.16);

                  return Transform(
                    alignment: Alignment.center,
                    transform: widget.maxStageSize != null
                        ? Matrix4.identity()
                        : smoothMatrix,
                    child: Hero(
                      tag: 'album_art',
                      child: widget.style == PlayerVisualStyle.vinyl
                          ? VinylDisc(
                              coverData: coverData,
                              isPlaying: widget.isPlaying,
                              size: stageSize * 0.95,
                            )
                          : Container(
                              width: stageSize,
                              height: stageSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  stageSize * 0.08,
                                ),
                                boxShadow: [
                                  // 1. 深色内收立体底影（置于底层，避免在彩色光晕上切出暗环）
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.42),
                                    blurRadius: 20,
                                    spreadRadius: -4,
                                    offset: const Offset(0, 10),
                                  ),
                                  // 2. 随音频低频能量呼吸的柔和弥散光晕（自然衰减不越界）
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: (0.20 + bassPulse * 0.22).clamp(
                                        0.12,
                                        0.48,
                                      ),
                                    ),
                                    blurRadius: 26 + bassPulse * 20,
                                    spreadRadius: 0,
                                    offset: Offset(
                                      -animOffset.dx * 6,
                                      4 - animOffset.dy * 6,
                                    ),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  stageSize * 0.08,
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    coverData != null
                                        ? Image.memory(
                                            Uint8List.fromList(coverData),
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                            errorBuilder: (_, _, _) =>
                                                _buildDefaultCover(
                                                  theme,
                                                  stageSize,
                                                ),
                                          )
                                        : _buildDefaultCover(theme, stageSize),

                                    // 鼠标 3D 视差动态高光反光层 (Specular Glare)
                                    if (_isHovered &&
                                        widget.maxStageSize == null)
                                      IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment(
                                                -animOffset.dx,
                                                -animOffset.dy,
                                              ),
                                              end: Alignment(
                                                animOffset.dx,
                                                animOffset.dy,
                                              ),
                                              colors: [
                                                Colors.white.withValues(
                                                  alpha: 0.16,
                                                ),
                                                Colors.transparent,
                                                Colors.black.withValues(
                                                  alpha: 0.12,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                    // 细微高光内描边
                                    IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            stageSize * 0.08,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.14,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultCover(ThemeData theme, double size) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.55),
            theme.colorScheme.tertiary.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Icon(
        Icons.album_rounded,
        size: size * 0.42,
        color: Colors.white24,
      ),
    );
  }
}
