package app.viptech.pumpwatch

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Build
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
                else -> result.notImplemented()
            }
        }
    }
}
