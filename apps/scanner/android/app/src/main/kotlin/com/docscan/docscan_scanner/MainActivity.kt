package com.docscan.docscan_scanner

import android.content.Intent
import android.content.IntentSender
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    // Set when IDSnap itself opens another activity (file picker, camera,
    // share sheet, document scanner) and captured at the next onPause, so
    // the Dart lock gate can tell "IDSnap opened the camera" from "the user
    // left IDSnap" and doesn't re-lock on return from those flows.
    private var launchedExternal = false
    private var pausedByExternal = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Licensing (ADR-0012): ANDROID_ID survives reinstall and is scoped
        // per signing key and user. Dart hashes it (salted SHA-256) before it
        // is stored or sent. Must match PlatformDeviceIdentity.channelName.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "idsnap/device_id")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceId") {
                    result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
                    )
                } else {
                    result.notImplemented()
                }
            }
        // Ads (ADR-0013): the consent platform (UMP) stores the user's IAB
        // TCF choices in the default preferences. Dart reads them to ask for
        // non-personalised ads when personalised ones aren't allowed. Must
        // match GoogleAdsPlatform.consentChannelName in engine_ads.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "idsnap/ad_consent")
            .setMethodCallHandler { call, result ->
                if (call.method == "tcf") {
                    val prefs = getSharedPreferences("${packageName}_preferences", MODE_PRIVATE)
                    result.success(
                        mapOf(
                            "gdprApplies" to
                                if (prefs.contains("IABTCF_gdprApplies")) {
                                    prefs.getInt("IABTCF_gdprApplies", 0)
                                } else {
                                    null
                                },
                            "purposeConsents" to prefs.getString("IABTCF_PurposeConsents", null),
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }
        // Channel name must match SecureWindow.channelName in engine_security.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "docscan/secure_window")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // FLAG_SECURE blanks the recent-apps thumbnail and blocks
                    // screenshots while App Lock is on or a sensitive screen
                    // is visible.
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        }
                    }
                    "consumeExternalLaunch" -> {
                        val external = pausedByExternal
                        pausedByExternal = false
                        result.success(external)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        // Snapshot per pause: a launch only excuses the pause it caused, never
        // a later, real trip away from the app.
        pausedByExternal = launchedExternal
        launchedExternal = false
        super.onPause()
    }

    @Deprecated("Tracks plugin launches; behaviour is unchanged.")
    override fun startActivityForResult(intent: Intent, requestCode: Int, options: Bundle?) {
        launchedExternal = true
        @Suppress("DEPRECATION")
        super.startActivityForResult(intent, requestCode, options)
    }

    override fun startActivity(intent: Intent, options: Bundle?) {
        launchedExternal = true
        super.startActivity(intent, options)
    }

    @Deprecated("Tracks plugin launches; behaviour is unchanged.")
    override fun startIntentSenderForResult(
        intent: IntentSender,
        requestCode: Int,
        fillInIntent: Intent?,
        flagsMask: Int,
        flagsValues: Int,
        extraFlags: Int,
        options: Bundle?,
    ) {
        launchedExternal = true
        @Suppress("DEPRECATION")
        super.startIntentSenderForResult(
            intent, requestCode, fillInIntent, flagsMask, flagsValues, extraFlags, options,
        )
    }
}
