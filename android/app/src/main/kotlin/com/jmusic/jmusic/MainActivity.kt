package com.jmusic.jmusic

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PERMISSIONS_CHANNEL = "com.jmusic.app/permissions"
    private val PLAYER_CHANNEL = "com.jmusic.app/player"
    private var pendingResult: MethodChannel.Result? = null
    private val PICK_DIRECTORY_REQUEST = 2001

    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

        // 音频播放
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYER_CHANNEL)
            .setMethodCallHandler { call, result ->
                val arg = call.arguments as? String ?: ""
                when (call.method) {
                    "play" -> {
                        try {
                            playFile(arg)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    }
                    "pause" -> {
                        mediaPlayer?.pause()
                        result.success(null)
                    }
                    "resume" -> {
                        mediaPlayer?.start()
                        result.success(null)
                    }
                    "stop" -> {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                        mediaPlayer = null
                        result.success(null)
                    }
                    "seek" -> {
                        val secs = arg.toDoubleOrNull() ?: 0.0
                        mediaPlayer?.seekTo((secs * 1000).toInt())
                        result.success(null)
                    }
                    "setVolume" -> {
                        val vol = arg.toFloatOrNull() ?: 1.0f
                        mediaPlayer?.setVolume(vol, vol)
                        result.success(null)
                    }
                    "getPosition" -> {
                        val pos = mediaPlayer?.currentPosition ?: 0
                        result.success(pos)
                    }
                    "isPlaying" -> {
                        result.success(mediaPlayer?.isPlaying ?: false)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playFile(filePath: String) {
        mediaPlayer?.release()
        mediaPlayer = MediaPlayer().apply {
            setDataSource(filePath)
            prepare()
            start()
        }
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
