package rs.antonijevic.invoice2ips

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.text.Html
import com.googlecode.tesseract.android.TessBaseAPI
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Prijem slike, PDF dokumenta ili teksta podeljenog iz druge aplikacije (ACTION_SEND),
 * nativno renderovanje PDF stranica u slike pomoću Android PdfRenderer-a,
 * čitanje tekstualnog sloja PDF-a (pdfbox-android) i lokalni ćirilični OCR (Tesseract 4).
 */
class MainActivity : FlutterActivity() {

    companion object {
        private var sharedImage: ByteArray? = null
        private var sharedPayload: Map<String, Any?>? = null
        private val tesseractLock = Any()
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
                "getSharedPayload" -> {
                    result.success(sharedPayload)
                    sharedPayload = null
                    sharedImage = null
                }
                "renderPdfPages" -> {
                    val pdfBytes = pdfBytesArgument(call.argument<Any>("bytes"))
                    if (pdfBytes == null || pdfBytes.isEmpty()) {
                        result.success(emptyList<ByteArray>())
                        return@setMethodCallHandler
                    }
                    Thread {
                        val pages = renderPdfBytesToPngPages(pdfBytes)
                        runOnUiThread {
                            result.success(pages)
                        }
                    }.start()
                }
                "extractPdfText" -> {
                    val pdfBytes = pdfBytesArgument(call.argument<Any>("bytes"))
                    if (pdfBytes == null || pdfBytes.isEmpty()) {
                        result.success(emptyList<String>())
                        return@setMethodCallHandler
                    }
                    Thread {
                        val texts = extractPdfTextPages(pdfBytes)
                        runOnUiThread {
                            result.success(texts)
                        }
                    }.start()
                }
                "recognizeTextNative" -> {
                    val path = call.argument<String>("path")
                    val mode = call.argument<Int>("mode") ?: 0
                    if (path.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val ocrResult = recognizeTextWithTesseract(path, mode)
                        runOnUiThread {
                            result.success(ocrResult)
                        }
                    }.start()
                }
                "getAppSignatureSha1" -> {
                    result.success(getAppSignatureSha1())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pdfBytesArgument(raw: Any?): ByteArray? = when (raw) {
        is ByteArray -> raw
        is List<*> -> ByteArray(raw.size) { (raw[it] as Number).toByte() }
        else -> null
    }

    /**
     * Kopira ugrađeni srpski ćirilični Tesseract LSTM model (`assets/tessdata/srp.traineddata`)
     * u `filesDir/tessdata/srp.traineddata` pri prvom pozivu.
     */
    private fun ensureTessDataReady(): File? {
        return try {
            val tessDir = File(filesDir, "tessdata")
            if (!tessDir.exists()) {
                tessDir.mkdirs()
            }
            val targetFile = File(tessDir, "srp.traineddata")
            // Zvanični srp.traineddata je ~2.15 MB (2,149,931 bajtova).
            if (!targetFile.exists() || targetFile.length() < 2_000_000L) {
                val assetKey = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/tessdata/srp.traineddata")
                val tmpFile = File(tessDir, "srp.traineddata.tmp")
                assets.open(assetKey).use { input ->
                    tmpFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                if (tmpFile.length() >= 2_000_000L) {
                    if (targetFile.exists()) targetFile.delete()
                    tmpFile.renameTo(targetFile)
                }
            }
            if (targetFile.exists() && targetFile.length() >= 2_000_000L) {
                filesDir
            } else {
                android.util.Log.e("Invoice2IPS", "srp.traineddata nije pronađen ili je neispravne veličine")
                null
            }
        } catch (e: Throwable) {
            android.util.Log.e("Invoice2IPS", "ensureTessDataReady error: $e", e)
            null
        }
    }

    private data class DecodedBitmap(val bitmap: Bitmap, val coordScale: Double)

    /**
     * Učitava sliku sa diska, primenjuje EXIF orijentaciju i skalira tako da duža
     * strana bude između 2200px i 2800px (optimalno za sitan tekst uplatnice na celoj
     * stranici računa u Tesseract LSTM-u), uz morfološku normalizaciju pozadine papira (`tileMax`).
     * - `mode == 0`: `PSM_AUTO` (standardna detekcija kolona i tabela).
     * - `mode == 1`: `PSM_SPARSE_TEXT` fallback kada `PSM_AUTO` preskoči tekst unutar
     *   zatvorenih pravougaonih okvira (`Платилац:`, `Сврха уплате:`, `Прималац:`).
     */
    private fun decodeUprightBitmap(filePath: String, mode: Int): DecodedBitmap? {
        return try {
            val boundsOpts = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(filePath, boundsOpts)
            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

            val targetMax = 2800
            var sampleSize = 1
            val rawLongest = max(boundsOpts.outWidth, boundsOpts.outHeight)
            while ((rawLongest / (sampleSize * 2)) >= targetMax) {
                sampleSize *= 2
            }

            val opts = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            var bmp = BitmapFactory.decodeFile(filePath, opts) ?: return null

            val exif = try {
                ExifInterface(filePath)
            } catch (_: Exception) {
                null
            }
            val rotation = when (exif?.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            val uprightRawLongest = max(boundsOpts.outWidth, boundsOpts.outHeight).toDouble()
            if (rotation != 0f) {
                val matrix = Matrix().apply { postRotate(rotation) }
                val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                if (rotated !== bmp) bmp.recycle()
                bmp = rotated
            }

            val longest = max(bmp.width, bmp.height)
            if (longest in 1..1799) {
                val scale = 2200f / longest.toFloat()
                val scaled = Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * scale).roundToInt().coerceAtLeast(1),
                    (bmp.height * scale).roundToInt().coerceAtLeast(1),
                    true
                )
                if (scaled !== bmp) bmp.recycle()
                bmp = scaled
            } else if (longest > 3000) {
                val scale = targetMax.toFloat() / longest.toFloat()
                val scaled = Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * scale).roundToInt().coerceAtLeast(1),
                    (bmp.height * scale).roundToInt().coerceAtLeast(1),
                    true
                )
                if (scaled !== bmp) bmp.recycle()
                bmp = scaled
            }

            if (mode == 0 || mode == 1) {
                if (bmp.config != Bitmap.Config.ARGB_8888 || !bmp.isMutable) {
                    val argb = bmp.copy(Bitmap.Config.ARGB_8888, true)
                    bmp.recycle()
                    bmp = argb
                }
                normalizePaperBackground(bmp)
            } else if (bmp.config != Bitmap.Config.ARGB_8888) {
                val argb = bmp.copy(Bitmap.Config.ARGB_8888, false)
                bmp.recycle()
                bmp = argb
            }
            val finalLongest = max(bmp.width, bmp.height).coerceAtLeast(1).toDouble()
            DecodedBitmap(bmp, uprightRawLongest / finalLongest)
        } catch (e: Throwable) {
            android.util.Log.e("Invoice2IPS", "decodeUprightBitmap error: $e", e)
            null
        }
    }

    /**
     * Morfološka procena osvetljenja papira po blokovima (bez uticaja tamnih linija
     * i okvira tabela): za svaki blok od 32x32 piksela uzima se lokalni maksimum
     * svetline papira (2x2 prosek radi potiskivanja šuma), pa se pozadina glatko
     * interpolira. Time se uklanjaju senke na kameri bez izbeljivanja tankih slova
     * uz ivice boksova uplatnice.
     */
    private fun normalizePaperBackground(bmp: Bitmap) {
        val w = bmp.width
        val h = bmp.height
        if (w < 4 || h < 4) return

        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)

        val lums = IntArray(w * h)
        for (i in pixels.indices) {
            val c = pixels[i]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            lums[i] = (r * 77 + g * 150 + b * 29) shr 8
        }

        val tile = 32
        val gw = ((w + tile - 1) / tile).coerceAtLeast(1)
        val gh = ((h + tile - 1) / tile).coerceAtLeast(1)
        var grid = IntArray(gw * gh)

        for (gy in 0 until gh) {
            val yStart = gy * tile
            val yEnd = min(h - 1, yStart + tile - 1)
            for (gx in 0 until gw) {
                val xStart = gx * tile
                val xEnd = min(w - 1, xStart + tile - 1)
                var maxPair = 64
                var y = yStart
                while (y < yEnd) {
                    val row0 = y * w
                    val row1 = (y + 1) * w
                    var x = xStart
                    while (x < xEnd) {
                        val avg2x2 = (lums[row0 + x] + lums[row0 + x + 1] +
                            lums[row1 + x] + lums[row1 + x + 1]) shr 2
                        if (avg2x2 > maxPair) maxPair = avg2x2
                        x += 2
                    }
                    y += 2
                }
                grid[gy * gw + gx] = maxPair
            }
        }

        // Širimo vrednost svetlog papira u eventualne potpuno tamne blokove (npr. zaglavlje)
        repeat(2) {
            val next = grid.copyOf()
            for (gy in 0 until gh) {
                for (gx in 0 until gw) {
                    val v = grid[gy * gw + gx]
                    if (v >= 115) continue
                    var best = v
                    for (dy in -1..1) {
                        val ny = gy + dy
                        if (ny !in 0 until gh) continue
                        for (dx in -1..1) {
                            val nx = gx + dx
                            if (nx !in 0 until gw) continue
                            val nv = grid[ny * gw + nx]
                            if (nv > best) best = nv
                        }
                    }
                    next[gy * gw + gx] = best
                }
            }
            grid = next
        }

        // Blago zaglađivanje mreže pozadine (3x3 prosek) radi izbegavanja skokova između blokova
        val smoothed = IntArray(gw * gh)
        for (gy in 0 until gh) {
            for (gx in 0 until gw) {
                var sum = 0
                var count = 0
                for (dy in -1..1) {
                    val ny = gy + dy
                    if (ny !in 0 until gh) continue
                    for (dx in -1..1) {
                        val nx = gx + dx
                        if (nx !in 0 until gw) continue
                        sum += grid[ny * gw + nx]
                        count++
                    }
                }
                smoothed[gy * gw + gx] = (sum / count).coerceAtLeast(80)
            }
        }

        for (y in 0 until h) {
            val fy = (y.toFloat() + 0.5f) / tile - 0.5f
            val gy0 = floor(fy).toInt().coerceIn(0, gh - 1)
            val gy1 = (gy0 + 1).coerceAtMost(gh - 1)
            val ty = (fy - gy0).coerceIn(0f, 1f)
            val rowOffset = y * w
            val gRow0 = gy0 * gw
            val gRow1 = gy1 * gw

            for (x in 0 until w) {
                val fx = (x.toFloat() + 0.5f) / tile - 0.5f
                val gx0 = floor(fx).toInt().coerceIn(0, gw - 1)
                val gx1 = (gx0 + 1).coerceAtMost(gw - 1)
                val tx = (fx - gx0).coerceIn(0f, 1f)

                val c00 = smoothed[gRow0 + gx0]
                val c10 = smoothed[gRow0 + gx1]
                val c01 = smoothed[gRow1 + gx0]
                val c11 = smoothed[gRow1 + gx1]
                val top = c00 + (c10 - c00) * tx
                val bot = c01 + (c11 - c01) * tx
                val paperBg = (top + (bot - top) * ty).roundToInt().coerceAtLeast(80)
                val norm = ((lums[rowOffset + x] * 255) / paperBg).coerceIn(0, 255)

                // Na čistim digitalnim slikama (paperBg >= 238) čuvamo pune anti-alias polu-tonove;
                // na fotografijama papira i kamerama (paperBg < 238) istežemo kontrast u odnosu na
                // stvarnu svetlinu papira (bez uticaja tamnih okvira tabela).
                val outGray = if (paperBg >= 238) {
                    norm
                } else {
                    when {
                        norm >= 227 -> 255
                        norm <= 115 -> 0
                        else -> ((norm - 115) * 255) / (227 - 115)
                    }
                }
                pixels[rowOffset + x] = (0xFF shl 24) or (outGray shl 16) or (outGray shl 8) or outGray
            }
        }

        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
    }

    /**
     * Izvršava lokalni ćirilični OCR pomoću Tesseract 4 LSTM modela (`srp.traineddata`)
     * i vraća pun tekst zajedno sa segmentima linija i njihovim koordinatama (`left`, `top`, `right`, `bottom`)
     * iz hOCR izlaza radi geometrijske rekonstrukcije kolona i redova tabele.
     */
    private fun recognizeTextWithTesseract(filePath: String, mode: Int = 0): Map<String, Any>? {
        synchronized(tesseractLock) {
            val dataParent = ensureTessDataReady() ?: return null
            val decoded = decodeUprightBitmap(filePath, mode) ?: return null
            val bitmap = decoded.bitmap
            val coordScale = decoded.coordScale
            val tess = TessBaseAPI()
            try {
                val initialized = tess.init(
                    dataParent.absolutePath,
                    "srp",
                    TessBaseAPI.OEM_LSTM_ONLY
                )
                if (!initialized) {
                    return null
                }
                tess.pageSegMode = if (mode == 1) {
                    TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT
                } else {
                    TessBaseAPI.PageSegMode.PSM_AUTO
                }
                // Parametri za fotografije sa prave kamere:
                // - user_defined_dpi=300: sprečava pogrešnu procenu veličine fonta (default je 70 dpi)
                // - tessedit_do_invert=0: računi su taman tekst na svetloj podlozi (sprečava inverziju osenčenih boksova)
                tess.setVariable("user_defined_dpi", "300")
                tess.setVariable("tessedit_do_invert", "0")
                tess.setImage(bitmap)

                val fullText = tess.utF8Text ?: ""
                val hocr = tess.getHOCRText(0) ?: ""

                val lineHeaderRegex = Regex(
                    """<span\s+class=['"](?:ocr_line|ocr_header|ocr_caption|ocr_textfloat)['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+);[^'"]*['"][^>]*>""",
                    RegexOption.IGNORE_CASE
                )
                val wordRegex = Regex(
                    """<span\s+class=['"]ocrx_word['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+);[^'"]*['"][^>]*>(.*?)</span>""",
                    setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE)
                )
                val tagStripRegex = Regex("""<[^>]+>""")
                val lines = mutableListOf<Map<String, Any>>()

                fun decodeHtmlText(raw: String): String {
                    val stripped = raw.replace(tagStripRegex, " ")
                    val decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        Html.fromHtml(stripped, Html.FROM_HTML_MODE_LEGACY).toString()
                    } else {
                        @Suppress("DEPRECATION")
                        Html.fromHtml(stripped).toString()
                    }
                    return decoded.replace(Regex("""\s+"""), " ").trim()
                }

                val lineHeaders = lineHeaderRegex.findAll(hocr).toList()
                for (idx in lineHeaders.indices) {
                    val match = lineHeaders[idx]
                    val lineLeft = match.groupValues[1].toDoubleOrNull() ?: continue
                    val lineTop = match.groupValues[2].toDoubleOrNull() ?: continue
                    val lineRight = match.groupValues[3].toDoubleOrNull() ?: continue
                    val lineBottom = match.groupValues[4].toDoubleOrNull() ?: continue
                    val chunkStart = match.range.last + 1
                    val chunkEnd = if (idx + 1 < lineHeaders.size) {
                        lineHeaders[idx + 1].range.first
                    } else {
                        hocr.length
                    }
                    val innerHtml = hocr.substring(chunkStart, chunkEnd)

                    // Razdvoji reči u istoj liniji kada postoji horizontalni razmak između
                    // susednih kolona uplatnice ili tabele, tako da svaka ćelija zadrži sopstveni bbox.
                    val wordMatches = wordRegex.findAll(innerHtml).toList()
                    if (wordMatches.isNotEmpty()) {
                        var segWords = mutableListOf<String>()
                        var segLeft = 0.0
                        var segTop = 0.0
                        var segRight = 0.0
                        var segBottom = 0.0
                        var wordHeightSum = 0.0

                        fun flushSegment() {
                            val text = segWords.joinToString(" ").trim()
                            if (text.isNotEmpty()) {
                                lines.add(
                                    mapOf(
                                        "text" to text,
                                        "left" to segLeft * coordScale,
                                        "top" to segTop * coordScale,
                                        "right" to segRight * coordScale,
                                        "bottom" to segBottom * coordScale
                                    )
                                )
                            }
                            segWords = mutableListOf()
                            wordHeightSum = 0.0
                        }

                        for (wm in wordMatches) {
                            val wLeft = wm.groupValues[1].toDoubleOrNull() ?: continue
                            val wTop = wm.groupValues[2].toDoubleOrNull() ?: continue
                            val wRight = wm.groupValues[3].toDoubleOrNull() ?: continue
                            val wBottom = wm.groupValues[4].toDoubleOrNull() ?: continue
                            val wText = decodeHtmlText(wm.groupValues[5])
                            if (wText.isEmpty()) continue

                            val wWidth = max(1.0, wRight - wLeft)
                            val wHeight = max(1.0, wBottom - wTop)
                            // Ignoriši artefakte vertikalnih/horizontalnih linija tabele i okvira uplatnice
                            // kako ne bi premostili prazninu između leve i desne kolone.
                            val isBorderArtifact = wText.all { it in "|¦[]_—~\\/" } ||
                                ((wText == "I" || wText == "l" || wText == "1" || wText == "!") &&
                                    wHeight > wWidth * 5.0)
                            if (isBorderArtifact) continue

                            if (segWords.isEmpty()) {
                                segWords.add(wText)
                                segLeft = wLeft
                                segTop = wTop
                                segRight = wRight
                                segBottom = wBottom
                                wordHeightSum = wHeight
                            } else {
                                // Koristimo prosečnu visinu reči umesto (segBottom - segTop) jer blagi
                                // nagib kamere (2-4°) povećava ukupni vertikalni raspon celog segmenta.
                                val avgWordHeight = max(1.0, wordHeightSum / segWords.size)
                                val gap = wLeft - segRight
                                if (gap > max(avgWordHeight * 1.65, 18.0)) {
                                    flushSegment()
                                    segWords.add(wText)
                                    segLeft = wLeft
                                    segTop = wTop
                                    segRight = wRight
                                    segBottom = wBottom
                                    wordHeightSum = wHeight
                                } else {
                                    segWords.add(wText)
                                    segTop = min(segTop, wTop)
                                    segRight = max(segRight, wRight)
                                    segBottom = max(segBottom, wBottom)
                                    wordHeightSum += wHeight
                                }
                            }
                        }
                        flushSegment()
                    } else {
                        val cleanLine = decodeHtmlText(innerHtml)
                        if (cleanLine.isNotEmpty()) {
                            lines.add(
                                mapOf(
                                    "text" to cleanLine,
                                    "left" to lineLeft * coordScale,
                                    "top" to lineTop * coordScale,
                                    "right" to lineRight * coordScale,
                                    "bottom" to lineBottom * coordScale
                                )
                            )
                        }
                    }
                }

                val segmentedText = if (lines.isNotEmpty()) {
                    lines.joinToString("\n") { it["text"] as String }
                } else {
                    fullText
                }

                return mapOf(
                    "text" to segmentedText,
                    "lines" to lines
                )
            } catch (e: Throwable) {
                android.util.Log.e("Invoice2IPS", "recognizeTextWithTesseract error: $e", e)
                return null
            } finally {
                try {
                    tess.recycle()
                } catch (_: Throwable) {}
                try {
                    bitmap.recycle()
                } catch (_: Throwable) {}
            }
        }
    }

    /**
     * Čita tekstualni sloj PDF-a za iste stranice koje se renderuju (sve do 3,
     * inače 1, 2. i poslednju). PDF računi (npr. EPS) obično imaju tačan tekst
     * na ćirilici, koji lokalni OCR (samo latinica) ne može da pročita sa slike.
     * Skenirani PDF bez tekstualnog sloja vraća prazne stringove.
     */
    private fun extractPdfTextPages(pdfBytes: ByteArray): List<String> {
        return try {
            PDFBoxResourceLoader.init(applicationContext)
            PDDocument.load(pdfBytes).use { document ->
                val count = document.numberOfPages
                val indices = if (count <= 3) (0 until count).toList() else listOf(0, 1, count - 1)
                val stripper = PDFTextStripper()
                indices.map { index ->
                    stripper.startPage = index + 1
                    stripper.endPage = index + 1
                    stripper.getText(document)
                }
            }
        } catch (_: Throwable) {
            // Zaključan ili neispravan PDF — Dart strana nastavlja sa QR/OCR/AI tokom.
            emptyList()
        }
    }

    /**
     * Renderuje stranice PDF dokumenta u PNG slike visoke rezolucije (~3000px po dužoj strani,
     * da i sitan IPS QR kod na strani ima dovoljno piksela po modulu za ML Kit)
     * sa belom pozadinom, pogodne za QR skener, lokalni OCR i prikaz u aplikaciji.
     */
    private fun renderPdfBytesToPngPages(pdfBytes: ByteArray): List<ByteArray> {
        var tempFile: File? = null
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        val outputPages = mutableListOf<ByteArray>()

        try {
            tempFile = File.createTempFile("invoice_pdf_", ".pdf", cacheDir)
            tempFile.writeBytes(pdfBytes)
            pfd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(pfd)

            val count = renderer.pageCount
            if (count <= 0) return emptyList()

            // Za višestranične račune (npr. EPS/telekom) uplatnica i QR su na 1, 2. ili poslednjoj strani.
            val indices = if (count <= 3) {
                (0 until count).toList()
            } else {
                listOf(0, 1, count - 1)
            }

            for (index in indices) {
                renderer.openPage(index).use { page ->
                    val maxDim = max(page.width, page.height).coerceAtLeast(1)
                    val scale = max(3000f / maxDim.toFloat(), 2.0f).coerceAtMost(4.0f)
                    val width = (page.width * scale).roundToInt().coerceAtLeast(1)
                    val height = (page.height * scale).roundToInt().coerceAtLeast(1)

                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    // PDF stranice nemaju podrazumevanu pozadinu — popuni belom bojom radi QR/OCR čitljivosti.
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)

                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    bitmap.recycle()
                    outputPages.add(out.toByteArray())
                }
            }
        } catch (_: Exception) {
            // U slučaju neispravnog ili zaključanog PDF-a vraća ono što je do sada uspešno renderovano.
        } finally {
            try {
                renderer?.close()
            } catch (_: Exception) {}
            try {
                pfd?.close()
            } catch (_: Exception) {}
            try {
                tempFile?.delete()
            } catch (_: Exception) {}
        }

        return outputPages
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
        setIntent(intent)
        handleSendIntent(intent)
    }

    private fun handleSendIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE && action != Intent.ACTION_VIEW) return

        @Suppress("DEPRECATION")
        val streamUri: Uri? = (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }) ?: runCatching {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.firstOrNull()
        }.getOrNull() ?: intent.getStringExtra(Intent.EXTRA_STREAM)?.let {
            runCatching { Uri.parse(it) }.getOrNull()
        }

        val clipUri: Uri? = if (intent.clipData != null && intent.clipData!!.itemCount > 0) {
            intent.clipData!!.getItemAt(0).uri
        } else {
            null
        }
        val dataUri: Uri? = intent.data
        // Prioritet: clipUri (gde sistem obično delegira URI permission) -> streamUri -> dataUri
        val uri: Uri? = clipUri ?: streamUri ?: dataUri

        val rawMime = intent.type ?: uri?.let {
            try {
                contentResolver.getType(it)
            } catch (_: Exception) {
                null
            }
        } ?: ""

        val uriString = uri?.toString()?.lowercase() ?: ""
        var isPdf = rawMime.contains("pdf", ignoreCase = true) || uriString.contains(".pdf")
        var isImage = rawMime.startsWith("image/") ||
                listOf(".png", ".jpg", ".jpeg", ".webp").any { uriString.contains(it) }

        android.util.Log.i(
            "Invoice2IPS",
            "handleSendIntent: action=$action, rawMime=$rawMime, uri=$uri, isPdf=$isPdf, isImage=$isImage"
        )

        try {
            val bytes = if (uri != null) {
                try {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (e: Exception) {
                    android.util.Log.w("Invoice2IPS", "openInputStream nije uspeo ($e), probam openFileDescriptor...")
                    try {
                        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                            FileInputStream(pfd.fileDescriptor).use { it.readBytes() }
                        }
                    } catch (e2: Exception) {
                        android.util.Log.w("Invoice2IPS", "openFileDescriptor nije uspeo: $e2")
                        if (uri.scheme == "file") {
                            val file = File(uri.path ?: "")
                            if (file.exists() && file.canRead()) file.readBytes() else null
                        } else {
                            null
                        }
                    }
                }
            } else {
                null
            }

            if (bytes != null && bytes.isNotEmpty()) {
                // Magic byte provera za 100% tačnu detekciju formata
                val isPdfMagic = bytes.size >= 4 &&
                        bytes[0] == 0x25.toByte() && // %
                        bytes[1] == 0x50.toByte() && // P
                        bytes[2] == 0x44.toByte() && // D
                        bytes[3] == 0x46.toByte()    // F
                val isPngMagic = bytes.size >= 8 &&
                        bytes[0] == 0x89.toByte() &&
                        bytes[1] == 0x50.toByte() &&
                        bytes[2] == 0x4E.toByte() &&
                        bytes[3] == 0x47.toByte()
                val isJpgMagic = bytes.size >= 3 &&
                        bytes[0] == 0xFF.toByte() &&
                        bytes[1] == 0xD8.toByte() &&
                        bytes[2] == 0xFF.toByte()

                if (isPdfMagic) {
                    isPdf = true
                    isImage = false
                } else if (isPngMagic || isJpgMagic) {
                    isImage = true
                    isPdf = false
                }

                if (isPdf) {
                    android.util.Log.i("Invoice2IPS", "Uspesno ucitan deljeni PDF: ${bytes.size} bajtova")
                    sharedPayload = mapOf("type" to "pdf", "bytes" to bytes)
                } else if (isImage) {
                    android.util.Log.i("Invoice2IPS", "Uspesno ucitana deljena slika: ${bytes.size} bajtova")
                    sharedImage = bytes
                    sharedPayload = mapOf("type" to "image", "bytes" to bytes)
                } else {
                    android.util.Log.w("Invoice2IPS", "Nepoznat binarni format fajla (${bytes.size} bajtova)")
                }
            } else {
                val extraText = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!extraText.isNullOrBlank()) {
                    android.util.Log.i("Invoice2IPS", "Uspesno ucitan deljeni tekst iz EXTRA_TEXT")
                    sharedPayload = mapOf("type" to "text", "text" to extraText)
                } else if (rawMime.startsWith("text/") && uri != null) {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        val text = stream.readBytes().toString(Charsets.UTF_8)
                        if (text.isNotBlank()) {
                            android.util.Log.i("Invoice2IPS", "Uspesno ucitan deljeni tekst iz URI-ja")
                            sharedPayload = mapOf("type" to "text", "text" to text)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("Invoice2IPS", "Greska pri ucitavanju deljenog sadrzaja: $e", e)
        }

        // Ukloni extras i data da se ne obrade ponovo pri recreate-u
        intent.data = null
        intent.clipData = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.removeExtra(Intent.EXTRA_TEXT)
    }
}
