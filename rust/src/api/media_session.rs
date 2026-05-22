//! 系统媒体会话 API（供 Flutter 端调用）
//!
//! 提供初始化、更新元数据、更新播放状态、轮询事件等接口。

use crate::audio::media_controls;

/// 媒体控制事件（传递给 Flutter 端）
/// 
/// action 字段取值：
/// - "play" / "pause" / "toggle" / "next" / "previous" / "stop" / "seek"
/// 
/// 当 action 为 "seek" 时，position_secs 表示目标位置（秒）
pub struct MediaControlEvent {
    pub action: String,
    pub position_secs: f64,
}

/// 初始化系统媒体会话
/// 
/// Windows 平台需要传入窗口句柄（HWND 转为 i64），macOS 传 0 即可。
/// Android 端此函数为空操作（由原生层处理）。
#[flutter_rust_bridge::frb(sync)]
pub fn media_session_init(hwnd: i64) -> Result<(), String> {
    media_controls::init_media_controls(hwnd)
}

/// 更新当前播放歌曲的元数据
#[flutter_rust_bridge::frb(sync)]
pub fn media_session_update_metadata(
    title: String,
    artist: String,
    album: String,
    duration_secs: f64,
) {
    media_controls::update_media_metadata(&title, &artist, &album, duration_secs);
}

/// 更新播放状态（播放中/暂停）
#[flutter_rust_bridge::frb(sync)]
pub fn media_session_update_playback(is_playing: bool, position_secs: f64) {
    media_controls::update_media_playback(is_playing, position_secs);
}

/// 设置播放状态为停止
#[flutter_rust_bridge::frb(sync)]
pub fn media_session_update_stopped() {
    media_controls::update_media_stopped();
}

/// 轮询系统媒体控制事件
/// 
/// 返回 None 表示没有新事件。Flutter 端应定期调用此函数来获取系统媒体键事件。
#[flutter_rust_bridge::frb(sync)]
pub fn media_session_poll_event() -> Option<MediaControlEvent> {
    media_controls::poll_media_event().map(|evt| match evt {
        media_controls::MediaEvent::Play => MediaControlEvent {
            action: "play".to_string(),
            position_secs: 0.0,
        },
        media_controls::MediaEvent::Pause => MediaControlEvent {
            action: "pause".to_string(),
            position_secs: 0.0,
        },
        media_controls::MediaEvent::Toggle => MediaControlEvent {
            action: "toggle".to_string(),
            position_secs: 0.0,
        },
        media_controls::MediaEvent::Next => MediaControlEvent {
            action: "next".to_string(),
            position_secs: 0.0,
        },
        media_controls::MediaEvent::Previous => MediaControlEvent {
            action: "previous".to_string(),
            position_secs: 0.0,
        },
        media_controls::MediaEvent::Stop => MediaControlEvent {
            action: "stop".to_string(),
            position_secs: 0.0,
        },
        media_controls::MediaEvent::SeekTo(secs) => MediaControlEvent {
            action: "seek".to_string(),
            position_secs: secs,
        },
    })
}
