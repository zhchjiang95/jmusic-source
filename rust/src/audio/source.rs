use std::fs::File;
use std::time::Duration;

use rodio::Source;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{Decoder, DecoderOptions};
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::Time;

/// 基于 symphonia 的可 seek 音频源，支持所有格式的高效跳转
pub struct SeekableSource {
    reader: Box<dyn FormatReader>,
    decoder: Box<dyn Decoder>,
    track_id: u32,
    sample_rate: u32,
    channels: u16,
    /// 当前解码帧的采样缓冲
    samples: Vec<i16>,
    /// 当前读取位置
    pos: usize,
}

impl SeekableSource {
    /// 从文件路径创建音频源
    pub fn new(file_path: &str) -> Result<Self, String> {
        let file = File::open(file_path)
            .map_err(|e| format!("无法打开文件 {}: {}", file_path, e))?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(ext) = std::path::Path::new(file_path).extension() {
            hint.with_extension(&ext.to_string_lossy());
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
            .map_err(|e| format!("无法探测格式: {}", e))?;

        let reader = probed.format;
        let track = reader
            .default_track()
            .ok_or("未找到音轨".to_string())?;
        let track_id = track.id;
        let codec_params = track.codec_params.clone();
        let sample_rate = codec_params.sample_rate.ok_or("未知采样率")?;
        let channels = codec_params
            .channels
            .map(|c| c.count() as u16)
            .ok_or("未知声道数")?;

        let decoder = symphonia::default::get_codecs()
            .make(&codec_params, &DecoderOptions::default())
            .map_err(|e| format!("无法创建解码器: {}", e))?;

        Ok(Self {
            reader,
            decoder,
            track_id,
            sample_rate,
            channels,
            samples: Vec::new(),
            pos: 0,
        })
    }

    /// 跳转到指定秒数（容器级高效 seek）
    pub fn seek(&mut self, position_secs: f64) -> Result<(), String> {
        let seconds = position_secs as u64;
        let frac = position_secs.fract();

        self.reader
            .seek(
                SeekMode::Coarse,
                SeekTo::Time {
                    time: Time { seconds, frac },
                    track_id: Some(self.track_id),
                },
            )
            .map_err(|e| format!("seek 失败: {}", e))?;

        // 重置解码器状态
        self.decoder.reset();
        self.samples.clear();
        self.pos = 0;
        Ok(())
    }

    /// 解码下一个数据包，填充采样缓冲
    fn decode_next_packet(&mut self) -> bool {
        loop {
            let packet = match self.reader.next_packet() {
                Ok(p) => p,
                Err(_) => return false,
            };

            // 跳过其他音轨的包
            if packet.track_id() != self.track_id {
                continue;
            }

            match self.decoder.decode(&packet) {
                Ok(decoded) => {
                    let spec = *decoded.spec();
                    let num_samples = decoded.capacity();
                    let mut buf = SampleBuffer::<i16>::new(num_samples as u64, spec);
                    buf.copy_interleaved_ref(decoded);
                    self.samples = buf.samples().to_vec();
                    self.pos = 0;
                    return true;
                }
                // 解码错误则跳过该包继续
                Err(_) => continue,
            }
        }
    }
}

impl Iterator for SeekableSource {
    type Item = i16;

    fn next(&mut self) -> Option<i16> {
        // 当前帧已消耗完，解码下一帧
        if self.pos >= self.samples.len() {
            if !self.decode_next_packet() {
                return None;
            }
        }
        let sample = self.samples[self.pos];
        self.pos += 1;
        Some(sample)
    }
}

impl Source for SeekableSource {
    fn current_frame_len(&self) -> Option<usize> {
        if self.samples.is_empty() {
            None
        } else {
            Some(self.samples.len() - self.pos)
        }
    }

    fn channels(&self) -> u16 {
        self.channels
    }

    fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    fn total_duration(&self) -> Option<Duration> {
        None
    }
}
