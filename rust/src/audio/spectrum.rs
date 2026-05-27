//! 音频频谱分析模块
//!
//! 从音频线程无分配地采集 PCM 样本，通过独立 worker 线程执行 FFT，
//! 产出 64 个对数分箱的归一化频谱帧，供 FFI 层读取。

use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use arc_swap::ArcSwap;
use parking_lot::{Mutex, RwLock};
use realfft::num_complex::Complex32;
use realfft::{RealFftPlanner, RealToComplex};

// ─── 常量 ───────────────────────────────────────────────────────────────────

/// FFT 窗口大小（采样点数）
pub const FFT_SIZE: usize = 2048;

/// 环形缓冲区容量（FFT_SIZE 的两倍，保证随时可读最近一窗）
pub const RING_CAPACITY: usize = FFT_SIZE * 2;

/// 输出频谱的 bin 数量
pub const NUM_BINS: usize = 64;

/// 频谱覆盖的最低频率 (Hz)
pub const FREQ_LOW_HZ: f32 = 20.0;

/// 频谱覆盖的最高频率 (Hz)
pub const FREQ_HIGH_HZ: f32 = 16_000.0;

/// Worker 线程 tick 间隔 (ms)
pub const TICK_MS: u64 = 50;

/// 平滑系数 — 上升（attack）
pub const ATTACK: f32 = 0.30;

/// 平滑系数 — 下降（release）
pub const RELEASE: f32 = 0.10;

/// dB 下限
pub const DB_FLOOR: f32 = -80.0;

/// dB 上限
pub const DB_CEIL: f32 = 0.0;

// ─── FFT 工作区 ─────────────────────────────────────────────────────────────

struct FftScratch {
    fft: Arc<dyn RealToComplex<f32>>,
    window: [f32; FFT_SIZE],
    input: Vec<f32>,
    spectrum: Vec<Complex32>,
    smoothed: [f32; NUM_BINS],
}

// ─── 频谱分析器 ─────────────────────────────────────────────────────────────

/// 频谱分析器：拥有环形缓冲、FFT 计划、平滑状态和最新帧缓存。
pub struct SpectrumAnalyzer {
    /// 环形缓冲区（预分配，永不重新分配）
    ring: Box<[f32; RING_CAPACITY]>,
    /// 写入头（单调递增，取模 RING_CAPACITY 得到实际索引）
    head: AtomicUsize,
    /// 已写入的总样本数（用于判断缓冲区是否已填满一窗）
    total_written: AtomicUsize,
    /// 当前音源采样率
    sample_rate: AtomicUsize,
    /// 是否暂停
    paused: AtomicBool,
    /// 是否已产出过至少一帧
    has_frame: AtomicBool,

    /// FFT 工作区（仅 worker 线程使用，音频线程永远不碰）
    scratch: Mutex<FftScratch>,

    /// 最新的 64-bin 频谱帧（归一化 0..1，已平滑）
    latest: ArcSwap<Vec<f32>>,

    /// 对数分箱边界（采样率变化时重新计算）
    bin_edges: RwLock<[f32; NUM_BINS + 1]>,
}

// Safety: SpectrumAnalyzer 的所有可变状态都通过原子操作或锁保护
unsafe impl Send for SpectrumAnalyzer {}
unsafe impl Sync for SpectrumAnalyzer {}

impl SpectrumAnalyzer {
    /// 创建新的频谱分析器（一次性分配所有缓冲区）
    pub fn new() -> Arc<Self> {
        // 预计算 Hann 窗
        let mut window = [0.0f32; FFT_SIZE];
        for i in 0..FFT_SIZE {
            window[i] =
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / (FFT_SIZE - 1) as f32).cos());
        }

        // 构建 FFT 计划
        let mut planner = RealFftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FFT_SIZE);
        let spectrum_len = FFT_SIZE / 2 + 1;

        let scratch = FftScratch {
            fft,
            window,
            input: vec![0.0; FFT_SIZE],
            spectrum: vec![Complex32::new(0.0, 0.0); spectrum_len],
            smoothed: [0.0; NUM_BINS],
        };

        // 计算默认采样率下的 bin 边界
        let bin_edges = compute_bin_edges(44_100);

        Arc::new(Self {
            ring: Box::new([0.0f32; RING_CAPACITY]),
            head: AtomicUsize::new(0),
            total_written: AtomicUsize::new(0),
            sample_rate: AtomicUsize::new(44_100),
            paused: AtomicBool::new(true),
            has_frame: AtomicBool::new(false),
            scratch: Mutex::new(scratch),
            latest: ArcSwap::from_pointee(vec![0.0; NUM_BINS]),
            bin_edges: RwLock::new(bin_edges),
        })
    }

    /// 音频线程调用：将交错的 i16 PCM 样本推入环形缓冲区。
    ///
    /// **零分配**：不做任何堆分配，不获取任何互斥锁。
    #[inline]
    pub fn push_interleaved_i16(&self, samples: &[i16], channels: u16) {
        if samples.is_empty() {
            return;
        }

        let ch = channels.max(1) as usize;
        let frame_count = samples.len() / ch;

        // 获取当前写入位置
        let mut head = self.head.load(Ordering::Relaxed);

        // 逐帧混合为单声道并写入环形缓冲
        // Safety: 我们是唯一的写入者（音频线程），ring 是预分配的固定大小数组
        let ring_ptr = self.ring.as_ptr() as *mut f32;

        for frame_idx in 0..frame_count {
            // 混合为单声道
            let mut sum: f32 = 0.0;
            let base = frame_idx * ch;
            for c in 0..ch {
                if base + c < samples.len() {
                    sum += samples[base + c] as f32;
                }
            }
            let mono = sum / (ch as f32 * 32768.0);

            // 写入环形缓冲
            let idx = head % RING_CAPACITY;
            unsafe {
                *ring_ptr.add(idx) = mono;
            }
            head = head.wrapping_add(1);
        }

        // 更新 head（Release 保证 worker 能看到写入的数据）
        self.head.store(head, Ordering::Release);
        self.total_written
            .fetch_add(frame_count, Ordering::Relaxed);
    }

    /// 设置新的采样率（当音源切换时调用）
    pub fn set_sample_rate(&self, sr: u32) {
        self.sample_rate.store(sr as usize, Ordering::Release);
        let edges = compute_bin_edges(sr);
        *self.bin_edges.write() = edges;
    }

    /// 设置暂停状态
    pub fn set_paused(&self, paused: bool) {
        self.paused.store(paused, Ordering::Release);
    }

    /// 清除帧标记（停止播放时调用，使 FFI 返回 None 直到新曲目开始）
    pub fn clear_frame(&self) {
        self.has_frame.store(false, Ordering::Release);
        // 同时清零 smoothed 状态
        if let Some(mut scratch) = self.scratch.try_lock() {
            scratch.smoothed = [0.0; NUM_BINS];
        }
        self.latest.store(Arc::new(vec![0.0; NUM_BINS]));
    }

    /// Worker 线程的 tick：从环形缓冲读取最新窗口，执行 FFT，更新频谱帧。
    pub fn tick(&self) {
        // 暂停时发布全零帧
        if self.paused.load(Ordering::Acquire) {
            let zeros = vec![0.0f32; NUM_BINS];
            self.latest.store(Arc::new(zeros));
            if self.has_frame.load(Ordering::Relaxed) {
                // 保持 has_frame = true 以便 FFI 返回零帧而非 None
            }
            return;
        }

        let mut scratch = self.scratch.lock();

        // 从环形缓冲读取最近 FFT_SIZE 个样本
        let head = self.head.load(Ordering::Acquire);
        let total = self.total_written.load(Ordering::Relaxed);
        let available = total.min(FFT_SIZE);

        if available == 0 {
            return;
        }

        // 零填充不足的部分（从前面填零）
        let zero_pad = FFT_SIZE - available;
        for i in 0..zero_pad {
            scratch.input[i] = 0.0;
        }

        // 从环形缓冲复制最近的 available 个样本
        let start = if head >= available {
            head - available
        } else {
            // head 已经 wrap 过
            head.wrapping_sub(available)
        };

        for i in 0..available {
            let idx = (start.wrapping_add(i)) % RING_CAPACITY;
            scratch.input[zero_pad + i] = self.ring[idx];
        }

        // 应用 Hann 窗
        for i in 0..FFT_SIZE {
            scratch.input[i] *= scratch.window[i];
        }

        // 执行 FFT（需要分离借用 input 和 spectrum）
        {
            let FftScratch {
                ref fft,
                ref mut input,
                ref mut spectrum,
                ..
            } = *scratch;
            if fft.process(input, spectrum).is_err() {
                return;
            }
        }

        // 计算幅度
        let sr = self.sample_rate.load(Ordering::Relaxed) as f32;
        let bin_edges = self.bin_edges.read();

        let mut output = [0.0f32; NUM_BINS];

        for b in 0..NUM_BINS {
            let freq_lo = bin_edges[b];
            let freq_hi = bin_edges[b + 1];

            // 将频率转换为 FFT bin 索引
            let fft_bin_lo = (freq_lo * FFT_SIZE as f32 / sr).floor() as usize;
            let fft_bin_hi = (freq_hi * FFT_SIZE as f32 / sr).ceil() as usize;

            let fft_bin_lo = fft_bin_lo.max(1); // 跳过 DC
            let fft_bin_hi = fft_bin_hi.min(scratch.spectrum.len() - 1);

            if fft_bin_lo > fft_bin_hi {
                // 范围为空，取最近的单个 bin
                let nearest = ((freq_lo + freq_hi) * 0.5 * FFT_SIZE as f32 / sr)
                    .round() as usize;
                let nearest = nearest.clamp(1, scratch.spectrum.len() - 1);
                let c = scratch.spectrum[nearest];
                output[b] = (c.re * c.re + c.im * c.im).sqrt();
            } else {
                let mut sum = 0.0f32;
                let count = (fft_bin_hi - fft_bin_lo + 1) as f32;
                for k in fft_bin_lo..=fft_bin_hi {
                    let c = scratch.spectrum[k];
                    sum += (c.re * c.re + c.im * c.im).sqrt();
                }
                // 取平均而非求和，避免高频 bin（包含更多 FFT bin）被过度放大
                output[b] = sum / count;
            }
        }

        // dB 压缩 + 归一化
        // realfft 输出未除以 FFT_SIZE，需要先归一化幅度
        let fft_norm = 2.0 / FFT_SIZE as f32;
        for b in 0..NUM_BINS {
            let normalized_mag = output[b] * fft_norm;
            let db = 20.0 * (normalized_mag + 1e-9).log10();
            let db = db.clamp(DB_FLOOR, DB_CEIL);
            output[b] = (db - DB_FLOOR) / (DB_CEIL - DB_FLOOR);
        }

        // 非对称 IIR 平滑
        for b in 0..NUM_BINS {
            let target = output[b];
            let current = scratch.smoothed[b];
            if target > current {
                scratch.smoothed[b] = current + ATTACK * (target - current);
            } else {
                scratch.smoothed[b] = current + RELEASE * (target - current);
            }
        }

        // 发布帧
        let frame: Vec<f32> = scratch.smoothed.to_vec();
        self.latest.store(Arc::new(frame));
        self.has_frame.store(true, Ordering::Release);
    }

    /// 获取最新频谱快照（FFI 调用，极低开销）
    pub fn snapshot(&self) -> Option<Vec<f32>> {
        if !self.has_frame.load(Ordering::Acquire) {
            return None;
        }
        Some((**self.latest.load()).clone())
    }
}

// ─── Worker 线程 ─────────────────────────────────────────────────────────────

/// 启动频谱 worker 线程，返回 JoinHandle。
pub fn spawn_worker(
    analyzer: Arc<SpectrumAnalyzer>,
    shutdown: Arc<AtomicBool>,
) -> thread::JoinHandle<()> {
    thread::Builder::new()
        .name("spectrum-worker".into())
        .spawn(move || {
            while !shutdown.load(Ordering::Acquire) {
                // catch_unwind 防止 panic 杀死线程
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    analyzer.tick();
                }));

                if result.is_err() {
                    log::error!("spectrum worker tick panicked, recovering...");
                    thread::sleep(Duration::from_millis(250));
                }

                thread::sleep(Duration::from_millis(TICK_MS));
            }
        })
        .expect("failed to spawn spectrum worker thread")
}

// ─── 辅助函数 ────────────────────────────────────────────────────────────────

/// 计算 64+1 个对数分布的频率边界
fn compute_bin_edges(sample_rate: u32) -> [f32; NUM_BINS + 1] {
    let _ = sample_rate; // 边界只依赖于 FREQ_LOW/HIGH，与采样率无关
    let mut edges = [0.0f32; NUM_BINS + 1];
    let ratio = FREQ_HIGH_HZ / FREQ_LOW_HZ;
    for i in 0..=NUM_BINS {
        edges[i] = FREQ_LOW_HZ * ratio.powf(i as f32 / NUM_BINS as f32);
    }
    edges
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_creates_valid_analyzer() {
        let analyzer = SpectrumAnalyzer::new();
        assert!(analyzer.snapshot().is_none());
    }

    #[test]
    fn test_push_and_tick_produces_frame() {
        let analyzer = SpectrumAnalyzer::new();
        analyzer.set_paused(false);

        // 生成一个 1kHz 正弦波（44100 Hz 采样率）
        let sr = 44100.0f32;
        let freq = 1000.0f32;
        let num_samples = 4096;
        let samples: Vec<i16> = (0..num_samples)
            .map(|i| {
                let t = i as f32 / sr;
                (0.8 * (2.0 * std::f32::consts::PI * freq * t).sin() * 32767.0) as i16
            })
            .collect();

        analyzer.push_interleaved_i16(&samples, 1);
        analyzer.tick();

        let frame = analyzer.snapshot();
        assert!(frame.is_some());
        let frame = frame.unwrap();
        assert_eq!(frame.len(), NUM_BINS);

        // 所有值应在 [0, 1] 范围内
        for &v in &frame {
            assert!(v >= 0.0 && v <= 1.0, "value out of range: {}", v);
        }

        // 1kHz 应该在某个 bin 有明显能量
        let max_bin = frame
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .unwrap()
            .0;
        // 1kHz 在 64 个对数 bin 中大约在 bin 35-42 附近
        assert!(
            max_bin >= 33 && max_bin <= 45,
            "1kHz peak at unexpected bin: {}",
            max_bin
        );
    }

    #[test]
    fn test_paused_returns_zeros() {
        let analyzer = SpectrumAnalyzer::new();
        analyzer.set_paused(false);

        // 先推一些数据产生帧
        let samples: Vec<i16> = (0..4096).map(|i| (i % 1000) as i16).collect();
        analyzer.push_interleaved_i16(&samples, 1);
        analyzer.tick();
        assert!(analyzer.snapshot().is_some());

        // 暂停后 tick 应产生全零帧
        analyzer.set_paused(true);
        analyzer.tick();
        let frame = analyzer.snapshot().unwrap();
        assert!(frame.iter().all(|&v| v == 0.0));
    }

    #[test]
    fn test_snapshot_idempotent() {
        let analyzer = SpectrumAnalyzer::new();
        analyzer.set_paused(false);

        let samples: Vec<i16> = (0..4096).map(|i| (i % 500) as i16).collect();
        analyzer.push_interleaved_i16(&samples, 1);
        analyzer.tick();

        let s1 = analyzer.snapshot().unwrap();
        let s2 = analyzer.snapshot().unwrap();
        let s3 = analyzer.snapshot().unwrap();
        assert_eq!(s1, s2);
        assert_eq!(s2, s3);
    }

    #[test]
    fn test_clear_frame_returns_none() {
        let analyzer = SpectrumAnalyzer::new();
        analyzer.set_paused(false);

        let samples: Vec<i16> = (0..4096).map(|i| (i % 500) as i16).collect();
        analyzer.push_interleaved_i16(&samples, 1);
        analyzer.tick();
        assert!(analyzer.snapshot().is_some());

        analyzer.clear_frame();
        assert!(analyzer.snapshot().is_none());
    }

    #[test]
    fn test_stereo_push() {
        let analyzer = SpectrumAnalyzer::new();
        analyzer.set_paused(false);

        // 立体声：L=正弦, R=正弦（交错）
        let sr = 44100.0f32;
        let freq = 440.0f32;
        let num_frames = 4096;
        let mut samples: Vec<i16> = Vec::with_capacity(num_frames * 2);
        for i in 0..num_frames {
            let t = i as f32 / sr;
            let s = (0.7 * (2.0 * std::f32::consts::PI * freq * t).sin() * 32767.0) as i16;
            samples.push(s); // L
            samples.push(s); // R
        }

        analyzer.push_interleaved_i16(&samples, 2);
        analyzer.tick();

        let frame = analyzer.snapshot().unwrap();
        assert_eq!(frame.len(), NUM_BINS);
        // 应该有能量
        assert!(frame.iter().any(|&v| v > 0.0));
    }
}
