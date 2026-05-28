/// 频谱可视化常量与辅助工具
library;

/// 频谱 bin 数量
const int kSpectrumBins = 64;

/// 频谱轮询间隔
const Duration kSpectrumPollInterval = Duration(milliseconds: 50);

/// 生成全零频谱列表
List<double> emptySpectrum() => List<double>.filled(kSpectrumBins, 0.0);
