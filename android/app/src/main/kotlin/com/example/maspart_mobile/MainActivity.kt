package com.example.maspart_mobile

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // lib/peta_google.dart: Google Maps hanya dipakai bila API key terpasang;
        // tanpa kunci, peta Google tampil kosong → Dart memakai OpenStreetMap.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maspart/peta")
            .setMethodCallHandler { call, result ->
                if (call.method == "googleSiap") result.success(adaKunciMaps()) else result.notImplemented()
            }
    }

    private fun adaKunciMaps(): Boolean = try {
        val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        !info.metaData?.getString("com.google.android.geo.API_KEY").isNullOrBlank()
    } catch (e: Exception) {
        false
    }
}
