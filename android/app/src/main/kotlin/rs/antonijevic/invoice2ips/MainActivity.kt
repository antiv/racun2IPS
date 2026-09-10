package rs.antonijevic.invoice2ips

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

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
                "getAppSignatureSha1" -> {
                    result.success(getAppSignatureSha1())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getAppSignatureSha1(): String? {
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
                packageInfo.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }
            val cert = signatures?.firstOrNull()?.toByteArray() ?: return null
            val md = MessageDigest.getInstance("SHA-1")
            val digest = md.digest(cert)
            digest.joinToString("") { "%02X".format(it) }
        } catch (_: Exception) {
            null
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
