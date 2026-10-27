package app.viptech.pumpwatch

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Adds a small "pumpwatch/usb" channel: list USB devices and ask Android for USB permission. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pumpwatch/usb").setMethodCallHandler { call, result ->
            val usb = getSystemService(Context.USB_SERVICE) as UsbManager
            when (call.method) {
                "list" -> {
                    val out = ArrayList<Map<String, Any?>>()
                    for (d in usb.deviceList.values) {
                        val classes = ArrayList<Int>()
                        for (i in 0 until d.interfaceCount) classes.add(d.getInterface(i).interfaceClass)
                        out.add(
                            mapOf(
                                "name" to d.deviceName,
                                "vendorId" to d.vendorId,
                                "productId" to d.productId,
                                "deviceClass" to d.deviceClass,
                                "interfaceClasses" to classes,
                                "product" to (try { d.productName } catch (e: Exception) { null }),
                                "maker" to (try { d.manufacturerName } catch (e: Exception) { null }),
                                "hasPermission" to usb.hasPermission(d),
                            )
                        )
                    }
                    result.success(out)
                }
                "request" -> {
                    val name = call.argument<String>("name")
                    val d = usb.deviceList[name]
                    if (d == null) {
                        result.success(false)
                    } else {
                        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                        val pi = PendingIntent.getBroadcast(
                            this, 0, Intent("app.viptech.pumpwatch.USB_PERMISSION").setPackage(packageName), flags
                        )
                        usb.requestPermission(d, pi)
                        result.success(usb.hasPermission(d))
                    }
                }
                "nv21ToJpeg" -> {
                    // Saves one camera frame as a JPEG "sign photo" (runs off the UI thread).
                    val bytes = call.argument<ByteArray>("bytes")
                    val w = call.argument<Int>("width") ?: 0
                    val h = call.argument<Int>("height") ?: 0
                    val rot = call.argument<Int>("rotation") ?: 0
                    val path = call.argument<String>("path")
                    if (bytes == null || path == null || w <= 0 || h <= 0 || bytes.size < w * h * 3 / 2) {
                        result.success(false)
                    } else {
                        Thread {
                            val ok = try {
                                val out = ByteArrayOutputStream()
                                YuvImage(bytes, ImageFormat.NV21, w, h, null).compressToJpeg(Rect(0, 0, w, h), 80, out)
                                var jpg = out.toByteArray()
                                if (rot != 0) {
                                    val bmp = BitmapFactory.decodeByteArray(jpg, 0, jpg.size)
                                    val m = Matrix().apply { postRotate(rot.toFloat()) }
                                    val r = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
                                    val o2 = ByteArrayOutputStream()
                                    r.compress(Bitmap.CompressFormat.JPEG, 80, o2)
                                    jpg = o2.toByteArray()
                                }
                                File(path).writeBytes(jpg)
                                true
                            } catch (e: Exception) {
                                false
                            }
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
