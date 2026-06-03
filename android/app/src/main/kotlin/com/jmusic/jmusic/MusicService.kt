package com.jmusic.jmusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.MediaPlayer
import android.media.audiofx.Visualizer
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sqrt

class MusicService : Service() {

    companion object {
        const val CHANNEL_ID = "jmusic_playback_channel"
        const val NOTIFICATION_ID = 1
    }

    private var mediaPlayer: MediaPlayer? = null
    private lateinit var mediaSession: MediaSessionCompat
    private var currentTitle: String = ""
    private var currentArtist: String = ""
    private var currentAlbum: String = ""
    private var durationMs: Long = 0
    private var isForeground: Boolean = false

    // 频谱分析器
    private var visualizer: Visualizer? = null
    private val NUM_BINS = 64
    @Volatile
    private var spectrumData: FloatArray = FloatArray(NUM_BINS)
    private val DB_FLOOR = -60.0f
    private val DB_CEIL = 0.0f

    // 回调接口，用于通知 Flutter 端
    var onMediaAction: ((String) -> Unit)? = null

    private val binder = MusicBinder()

    inner class MusicBinder : Binder() {
        fun getService(): MusicService = this@MusicService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initMediaSession()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(mediaSession, intent)
        // startForegroundService 要求 5 秒内调用 startForeground
        if (!isForeground) {
            showNotification()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseVisualizer()
        mediaPlayer?.release()
        mediaPlayer = null
        mediaSession.release()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "音乐播放",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "音乐播放控制通知"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun initMediaSession() {
        mediaSession = MediaSessionCompat(this, "JMusicSession").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )

            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    onMediaAction?.invoke("play")
                }

                override fun onPause() {
                    onMediaAction?.invoke("pause")
                }

                override fun onSkipToNext() {
                    onMediaAction?.invoke("next")
                }

                override fun onSkipToPrevious() {
                    onMediaAction?.invoke("previous")
                }

                override fun onStop() {
                    onMediaAction?.invoke("stop")
                }

                override fun onSeekTo(pos: Long) {
                    onMediaAction?.invoke("seek:$pos")
                }
            })

            isActive = true
        }
    }

    // --- 播放控制 ---

    fun play(filePath: String) {
        mediaPlayer?.release()
        mediaPlayer = MediaPlayer().apply {
            setDataSource(filePath)
            prepare()
            start()
            durationMs = duration.toLong()
        }
        startVisualizer()
        updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
        showNotification()
    }

    fun pause() {
        mediaPlayer?.pause()
        updatePlaybackState(PlaybackStateCompat.STATE_PAUSED)
        showNotification()
    }

    fun resume() {
        mediaPlayer?.start()
        updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
        showNotification()
    }

    fun stop() {
        releaseVisualizer()
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        updatePlaybackState(PlaybackStateCompat.STATE_STOPPED)
        stopForeground(STOP_FOREGROUND_REMOVE)
        isForeground = false
        stopSelf()
    }

    fun seekTo(positionMs: Int) {
        mediaPlayer?.seekTo(positionMs)
        val state = if (mediaPlayer?.isPlaying == true) {
            PlaybackStateCompat.STATE_PLAYING
        } else {
            PlaybackStateCompat.STATE_PAUSED
        }
        updatePlaybackState(state)
    }

    fun setVolume(volume: Float) {
        mediaPlayer?.setVolume(volume, volume)
    }

    fun getCurrentPosition(): Int = mediaPlayer?.currentPosition ?: 0

    fun isPlaying(): Boolean = mediaPlayer?.isPlaying ?: false

    /**
     * 获取当前 64-bin 归一化频谱数据 (0.0~1.0)
     */
    fun getSpectrum(): FloatArray = spectrumData

    /**
     * 启动 Visualizer，绑定到 MediaPlayer 的 audio session
     */
    private fun startVisualizer() {
        releaseVisualizer()
        val player = mediaPlayer ?: return
        try {
            val sessionId = player.audioSessionId
            visualizer = Visualizer(sessionId).apply {
                // 设置采集大小（必须是 2 的幂，范围 128~1024）
                val capSize = Visualizer.getCaptureSizeRange()
                val desiredSize = 1024 // 足够做 64-bin 对数分箱
                captureSize = desiredSize.coerceIn(capSize[0], capSize[1])

                setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int
                    ) {
                        // 不使用波形数据
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int
                    ) {
                        if (fft == null || fft.size < 4) return
                        processFFT(fft, samplingRate)
                    }
                }, Visualizer.getMaxCaptureRate(), false, true)

                enabled = true
            }
        } catch (e: Exception) {
            Log.w("MusicService", "Visualizer 初始化失败: ${e.message}")
            visualizer = null
        }
    }

    /**
     * 将 Android Visualizer 的 FFT 字节数据转换为 64-bin 对数频谱
     *
     * Android Visualizer FFT 格式:
     * - fft[0] = DC component (real)
     * - fft[1] = Nyquist component (real)
     * - fft[2k], fft[2k+1] = real, imaginary for bin k (k >= 1)
     */
    private fun processFFT(fft: ByteArray, samplingRate: Int) {
        val n = fft.size / 2 // FFT bin 数量
        if (n < 2) return

        val sampleRate = samplingRate / 1000.0f // Android 传入的是 milliHz，转 Hz
        val binFreqWidth = sampleRate / (n * 2) // 每个 FFT bin 对应的频率宽度

        // 对数分箱：20Hz ~ Nyquist
        val minFreq = 20.0f
        val maxFreq = sampleRate / 2.0f
        val logMin = ln(minFreq.toDouble()).toFloat()
        val logMax = ln(maxFreq.toDouble()).toFloat()

        val output = FloatArray(NUM_BINS)

        for (b in 0 until NUM_BINS) {
            val freqLo = Math.exp((logMin + (logMax - logMin) * b / NUM_BINS).toDouble()).toFloat()
            val freqHi = Math.exp((logMin + (logMax - logMin) * (b + 1) / NUM_BINS).toDouble()).toFloat()

            val binLo = max(1, (freqLo / binFreqWidth).toInt())
            val binHi = max(binLo, minOf((freqHi / binFreqWidth).toInt(), n - 1))

            var sum = 0.0f
            var count = 0
            for (k in binLo..binHi) {
                val real = fft[2 * k].toFloat()
                val imag = fft[2 * k + 1].toFloat()
                val magnitude = sqrt(real * real + imag * imag)
                sum += magnitude
                count++
            }

            if (count > 0) {
                val avg = sum / count
                // dB 归一化
                val db = (20.0f * Math.log10((avg + 1e-9f).toDouble())).toFloat()
                val clamped = db.coerceIn(DB_FLOOR, DB_CEIL)
                output[b] = (clamped - DB_FLOOR) / (DB_CEIL - DB_FLOOR)
            } else {
                output[b] = 0.0f
            }
        }

        spectrumData = output
    }

    /**
     * 释放 Visualizer 资源
     */
    private fun releaseVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
        spectrumData = FloatArray(NUM_BINS)
    }

    // --- 元数据更新 ---

    fun updateMetadata(title: String, artist: String, album: String, durationSecs: Double) {
        currentTitle = title
        currentArtist = artist
        currentAlbum = album
        durationMs = (durationSecs * 1000).toLong()

        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            .build()

        mediaSession.setMetadata(metadata)
        // 更新通知
        if (mediaPlayer != null) {
            showNotification()
        }
    }

    // --- 播放状态 ---

    private fun updatePlaybackState(state: Int) {
        val position = mediaPlayer?.currentPosition?.toLong() ?: 0L
        val playbackSpeed = if (state == PlaybackStateCompat.STATE_PLAYING) 1.0f else 0.0f

        val stateBuilder = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO
            )
            .setState(state, position, playbackSpeed)

        mediaSession.setPlaybackState(stateBuilder.build())
    }

    // --- 通知 ---

    private fun showNotification() {
        val isPlaying = mediaPlayer?.isPlaying ?: false

        // 点击通知打开应用
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle.ifEmpty { "JMusic" })
            .setContentText(currentArtist.ifEmpty { "未知歌手" })
            .setSubText(currentAlbum)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        // 添加控制按钮
        // 上一首
        builder.addAction(
            NotificationCompat.Action(
                android.R.drawable.ic_media_previous, "上一首",
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                )
            )
        )

        // 播放/暂停
        if (isPlaying) {
            builder.addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_pause, "暂停",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this, PlaybackStateCompat.ACTION_PAUSE
                    )
                )
            )
        } else {
            builder.addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play, "播放",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this, PlaybackStateCompat.ACTION_PLAY
                    )
                )
            )
        }

        // 下一首
        builder.addAction(
            NotificationCompat.Action(
                android.R.drawable.ic_media_next, "下一首",
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                )
            )
        )

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isForeground = true
    }
}
