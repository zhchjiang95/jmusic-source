use rodio::{OutputStream, Sink};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread;

use super::source::SeekableSource;
use super::spectrum::{spawn_worker, SpectrumAnalyzer};

/// 音频引擎命令
enum AudioCommand {
    /// 播放文件
    Play(String, mpsc::Sender<Result<(), String>>),
    /// 暂停
    Pause,
    /// 恢复
    Resume,
    /// 停止
    Stop,
    /// 设置音量
    SetVolume(f32),
    /// 获取音量
    GetVolume(mpsc::Sender<f32>),
    /// 设置播放速度（0.5~2.0）
    SetSpeed(f32),
    /// 跳转到指定位置（秒）
    Seek(f64, mpsc::Sender<Result<(), String>>),
    /// 检查是否播放完毕
    IsFinished(mpsc::Sender<bool>),
    /// 退出引擎线程
    Shutdown,
}

/// 音频播放引擎（通过命令通道与音频线程通信）
pub struct AudioEngine {
    cmd_tx: mpsc::Sender<AudioCommand>,
    analyzer: Arc<SpectrumAnalyzer>,
    shutdown: Arc<AtomicBool>,
    _worker: Option<thread::JoinHandle<()>>,
}

impl AudioEngine {
    /// 创建新的音频引擎实例
    /// 在单独的线程中运行音频输出（因为 OutputStream 不是 Send）
    pub fn new() -> Result<Self, String> {
        let (cmd_tx, cmd_rx) = mpsc::channel::<AudioCommand>();

        // 创建频谱分析器和 worker 线程
        let analyzer = SpectrumAnalyzer::new();
        let shutdown = Arc::new(AtomicBool::new(false));
        let worker = spawn_worker(analyzer.clone(), shutdown.clone());
        let analyzer_for_thread = analyzer.clone();

        // 启动音频专用线程
        thread::spawn(move || {
            // 在这个线程中创建音频输出
            let (stream, stream_handle) = match OutputStream::try_default() {
                Ok(pair) => pair,
                Err(e) => {
                    log::error!("无法初始化音频输出: {}", e);
                    return;
                }
            };

            let mut sink: Option<Sink> = None;
            let mut current_file: Option<String> = None;
            let _stream = stream; // 保持存活
            let analyzer = analyzer_for_thread;

            // 处理命令循环
            while let Ok(cmd) = cmd_rx.recv() {
                match cmd {
                    AudioCommand::Play(file_path, reply) => {
                        let result = (|| -> Result<(), String> {
                            let source = SeekableSource::new(&file_path)?
                                .with_analyzer(analyzer.clone());

                            // 停止当前播放
                            if let Some(s) = sink.take() {
                                s.stop();
                            }

                            // 创建新 Sink 并播放
                            let new_sink = Sink::try_new(&stream_handle)
                                .map_err(|e| format!("无法创建 Sink: {}", e))?;
                            new_sink.append(source);
                            current_file = Some(file_path);
                            sink = Some(new_sink);
                            analyzer.set_paused(false);
                            Ok(())
                        })();
                        let _ = reply.send(result);
                    }
                    AudioCommand::Pause => {
                        if let Some(s) = &sink {
                            s.pause();
                        }
                        analyzer.set_paused(true);
                    }
                    AudioCommand::Resume => {
                        if let Some(s) = &sink {
                            s.play();
                        }
                        analyzer.set_paused(false);
                    }
                    AudioCommand::Stop => {
                        if let Some(s) = sink.take() {
                            s.stop();
                        }
                        current_file = None;
                        analyzer.set_paused(true);
                        analyzer.clear_frame();
                    }
                    AudioCommand::SetVolume(vol) => {
                        if let Some(s) = &sink {
                            s.set_volume(vol.clamp(0.0, 1.0));
                        }
                    }
                    AudioCommand::SetSpeed(speed) => {
                        if let Some(s) = &sink {
                            s.set_speed(speed.clamp(0.25, 3.0));
                        }
                    }
                    AudioCommand::GetVolume(reply) => {
                        let vol = sink.as_ref().map(|s| s.volume()).unwrap_or(1.0);
                        let _ = reply.send(vol);
                    }
                    AudioCommand::Seek(pos, reply) => {
                        let result = (|| -> Result<(), String> {
                            let file_path = current_file.as_ref()
                                .ok_or("未在播放".to_string())?
                                .clone();
                            let volume = sink.as_ref().map(|s| s.volume()).unwrap_or(1.0);
                            let was_paused = sink.as_ref()
                                .map(|s| s.is_paused()).unwrap_or(false);

                            // 停止当前播放
                            if let Some(s) = sink.take() {
                                s.stop();
                            }

                            // 重新打开文件，用 symphonia 直接 seek（容器级高效跳转）
                            let mut source = SeekableSource::new(&file_path)?;
                            source.seek(pos)?;
                            let source = source.with_analyzer(analyzer.clone());

                            // 创建新 Sink 从 seek 位置播放
                            let new_sink = Sink::try_new(&stream_handle)
                                .map_err(|e| format!("无法创建 Sink: {}", e))?;
                            new_sink.set_volume(volume);
                            new_sink.append(source);

                            if was_paused {
                                new_sink.pause();
                            }

                            sink = Some(new_sink);
                            Ok(())
                        })();
                        let _ = reply.send(result);
                    }
                    AudioCommand::IsFinished(reply) => {
                        let finished = sink.as_ref().map(|s| s.empty()).unwrap_or(true);
                        let _ = reply.send(finished);
                    }
                    AudioCommand::Shutdown => {
                        if let Some(s) = sink.take() {
                            s.stop();
                        }
                        break;
                    }
                }
            }
        });

        Ok(Self {
            cmd_tx,
            analyzer,
            shutdown,
            _worker: Some(worker),
        })
    }

    /// 获取频谱分析器引用
    pub fn analyzer(&self) -> &Arc<SpectrumAnalyzer> {
        &self.analyzer
    }

    /// 播放指定文件
    pub fn play(&self, file_path: &str) -> Result<(), String> {
        let (tx, rx) = mpsc::channel();
        self.cmd_tx
            .send(AudioCommand::Play(file_path.to_string(), tx))
            .map_err(|_| "音频线程已断开".to_string())?;
        rx.recv().map_err(|_| "音频线程无响应".to_string())?
    }

    /// 暂停播放
    pub fn pause(&self) {
        let _ = self.cmd_tx.send(AudioCommand::Pause);
    }

    /// 恢复播放
    pub fn resume(&self) {
        let _ = self.cmd_tx.send(AudioCommand::Resume);
    }

    /// 停止播放
    pub fn stop(&self) {
        let _ = self.cmd_tx.send(AudioCommand::Stop);
    }

    /// 设置音量（0.0 ~ 1.0）
    pub fn set_volume(&self, volume: f32) {
        let _ = self.cmd_tx.send(AudioCommand::SetVolume(volume));
    }

    /// 设置播放速度（0.5 ~ 2.0）
    pub fn set_speed(&self, speed: f32) {
        let _ = self.cmd_tx.send(AudioCommand::SetSpeed(speed));
    }

    /// 获取当前音量
    pub fn get_volume(&self) -> f32 {
        let (tx, rx) = mpsc::channel();
        if self.cmd_tx.send(AudioCommand::GetVolume(tx)).is_ok() {
            rx.recv().unwrap_or(1.0)
        } else {
            1.0
        }
    }

    /// 检查是否播放完毕
    pub fn is_finished(&self) -> bool {
        let (tx, rx) = mpsc::channel();
        if self.cmd_tx.send(AudioCommand::IsFinished(tx)).is_ok() {
            rx.recv().unwrap_or(true)
        } else {
            true
        }
    }

    /// 跳转到指定位置（秒）
    pub fn seek(&self, position_secs: f64) -> Result<(), String> {
        let (tx, rx) = mpsc::channel();
        self.cmd_tx
            .send(AudioCommand::Seek(position_secs, tx))
            .map_err(|_| "音频线程已断开".to_string())?;
        rx.recv().map_err(|_| "音频线程无响应".to_string())?
    }
}

impl Drop for AudioEngine {
    fn drop(&mut self) {
        let _ = self.cmd_tx.send(AudioCommand::Shutdown);
        self.shutdown.store(true, Ordering::Release);
        // Best-effort join the worker thread
        if let Some(handle) = self._worker.take() {
            let _ = handle.join();
        }
    }
}
