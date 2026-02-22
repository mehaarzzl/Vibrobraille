package com.vibrobraille.vibrobraille_hybrid

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.vibrobraille.haptics.HapticBridge

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.vibrobraille/haptics"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize the HapticBridge and register it with the MethodChannel
        val hapticBridge = HapticBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(hapticBridge)
    }
}
