package com.healthkicks.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val locationChannelName = "com.healthkicks.mobile/location"
    private val smsChannelName = "healthkicks/sms"
    private val smsPermissionRequestCode = 9112

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCurrentLocation") {
                    result.success(getBestLastKnownLocation())
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestSmsPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.SEND_SMS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.SEND_SMS),
                                smsPermissionRequestCode
                            )
                        }
                        result.success(granted)
                    }
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")?.trim() ?: ""
                        val message = call.argument<String>("message") ?: ""
                        if (phone.isEmpty() || message.isEmpty()) {
                            result.error("INVALID_ARGUMENTS", "Phone or message is empty", null)
                            return@setMethodCallHandler
                        }
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.SEND_SMS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            result.error("PERMISSION_DENIED", "SEND_SMS permission not granted", null)
                            return@setMethodCallHandler
                        }
                        try {
                            @Suppress("DEPRECATION")
                            val smsManager = getSystemService(SmsManager::class.java)
                                ?: SmsManager.getDefault()
                            val parts = smsManager.divideMessage(message)
                            if (parts.size > 1) {
                                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                            } else {
                                smsManager.sendTextMessage(phone, null, message, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_SEND_FAILED", e.message ?: "Failed to send SMS", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("MissingPermission")
    private fun getBestLastKnownLocation(): Map<String, Any>? {
        val hasFine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasFine && !hasCoarse) {
            return null
        }

        return try {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return null
            val providers = locationManager.getProviders(true)
            var bestLocation: Location? = null
            for (provider in providers) {
                val loc = locationManager.getLastKnownLocation(provider) ?: continue
                if (bestLocation == null || loc.accuracy < bestLocation.accuracy) {
                    bestLocation = loc
                }
            }
            if (bestLocation != null) {
                mapOf(
                    "lat" to bestLocation.latitude,
                    "lon" to bestLocation.longitude,
                    "accuracy_m" to bestLocation.accuracy.toDouble(),
                    "captured_at" to bestLocation.time
                )
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }
}
