package com.jmusic.jmusic

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PERMISSIONS_CHANNEL = "com.jmusic.app/permissions"
    private val PLAYER_CHANNEL = "com.jmusic.app/player"
    private var pendingResult: MethodChannel.Result? = null
    private val PICK_DIRECTORY_REQUEST = 2001

    private var musicService: MusicService? = null
    private var serviceBound = false
    private var playerChannel: MethodChannel? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as MusicService.MusicBinder
            musicService = binder.getService()
            serviceBound = true

            // 注册媒体控制事件回调 → 转发给 Flutter
            musicService?.onMediaAction = { action ->
                runOnUiThread {
                    playerChannel?.invokeMethod("onMediaAction", action)
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            musicService = null
            serviceBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 绑定音乐服务（不立即启动前台服务，等播放时再启动）
        val serviceIntent = Intent(this, MusicService::class.java)
        bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)

        // 权限和目录选择
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestStoragePermission" -> {
                        if (hasStoragePermission()) {
                            result.success(true)
                        } else {
                            requestStoragePermission()
                            result.success(false)
                        }
                    }
                    "hasStoragePermission" -> {
                        result.success(hasStoragePermission())
                    }
                    "pickDirectory" -> {
                        pendingResult = result
                        pickDirectory()
                    }
                    else -> result.notImplemented()
                }
            }

        // 音频播放 — 通过 MusicService 处理
        playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYER_CHANNEL)
        playerChannel!!.setMethodCallHandler { call, result ->
            val arg = call.arguments as? String ?: ""
            when (call.method) {
                "play" -> {
                    try {
                        // 确保服务以 startService 方式启动（startForeground 需要）
                        val svcIntent = Intent(this@MainActivity, MusicService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(svcIntent)
                        } else {
                            startService(svcIntent)
                        }
                        musicService?.play(arg)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("PLAY_ERROR", e.message, null)
                    }
                }
                "pause" -> {
                    musicService?.pause()
                    result.success(null)
                }
                "resume" -> {
                    musicService?.resume()
                    result.success(null)
                }
                "stop" -> {
                    musicService?.stop()
                    result.success(null)
                }
                "seek" -> {
                    val secs = arg.toDoubleOrNull() ?: 0.0
                    musicService?.seekTo((secs * 1000).toInt())
                    result.success(null)
                }
                "setVolume" -> {
                    val vol = arg.toFloatOrNull() ?: 1.0f
                    musicService?.setVolume(vol)
                    result.success(null)
                }
                "getPosition" -> {
                    val pos = musicService?.getCurrentPosition() ?: 0
                    result.success(pos)
                }
                "isPlaying" -> {
                    result.success(musicService?.isPlaying() ?: false)
                }
                "updateMetadata" -> {
                    // 参数格式: "title\nartist\nalbum\ndurationSecs"
                    val parts = arg.split("\n")
                    if (parts.size >= 4) {
                        val title = parts[0]
                        val artist = parts[1]
                        val album = parts[2]
                        val durationSecs = parts[3].toDoubleOrNull() ?: 0.0
                        musicService?.updateMetadata(title, artist, album, durationSecs)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        super.onDestroy()
    }

    // --- 权限相关 ---

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!Environment.isExternalStorageManager()) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                } catch (e: Exception) {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    startActivity(intent)
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(arrayOf(
                android.Manifest.permission.READ_EXTERNAL_STORAGE,
                android.Manifest.permission.WRITE_EXTERNAL_STORAGE
            ), 1001)
        }
    }

    // --- 目录选择 ---

    private fun pickDirectory() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        startActivityForResult(intent, PICK_DIRECTORY_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_DIRECTORY_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val path = getPathFromUri(data.data!!)
                pendingResult?.success(path)
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }

    private fun getPathFromUri(uri: Uri): String? {
        val docId = try {
            android.provider.DocumentsContract.getTreeDocumentId(uri)
        } catch (e: Exception) { null }

        if (docId != null) {
            val split = docId.split(":")
            val type = split[0]
            val relativePath = if (split.size > 1) split[1] else ""

            if ("primary".equals(type, ignoreCase = true)) {
                val basePath = Environment.getExternalStorageDirectory().absolutePath
                return if (relativePath.isEmpty()) basePath else "$basePath/$relativePath"
            } else {
                return if (relativePath.isEmpty()) "/storage/$type" else "/storage/$type/$relativePath"
            }
        }
        return null
    }
}
