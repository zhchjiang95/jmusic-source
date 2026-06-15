#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

/// 设置应用数据目录（Android 上需要从 Dart 端传入）
#[flutter_rust_bridge::frb(sync)]
pub fn set_app_data_dir(path: String) {
    crate::storage::set_data_dir(path);
}

// 私有辅助函数：解码音频文件至内存 PCM i16 交错样本
use std::fs::File;
use std::io::Write;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use flacenc::error::Verify;
use flacenc::component::BitRepr;

fn decode_to_pcm(file_path: &str) -> Result<(Vec<i16>, u32, u16), String> {
    let file = File::open(file_path)
        .map_err(|e| format!("无法打开源文件: {}", e))?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = std::path::Path::new(file_path).extension() {
        hint.with_extension(&ext.to_string_lossy());
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| format!("无法探测音频格式: {}", e))?;

    let mut reader = probed.format;
    let track = reader
        .default_track()
        .ok_or_else(|| "未找到有效音轨".to_string())?;
    let track_id = track.id;
    let codec_params = track.codec_params.clone();
    let sample_rate = codec_params.sample_rate.ok_or("无法获取采样率")?;
    let channels = codec_params
        .channels
        .map(|c| c.count() as u16)
        .ok_or("无法获取声道数")?;

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .map_err(|e| format!("无法创建音频解码器: {}", e))?;

    let mut all_samples = Vec::new();

    loop {
        let packet = match reader.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                break;
            }
            Err(e) => {
                if !all_samples.is_empty() {
                    break;
                }
                return Err(format!("读取音频数据包失败: {}", e));
            }
        };

        if packet.track_id() != track_id {
            continue;
        }

        match decoder.decode(&packet) {
            Ok(decoded) => {
                let spec = *decoded.spec();
                let num_samples = decoded.capacity();
                let mut buf = SampleBuffer::<i16>::new(num_samples as u64, spec);
                buf.copy_interleaved_ref(decoded);
                all_samples.extend_from_slice(buf.samples());
            }
            Err(symphonia::core::errors::Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                break;
            }
            Err(symphonia::core::errors::Error::DecodeError(_)) => {
                continue;
            }
            Err(e) => return Err(format!("解码音频数据帧失败: {}", e)),
        }
    }

    Ok((all_samples, sample_rate, channels))
}

/// 音频转码导出函数，支持转换为 MP3, FLAC, WAV
pub fn convert_audio(
    input_path: String,
    output_path: String,
    target_format: String,
) -> Result<(), String> {
    // 1. 解码输入音频文件至内存 PCM
    let (samples, sample_rate, channels) = decode_to_pcm(&input_path)?;

    // 2. 根据目标格式类型进行对应编码
    let format = target_format.to_lowercase();
    match format.as_str() {
        "wav" => {
            let spec = hound::WavSpec {
                channels,
                sample_rate,
                bits_per_sample: 16,
                sample_format: hound::SampleFormat::Int,
            };
            let mut writer = hound::WavWriter::create(&output_path, spec)
                .map_err(|e| format!("无法创建 WAV 写入器: {}", e))?;
            for &sample in &samples {
                writer.write_sample(sample).map_err(|e| format!("写入 WAV 采样点失败: {}", e))?;
            }
            writer.finalize().map_err(|e| format!("完成 WAV 写入失败: {}", e))?;
        }
        "flac" => {
            let samples_i32: Vec<i32> = samples.iter().map(|&s| s as i32).collect();
            let config = flacenc::config::Encoder::default()
                .into_verified()
                .map_err(|_| "FLAC 编码配置初始化失败".to_string())?;
            let source = flacenc::source::MemSource::from_samples(
                &samples_i32,
                channels as usize,
                16,
                sample_rate as usize,
            );
            let flac_stream = flacenc::encode_with_fixed_block_size(&config, source, config.block_size)
                .map_err(|e| format!("FLAC 格式编码失败: {:?}", e))?;
            let mut sink = flacenc::bitsink::ByteSink::new();
            let _ = flac_stream.write(&mut sink);
            std::fs::write(&output_path, sink.as_slice())
                .map_err(|e| format!("无法保存 FLAC 文件: {}", e))?;
        }
        "mp3" => {
            let config = shine_rs::Mp3EncoderConfig::new()
                .sample_rate(sample_rate)
                .bitrate(192)
                .channels(channels as u8)
                .stereo_mode(if channels == 1 {
                    shine_rs::StereoMode::Mono
                } else {
                    shine_rs::StereoMode::Stereo
                });
            let mut encoder = shine_rs::Mp3Encoder::new(config)
                .map_err(|e| format!("创建 MP3 编码器失败: {:?}", e))?;

            let mut output_file = File::create(&output_path)
                .map_err(|e| format!("无法创建 MP3 输出文件: {}", e))?;

            let chunk_size = encoder.samples_per_frame() * (channels as usize);
            for chunk in samples.chunks(chunk_size) {
                let mp3_data = if chunk.len() < chunk_size {
                    let mut padded = chunk.to_vec();
                    padded.resize(chunk_size, 0);
                    encoder.encode_interleaved(&padded)
                } else {
                    encoder.encode_interleaved(chunk)
                };
                let mp3_data = mp3_data.map_err(|e| format!("MP3 格式编码失败: {:?}", e))?;
                for frame in &mp3_data {
                    output_file.write_all(frame)
                        .map_err(|e| format!("写入 MP3 数据段失败: {}", e))?;
                }
            }

            let final_data = encoder.finish().map_err(|e| format!("结束 MP3 格式编码失败: {:?}", e))?;
            output_file.write_all(&final_data)
                .map_err(|e| format!("写入 MP3 尾部信息失败: {}", e))?;
        }
        _ => return Err(format!("不受支持的音频目标格式: {}", target_format)),
    }

    Ok(())
}


