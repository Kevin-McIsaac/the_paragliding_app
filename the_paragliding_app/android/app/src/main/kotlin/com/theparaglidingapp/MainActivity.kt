package com.theparaglidingapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "the_paragliding_app/build_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGitCommit" -> {
                    result.success(BuildConfig.GIT_COMMIT)
                }
                "getGitBranch" -> {
                    result.success(BuildConfig.GIT_BRANCH)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
