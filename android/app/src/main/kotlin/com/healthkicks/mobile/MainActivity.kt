package com.healthkicks.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationListener
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.function.Consumer

class MainActivity : FlutterFragmentActivity() {
    private val locationChannelName = "com.healthkicks.mobile/location"
    private val smsChannelName = "healthkicks/sms"
    private val smsPermissionRequestCode = 9112

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCurrentLocation") {
                    val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: 3000L)
                        .coerceIn(1L, 3000L)
                    requestCurrentLocation(timeoutMs, result)
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
    private fun requestCurrentLocation(timeoutMs: Long, result: MethodChannel.Result) {
        val hasFine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasFine && !hasCoarse) {
            result.success(null)
            return
        }

        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (locationManager == null) {
            result.success(null)
            return
        }

        val lastKnownLocation = getBestLastKnownLocation(locationManager)
        if (lastKnownLocation?.isRecentAndPrecise() == true) {
            result.success(lastKnownLocation.toChannelMap())
            return
        }

        val providers = try {
            locationManager.getProviders(true)
        } catch (_: SecurityException) {
            emptyList()
        }
        if (providers.isEmpty()) {
            result.success(lastKnownLocation?.toChannelMap())
            return
        }

        PendingLocationRequest(
            locationManager = locationManager,
            providers = providers,
            fallback = lastKnownLocation,
            timeoutMs = timeoutMs,
            result = result
        ).start()
    }

    @SuppressLint("MissingPermission")
    private fun getBestLastKnownLocation(locationManager: LocationManager): Location? {
        return try {
            var bestLocation: Location? = null
            for (provider in locationManager.getProviders(true)) {
                val location = locationManager.getLastKnownLocation(provider) ?: continue
                if (bestLocation == null || location.accuracy < bestLocation.accuracy) {
                    bestLocation = location
                }
            }
            bestLocation
        } catch (_: SecurityException) {
            null
        }
    }

    private fun Location.isRecentAndPrecise(): Boolean {
        val ageMs = System.currentTimeMillis() - time
        return ageMs in 0..120_000 && accuracy <= 50f
    }

    private fun Location.toChannelMap(): Map<String, Any> = mapOf(
        "lat" to latitude,
        "lon" to longitude,
        "accuracy_m" to accuracy.toDouble(),
        "captured_at" to time
    )

    private inner class PendingLocationRequest(
        private val locationManager: LocationManager,
        private val providers: List<String>,
        private val fallback: Location?,
        private val timeoutMs: Long,
        private val result: MethodChannel.Result
    ) {
        private val handler = Handler(Looper.getMainLooper())
        private val cancellationSignals = mutableListOf<CancellationSignal>()
        private var locationListener: LocationListener? = null
        private var completed = false

        private val timeoutRunnable = Runnable {
            complete(fallback)
        }

        private val mainExecutor = Executor { command ->
            handler.post(command)
        }

        fun start() {
            handler.postDelayed(timeoutRunnable, timeoutMs)
            var requestsStarted = 0

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                for (provider in providers) {
                    val signal = CancellationSignal()
                    cancellationSignals.add(signal)
                    try {
                        locationManager.getCurrentLocation(
                            provider,
                            signal,
                            mainExecutor,
                            Consumer<Location?> { location ->
                                if (location != null) complete(location)
                            }
                        )
                        requestsStarted++
                    } catch (_: IllegalArgumentException) {
                        cancellationSignals.remove(signal)
                        signal.cancel()
                    } catch (_: SecurityException) {
                        cancellationSignals.remove(signal)
                        signal.cancel()
                    }
                }
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        complete(location)
                    }
                }
                locationListener = listener
                for (provider in providers) {
                    try {
                        @Suppress("DEPRECATION")
                        locationManager.requestSingleUpdate(
                            provider,
                            listener,
                            Looper.getMainLooper()
                        )
                        requestsStarted++
                    } catch (_: IllegalArgumentException) {
                        // Continue with the remaining enabled providers.
                    } catch (_: SecurityException) {
                        // Permission may have been revoked while the request was starting.
                    }
                }
            }

            if (requestsStarted == 0) {
                complete(fallback)
            }
        }

        private fun complete(location: Location?) {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeoutRunnable)
            locationListener?.let(locationManager::removeUpdates)
            cancellationSignals.forEach(CancellationSignal::cancel)
            result.success(location?.toChannelMap())
        }
    }
}
