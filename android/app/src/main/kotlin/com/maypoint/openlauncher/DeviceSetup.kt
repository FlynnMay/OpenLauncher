package com.maypoint.openlauncher

import android.content.Context
import dadb.AdbKeyPair
import dadb.Dadb
import java.io.File
import java.net.ConnectException
import java.net.SocketTimeoutException
import kotlinx.coroutines.delay

/**
 * One-press setup. Some of what the launcher needs can only be granted from
 * an ADB shell, so this connects to the TV's own ADB service, the way a
 * computer would, and runs the commands itself. The TV asks the user to allow
 * the connection the first time.
 */
class DeviceSetup(private val context: Context) {
    suspend fun run(): SetupResult {
        val pkg = context.packageName
        try {
            Dadb.create("127.0.0.1", ADB_PORT, keyPair(), CONNECT_TIMEOUT_MS, AUTH_TIMEOUT_MS)
                .use { adb ->
                    val grant = adb.shell("pm grant $pkg android.permission.WRITE_SECURE_SETTINGS")
                    if (grant.exitCode != 0) {
                        return SetupResult(SetupOutcome.FAILED, grant.allOutput.trim())
                    }
                    // TCL TVs refuse to start a third-party service without these;
                    // other TVs do not know the names and reject them, harmlessly.
                    // The uid-level mode is the one that matters: TCL resets the
                    // package-level mode to "ignore" on every boot.
                    for (op in listOf("AUTO_START", "ASSOC_START")) {
                        adb.shell("appops set --uid $pkg $op allow")
                        adb.shell("appops set $pkg $op allow")
                    }
                }
        } catch (e: Exception) {
            val causes = generateSequence<Throwable>(e) { it.cause }.toList()
            return when {
                causes.any { it is ConnectException } ->
                    SetupResult(SetupOutcome.ADB_UNAVAILABLE)
                causes.any { it is SocketTimeoutException } ->
                    SetupResult(SetupOutcome.NOT_AUTHORISED)
                else -> SetupResult(SetupOutcome.FAILED, e.message ?: e.javaClass.simpleName)
            }
        }
        // Off then on, with a pause the system can observe: a service that was
        // already on but had been refused is only retried when the setting changes.
        HomeButtonService.setEnabled(context, false)
        delay(SETTING_SETTLE_MS)
        HomeButtonService.setEnabled(context, true)
        return SetupResult(SetupOutcome.DONE)
    }

    /** This app's ADB identity, created once so the TV can remember allowing it. */
    private fun keyPair(): AdbKeyPair {
        val dir = File(context.filesDir, "adb").apply { mkdirs() }
        val privateKey = File(dir, "adbkey")
        val publicKey = File(dir, "adbkey.pub")
        if (!privateKey.exists() || !publicKey.exists()) {
            AdbKeyPair.generate(privateKey, publicKey)
        }
        return AdbKeyPair.read(privateKey, publicKey)
    }

    private companion object {
        const val ADB_PORT = 5555
        const val CONNECT_TIMEOUT_MS = 5_000

        // Long enough to read and answer the "Allow USB debugging?" prompt.
        const val AUTH_TIMEOUT_MS = 60_000
        const val SETTING_SETTLE_MS = 1_000L
    }
}
