/// 频谱可视化样式枚举与辅助工具
library;

/// 频谱可视化样式
enum SpectrumStyle {
  /// 64 条垂直柱状
  bars,

  /// 64 段环形径向
  ring,
}

/// SpectrumStyle 扩展方法
extension SpectrumStyleX on SpectrumStyle {
  /// 持久化用的字符串值
  String get prefValue => name;

  /// 从 SharedPreferences 字符串解析
  static SpectrumStyle fromPref(String? v) =>
      v == 'ring' ? SpectrumStyle.ring : SpectrumStyle.bars;

  /// 切换到下一个样式
  SpectrumStyle next() =>
      this == SpectrumStyle.bars ? SpectrumStyle.ring : SpectrumStyle.bars;
}

/// SharedPreferences 键名
const String kSpectrumStylePrefKey = 'spectrum_style';

/// 频谱 bin 数量
const int kSpectrumBins = 64;

/// 频谱轮询间隔
const Duration kSpectrumPollInterval = Duration(milliseconds: 50);

/// 生成全零频谱列表
List<double> emptySpectrum() => List<double>.filled(kSpectrumBins, 0.0);
