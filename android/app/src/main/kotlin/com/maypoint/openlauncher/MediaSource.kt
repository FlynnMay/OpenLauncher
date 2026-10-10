package com.maypoint.openlauncher

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.service.notification.StatusBarNotification
import java.io.File

/**
 * What other apps are playing, and the notifications they post. Both need
 * the access [NotificationService] stands for; without it there is simply
 * nothing to report.
 */
class MediaSource(
    private val context: Context,
    private val onNowPlayingChanged: () -> Unit,
    private val onNotification: (AppNotification) -> Unit,
) {
    private val manager = context.getSystemService(MediaSessionManager::class.java)
    private val component = NotificationService.component(context)
    private val artDir = File(context.cacheDir, "media")
    private var controller: MediaController? = null
    private var watchingSessions = false

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = onNowPlayingChanged()
        override fun onPlaybackStateChanged(state: PlaybackState?) = onNowPlayingChanged()
        override fun onSessionDestroyed() = attach()
    }

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { follow(it) }

    init {
        NotificationService.onConnected = { attach() }
        NotificationService.onPosted = { post(it) }
        attach()
    }

    fun dispose() {
        NotificationService.onConnected = null
        NotificationService.onPosted = null
        if (watchingSessions) manager?.removeOnActiveSessionsChangedListener(sessionsListener)
        controller?.unregisterCallback(callback)
        controller = null
    }

    /** Starts following media sessions; harmless to repeat, and to call before access is granted. */
    private fun attach() {
        val manager = manager ?: return
        try {
            if (!watchingSessions) {
                manager.addOnActiveSessionsChangedListener(sessionsListener, component)
                watchingSessions = true
            }
            follow(manager.getActiveSessions(component))
        } catch (e: SecurityException) {
            follow(null)
        }
    }

    /** Follows whichever session is playing, or failing that the most recent one. */
    private fun follow(sessions: List<MediaController>?) {
        val next = sessions?.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: sessions?.firstOrNull()
        if (next?.sessionToken != controller?.sessionToken) {
            controller?.unregisterCallback(callback)
            controller = next
            next?.registerCallback(callback)
        }
        onNowPlayingChanged()
    }

    /** Call off the main thread: writes the cover art to a file. */
    fun current(): NowPlaying? {
        val controller = controller ?: return null
        val metadata = controller.metadata
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
        val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
        val art = metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        return NowPlaying(
            packageName = controller.packageName,
            appLabel = appLabel(controller.packageName),
            title = title,
            artist = artist,
            artPath = art?.let {
                runCatching { cacheArt(it, "${controller.packageName}|$title|$artist") }.getOrNull()
            },
            playing = controller.playbackState?.state == PlaybackState.STATE_PLAYING,
        )
    }

    fun send(command: MediaCommand) {
        val controls = controller?.transportControls ?: return
        when (command) {
            MediaCommand.PLAY_PAUSE ->
                if (controller?.playbackState?.state == PlaybackState.STATE_PLAYING) {
                    controls.pause()
                } else {
                    controls.play()
                }
            MediaCommand.NEXT -> controls.skipToNext()
            MediaCommand.PREVIOUS -> controls.skipToPrevious()
        }
    }

    /** One file per track, named by what is playing so an unchanged track is not rewritten. */
    @Synchronized
    private fun cacheArt(art: Bitmap, key: String): String {
        artDir.mkdirs()
        val file = File(artDir, "art-${key.hashCode().toUInt().toString(36)}.png")
        if (!file.exists()) {
            val tmp = File(artDir, file.name + ".tmp")
            tmp.outputStream().use { art.compress(Bitmap.CompressFormat.PNG, 100, it) }
            tmp.renameTo(file)
        }
        artDir.listFiles()?.filter { it.name != file.name }?.forEach { it.delete() }
        return file.absolutePath
    }

    private fun post(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        // Progress bars, playback controls and group headers are not news.
        if (sbn.isOngoing || sbn.packageName == context.packageName) return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val title = notification.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = notification.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return
        onNotification(
            AppNotification(
                packageName = sbn.packageName,
                appLabel = appLabel(sbn.packageName),
                title = title,
                text = text,
            ),
        )
    }

    private fun appLabel(packageName: String): String = runCatching {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    }.getOrDefault(packageName)
}
