//! 系统媒体控制集成（Windows SMTC / macOS Now Playing）
//! 
//! 通过 souvlaki 库实现跨平台系统媒体会话，让系统识别到应用正在播放音乐。
//! Android 端不使用此模块（由 Flutter 原生层的 MediaSession 处理）。

#[cfg(not(target_os = "android"))]
use souvlaki::{
    MediaControlEvent, MediaControls, MediaMetadata, MediaPlayback, MediaPosition, PlatformConfig,
};
use std::sync::{mpsc, Mutex, LazyLock};
use std::time::Duration;

/// 媒体控制事件（从系统发送到应用）
#[derive(Debug, Clone)]
pub enum MediaEvent {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    Stop,
    SeekTo(f64), // 秒
}

/// 全局媒体控制实例
static MEDIA_CONTROLS: LazyLock<Mutex<Option<MediaControlsWrapper>>> =
    LazyLock::new(|| Mutex::new(None));

/// 事件接收通道
static EVENT_RECEIVER: LazyLock<Mutex<Option<mpsc::Receiver<MediaEvent>>>> =
    LazyLock::new(|| Mutex::new(None));

/// 包装 MediaControls 使其可以跨线程使用
#[cfg(not(target_os = "android"))]
struct MediaControlsWrapper {
    controls: MediaControls,
}

#[cfg(not(target_os = "android"))]
// Safety: MediaControls from souvlaki is Send+Sync
unsafe impl Send for MediaControlsWrapper {}
unsafe impl Sync for MediaControlsWrapper {}

#[cfg(not(target_os = "android"))]
impl MediaControlsWrapper {
    fn new(controls: MediaControls) -> Self {
        Self { controls }
    }
}

/// 初始化系统媒体控制
/// 
/// - Windows: 需要传入窗口句柄 (HWND as i64)
/// - macOS: hwnd 参数被忽略，传 0 即可
#[cfg(not(target_os = "android"))]
pub fn init_media_controls(hwnd: i64) -> Result<(), String> {
    let (event_tx, event_rx) = mpsc::channel::<MediaEvent>();

    #[cfg(target_os = "windows")]
    let hwnd_ptr = if hwnd != 0 {
        Some(hwnd as *mut std::ffi::c_void)
    } else {
        return Err("Windows 平台需要有效的窗口句柄".to_string());
    };

    #[cfg(not(target_os = "windows"))]
    let hwnd_ptr: Option<*mut std::ffi::c_void> = None;

    let config = PlatformConfig {
        display_name: "JMusic",
        dbus_name: "com.jmusic.app",
        hwnd: hwnd_ptr,
    };

    let mut controls =
        MediaControls::new(config).map_err(|e| format!("创建媒体控制失败: {:?}", e))?;

    // 注册事件处理器
    let tx = event_tx.clone();
    controls
        .attach(move |event: MediaControlEvent| {
            let mapped = match event {
                MediaControlEvent::Play => Some(MediaEvent::Play),
                MediaControlEvent::Pause => Some(MediaEvent::Pause),
                MediaControlEvent::Toggle => Some(MediaEvent::Toggle),
                MediaControlEvent::Next => Some(MediaEvent::Next),
                MediaControlEvent::Previous => Some(MediaEvent::Previous),
                MediaControlEvent::Stop => Some(MediaEvent::Stop),
                MediaControlEvent::SetPosition(pos) => {
                    // MediaPosition 包含一个 Duration
                    Some(MediaEvent::SeekTo(pos.0.as_secs_f64()))
                }
                _ => None,
            };
            if let Some(evt) = mapped {
                let _ = tx.send(evt);
            }
        })
        .map_err(|e| format!("注册事件处理器失败: {:?}", e))?;

    // 设置初始状态为停止
    controls
        .set_playback(MediaPlayback::Stopped)
        .map_err(|e| format!("设置播放状态失败: {:?}", e))?;

    *MEDIA_CONTROLS.lock().unwrap() = Some(MediaControlsWrapper::new(controls));
    *EVENT_RECEIVER.lock().unwrap() = Some(event_rx);

    log::info!("系统媒体控制初始化成功");
    Ok(())
}

#[cfg(target_os = "android")]
pub fn init_media_controls(_hwnd: i64) -> Result<(), String> {
    // Android 端由 Flutter 原生层处理 MediaSession
    Ok(())
}

/// 更新系统媒体控制的元数据（歌曲信息）
#[cfg(not(target_os = "android"))]
pub fn update_media_metadata(title: &str, artist: &str, album: &str, duration_secs: f64) {
    let mut guard = MEDIA_CONTROLS.lock().unwrap();
    if let Some(wrapper) = guard.as_mut() {
        let duration = if duration_secs > 0.0 {
            Some(Duration::from_secs_f64(duration_secs))
        } else {
            None
        };

        let _ = wrapper.controls.set_metadata(MediaMetadata {
            title: Some(title),
            artist: Some(artist),
            album: Some(album),
            duration,
            cover_url: None,
        });
    }
}

#[cfg(target_os = "android")]
pub fn update_media_metadata(_title: &str, _artist: &str, _album: &str, _duration_secs: f64) {}

/// 更新系统媒体控制的播放状态
#[cfg(not(target_os = "android"))]
pub fn update_media_playback(is_playing: bool, position_secs: f64) {
    let mut guard = MEDIA_CONTROLS.lock().unwrap();
    if let Some(wrapper) = guard.as_mut() {
        let playback = if is_playing {
            MediaPlayback::Playing {
                progress: Some(MediaPosition(Duration::from_secs_f64(position_secs))),
            }
        } else {
            MediaPlayback::Paused {
                progress: Some(MediaPosition(Duration::from_secs_f64(position_secs))),
            }
        };
        let _ = wrapper.controls.set_playback(playback);
    }
}

#[cfg(target_os = "android")]
pub fn update_media_playback(_is_playing: bool, _position_secs: f64) {}

/// 设置播放状态为停止
#[cfg(not(target_os = "android"))]
pub fn update_media_stopped() {
    let mut guard = MEDIA_CONTROLS.lock().unwrap();
    if let Some(wrapper) = guard.as_mut() {
        let _ = wrapper.controls.set_playback(MediaPlayback::Stopped);
    }
}

#[cfg(target_os = "android")]
pub fn update_media_stopped() {}

/// 轮询获取系统媒体控制事件（非阻塞）
/// 返回 None 表示没有新事件
pub fn poll_media_event() -> Option<MediaEvent> {
    let guard = EVENT_RECEIVER.lock().unwrap();
    if let Some(rx) = guard.as_ref() {
        rx.try_recv().ok()
    } else {
        None
    }
}
