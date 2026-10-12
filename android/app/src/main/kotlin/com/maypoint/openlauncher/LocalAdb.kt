package com.maypoint.openlauncher

import android.content.Context
import dadb.AdbKeyPair
import dadb.Dadb
import java.io.File
import java.net.ConnectException
import java.net.SocketTimeoutException

/**
 * A shell on the TV's own ADB service, reached the way a computer would
 * reach it. It can do what an ordinary app may not: grant permissions, stop
 * other apps. The TV asks the user to allow the connection the first time.
 */
internal object LocalAdb {
    private const val PORT = 5555
    private const val CONNECT_TIMEOUT_MS = 5_000

    /** Long enough to read and answer the "Allow USB debugging?" prompt. */
    const val PROMPT_TIMEOUT_MS = 60_000

    /** For actions that should just fail if the TV has not allowed us yet. */
    const val QUICK_TIMEOUT_MS = 4_000

    fun <T> use(context: Context, authTimeoutMs: Int, block: (Dadb) -> T): T =
        Dadb.create("127.0.0.1", PORT, keyPair(context), CONNECT_TIMEOUT_MS, authTimeoutMs)
            .use(block)

    /** Why a [use] threw: debugging off, not allowed, or something else. */
    fun failure(e: Exception): SetupResult {
        val causes = generateSequence<Throwable>(e) { it.cause }.toList()
        return when {
            causes.any { it is ConnectException } ->
                SetupResult(SetupOutcome.ADB_UNAVAILABLE)
            causes.any { it is SocketTimeoutException } ->
                SetupResult(SetupOutcome.NOT_AUTHORISED)
            else -> SetupResult(SetupOutcome.FAILED, e.message ?: e.javaClass.simpleName)
        }
    }

    /** This app's ADB identity, created once so the TV can remember allowing it. */
    private fun keyPair(context: Context): AdbKeyPair {
        val dir = File(context.filesDir, "adb").apply { mkdirs() }
        val privateKey = File(dir, "adbkey")
        val publicKey = File(dir, "adbkey.pub")
        if (!privateKey.exists() || !publicKey.exists()) {
            AdbKeyPair.generate(privateKey, publicKey)
        }
        return AdbKeyPair.read(privateKey, publicKey)
    }
}
