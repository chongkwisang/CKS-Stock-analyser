package com.cks.cks_stock_analyser

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Persist the claude.ai sign-in right away, so it survives the app
    // being closed shortly after signing in.
    override fun onPause() {
        super.onPause()
        CookieManager.getInstance().flush()
    }

    override fun onStop() {
        super.onStop()
        CookieManager.getInstance().flush()
    }
}
