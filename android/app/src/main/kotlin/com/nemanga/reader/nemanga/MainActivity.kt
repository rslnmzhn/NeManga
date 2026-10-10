package com.nemanga.reader.nemanga

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {
    private val UPDATER_CHANNEL = "com.nemanga.reader/updater"
    private val COMPRESSOR_CHANNEL = "com.nemanga.reader/compressor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Канал автообновления
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceAbi" -> {
                    val abi = if (Build.SUPPORTED_ABIS.isNotEmpty()) Build.SUPPORTED_ABIS[0] else "arm64-v8a"
                    result.success(abi)
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        val vName = pInfo.versionName ?: "0.0.1"
                        result.success(vName)
                    } catch (_: Exception) {
                        result.success("0.0.1")
                    }
                }
                "canInstallPackages" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.error("SETTINGS_UNAVAILABLE", "Cannot open install permission settings", null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_PATH", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    val apkFile = File(filePath)
                    if (!apkFile.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist: $filePath", null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        } catch (_: ActivityNotFoundException) {
                        }
                        result.success("pendingPermission")
                        return@setMethodCallHandler
                    }

                    try {
                        val authority = "$packageName.updater.files"
                        val apkUri = FileProvider.getUriForFile(this, authority, apkFile)
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(installIntent)
                        result.success("installerLaunched")
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Канал нативного сжатия архивов манги
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMPRESSOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPublicMangaDirectory" -> {
                    val publicDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "NeManga")
                    if (!publicDir.exists()) {
                        publicDir.mkdirs()
                    }
                    result.success(publicDir.absolutePath)
                }
                "scanMediaFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                    }
                    result.success(true)
                }
                "deleteFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    var deleted = false
                    try {
                        val file = File(path)
                        if (file.exists()) {
                            deleted = file.delete()
                        }
                    } catch (_: Exception) {}
                    if (deleted) {
                        MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                    }
                    result.success(deleted)
                }
                "compressArchive" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val targetPath = call.argument<String>("targetPath")
                    val maxWidth = call.argument<Int>("maxWidth") ?: 1440
                    val quality = call.argument<Int>("quality") ?: 80

                    if (sourcePath == null || targetPath == null) {
                        result.error("INVALID_ARGS", "sourcePath and targetPath are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val data = compressArchiveNative(sourcePath, targetPath, maxWidth, quality)
                            runOnUiThread {
                                result.success(data)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("COMPRESSION_FAILED", e.message ?: "Unknown compression error", null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isImageExtension(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
                lower.endsWith(".png") || lower.endsWith(".webp") ||
                lower.endsWith(".bmp") || lower.endsWith(".gif")
    }

    private fun compressArchiveNative(
        sourcePath: String,
        targetPath: String,
        maxWidth: Int,
        quality: Int
    ): Map<String, Any> {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalArgumentException("Source archive not found: $sourcePath")
        }

        val originalSize = sourceFile.length()
        val targetFile = File(targetPath)
        targetFile.parentFile?.mkdirs()

        val zipFile = ZipFile(sourceFile, java.nio.charset.StandardCharsets.UTF_8)
        val entries = zipFile.entries().asSequence().toList()

        var imageCount = 0
        ZipOutputStream(BufferedOutputStream(FileOutputStream(targetFile)), java.nio.charset.StandardCharsets.UTF_8).use { zos ->
            // Формат WebP
            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                @Suppress("DEPRECATION")
                Bitmap.CompressFormat.WEBP
            }

            for (entry in entries) {
                if (entry.isDirectory) continue

                val normalizedName = entry.name.replace('\\', '/')
                val baseName = File(normalizedName).name

                // Игнорируем метаданные macOS, скрытые файлы ._* и 0-байтные файлы
                if (baseName.startsWith(".") || normalizedName.contains("__MACOSX") || entry.size == 0L) {
                    continue
                }

                val isImage = isImageExtension(baseName)

                if (isImage) {
                    val originalBitmap = try {
                        zipFile.getInputStream(entry).use { inputStream ->
                            val options = BitmapFactory.Options().apply {
                                inPreferredConfig = Bitmap.Config.ARGB_8888
                            }
                            BitmapFactory.decodeStream(inputStream, null, options)
                        }
                    } catch (_: Exception) {
                        null
                    }

                    if (originalBitmap != null) {
                        imageCount++
                        val bitmapToCompress = if (originalBitmap.width > maxWidth) {
                            val ratio = maxWidth.toFloat() / originalBitmap.width.toFloat()
                            val targetHeight = (originalBitmap.height * ratio).toInt()
                            Bitmap.createScaledBitmap(originalBitmap, maxWidth, targetHeight, true)
                        } else {
                            originalBitmap
                        }

                        val baos = ByteArrayOutputStream()
                        bitmapToCompress.compress(format, quality, baos)
                        val compressedBytes = baos.toByteArray()

                        // Сохраняем имя с расширением .webp
                        val dotIndex = baseName.lastIndexOf('.')
                        val nameNoExt = if (dotIndex > 0) baseName.substring(0, dotIndex) else baseName
                        val newEntryName = "$nameNoExt.webp"

                        val newEntry = ZipEntry(newEntryName)
                        zos.putNextEntry(newEntry)
                        zos.write(compressedBytes)
                        zos.closeEntry()

                        if (bitmapToCompress != originalBitmap) {
                            bitmapToCompress.recycle()
                        }
                        originalBitmap.recycle()
                    }
                } else {
                    // Текстовые файлы, ComicInfo.xml переносим только полезные данные
                    val lower = baseName.lowercase()
                    if (lower.endsWith(".xml") || lower.endsWith(".txt") || lower.endsWith(".json")) {
                        zipFile.getInputStream(entry).use { nonImageStream ->
                            val plainEntry = ZipEntry(baseName)
                            zos.putNextEntry(plainEntry)
                            nonImageStream.copyTo(zos)
                            zos.closeEntry()
                        }
                    }
                }
            }
        }
        zipFile.close()

        val compressedSize = targetFile.length()
        val savedBytes = originalSize - compressedSize
        val savedPercent = if (originalSize > 0) (savedBytes.toDouble() / originalSize.toDouble() * 100.0) else 0.0

        return mapOf(
            "originalSize" to originalSize,
            "compressedSize" to compressedSize,
            "savedPercent" to savedPercent,
            "targetPath" to targetPath,
            "totalImages" to imageCount
        )
    }
}
