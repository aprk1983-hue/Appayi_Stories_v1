package com.app.audiostoryapp

import android.content.Context
import android.os.Bundle
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val engineId = "audio_service_engine"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Create and cache the FlutterEngine for audio service
        if (!FlutterEngineCache.getInstance().contains(engineId)) {
            val flutterEngine = FlutterEngine(this)
            
            // For audio_service 0.18.12, we don't need registerWith
            // The plugin is automatically registered
            
            flutterEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            
            FlutterEngineCache.getInstance().put(engineId, flutterEngine)
        }
    }
    
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // Return the cached engine
        return FlutterEngineCache.getInstance().get(engineId)
    }
}