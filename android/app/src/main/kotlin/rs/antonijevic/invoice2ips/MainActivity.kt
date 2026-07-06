package rs.antonijevic.invoice2ips

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Prijem slike podeljene iz druge aplikacije (ACTION_SEND, mime "image").
 * Bajtovi se čuvaju statički dok ih Flutter strana ne preuzme preko
 * MethodChannel-a "rs.antonijevic.invoice2ips/shared" (getSharedImage),
 * nakon čega se brišu — ista slika se ne obrađuje dvaput.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private var sharedImage: ByteArray? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rs.antonijevic.invoice2ips/shared"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedImage" -> {
                    result.success(sharedImage)
                    sharedImage = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleSendIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleSendIntent(intent)
    }

    private fun handleSendIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("image/") != true) return

        @Suppress("DEPRECATION")
        val uri: Uri? = if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        if (uri == null) return

        try {
            contentResolver.openInputStream(uri)?.use { stream ->
                sharedImage = stream.readBytes()
            }
        } catch (_: Exception) {
            // Slika nije dostupna — ignoriši, aplikacija se normalno otvara.
        }

        // Ukloni EXTRA_STREAM da se ne obradi ponovo pri recreate-u.
        intent.removeExtra(Intent.EXTRA_STREAM)
    }
}
