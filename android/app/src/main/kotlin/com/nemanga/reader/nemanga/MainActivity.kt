package com.nemanga.reader.nemanga

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
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

        val zipFile = ZipFile(sourceFile)
        val entries = zipFile.entries().asSequence().toList()

        var imageCount = 0
        ZipOutputStream(BufferedOutputStream(FileOutputStream(targetFile))).use { zos ->
            // Формат WebP
            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                @Suppress("DEPRECATION")
                Bitmap.CompressFormat.WEBP
            }

            for (entry in entries) {
                if (entry.isDirectory) continue

                val isImage = isImageExtension(entry.name) && !entry.name.contains("__MACOSX")

                if (isImage) {
                    imageCount++
                    zipFile.getInputStream(entry).use { inputStream ->
                        val options = BitmapFactory.Options().apply {
                            inPreferredConfig = Bitmap.Config.ARGB_8888
                        }
                        val originalBitmap = BitmapFactory.decodeStream(inputStream, null, options)

                        if (originalBitmap != null) {
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
                            val dotIndex = entry.name.lastIndexOf('.')
                            val baseName = if (dotIndex > 0) entry.name.substring(0, dotIndex) else entry.name
                            val newEntryName = "$baseName.webp"

                            val newEntry = ZipEntry(newEntryName)
                            zos.putNextEntry(newEntry)
                            zos.write(compressedBytes)
                            zos.closeEntry()

                            if (bitmapToCompress != originalBitmap) {
                                bitmapToCompress.recycle()
                            }
                            originalBitmap.recycle()
                        } else {
                            // Если не удалось декодировать как Bitmap, копируем как есть
                            zipFile.getInputStream(entry).use { rawStream ->
                                val fallbackEntry = ZipEntry(entry.name)
                                zos.putNextEntry(fallbackEntry)
                                rawStream.copyTo(zos)
                                zos.closeEntry()
                            }
                        }
                    }
                } else {
                    // Текстовые файлы, оглавление и прочие метаданные переносим без изменений
                    zipFile.getInputStream(entry).use { nonImageStream ->
                        val plainEntry = ZipEntry(entry.name)
                        zos.putNextEntry(plainEntry)
                        nonImageStream.copyTo(zos)
                        zos.closeEntry()
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
