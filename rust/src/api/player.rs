use std::sync::{LazyLock, Mutex};

use crate::audio::engine::AudioEngine;

/// 全局音频引擎实例
static AUDIO_ENGINE: LazyLock<Mutex<Option<AudioEngine>>> = LazyLock::new(|| Mutex::new(None));

/// 当前播放文件路径
static CURRENT_FILE: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));

/// 初始化音频引擎
#[flutter_rust_bridge::frb(sync)]
pub fn player_init() -> Result<(), String> {
    let engine = AudioEngine::new()?;
    *AUDIO_ENGINE.lock().unwrap() = Some(engine);
    Ok(())
}

/// 播放指定文件
#[flutter_rust_bridge::frb(sync)]
pub fn player_play(file_path: String) -> Result<(), String> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    let engine = guard.as_ref().ok_or("音频引擎未初始化")?;
    engine.play(&file_path)?;
    *CURRENT_FILE.lock().unwrap() = Some(file_path);
    Ok(())
}

/// 暂停播放
#[flutter_rust_bridge::frb(sync)]
pub fn player_pause() -> Result<(), String> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    let engine = guard.as_ref().ok_or("音频引擎未初始化")?;
    engine.pause();
    Ok(())
}

/// 恢复播放
#[flutter_rust_bridge::frb(sync)]
pub fn player_resume() -> Result<(), String> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    let engine = guard.as_ref().ok_or("音频引擎未初始化")?;
    engine.resume();
    Ok(())
}

/// 停止播放
#[flutter_rust_bridge::frb(sync)]
pub fn player_stop() -> Result<(), String> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    let engine = guard.as_ref().ok_or("音频引擎未初始化")?;
    engine.stop();
    *CURRENT_FILE.lock().unwrap() = None;
    Ok(())
}

/// 跳转到指定位置（秒）
#[flutter_rust_bridge::frb(sync)]
pub fn player_seek(position_secs: f64) -> Result<(), String> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    let engine = guard.as_ref().ok_or("音频引擎未初始化")?;
    engine.seek(position_secs)
}

/// 设置音量（0.0 ~ 1.0）
#[flutter_rust_bridge::frb(sync)]
pub fn player_set_volume(volume: f32) -> Result<(), String> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    let engine = guard.as_ref().ok_or("音频引擎未初始化")?;
    engine.set_volume(volume);
    Ok(())
}

/// 获取当前音量
#[flutter_rust_bridge::frb(sync)]
pub fn player_get_volume() -> f32 {
    let guard = AUDIO_ENGINE.lock().unwrap();
    guard.as_ref().map(|e| e.get_volume()).unwrap_or(1.0)
}

/// 检查是否播放完毕
#[flutter_rust_bridge::frb(sync)]
pub fn player_is_finished() -> bool {
    let guard = AUDIO_ENGINE.lock().unwrap();
    guard.as_ref().map(|e| e.is_finished()).unwrap_or(true)
}

/// 获取当前播放文件路径
#[flutter_rust_bridge::frb(sync)]
pub fn player_get_current_file() -> Option<String> {
    CURRENT_FILE.lock().unwrap().clone()
}

/// 获取最新的 64-bin 频谱帧（归一化 0.0~1.0），无帧时返回 None
#[flutter_rust_bridge::frb(sync)]
pub fn player_get_spectrum() -> Option<Vec<f32>> {
    let guard = AUDIO_ENGINE.lock().unwrap();
    guard.as_ref().and_then(|e| e.analyzer().snapshot())
}
