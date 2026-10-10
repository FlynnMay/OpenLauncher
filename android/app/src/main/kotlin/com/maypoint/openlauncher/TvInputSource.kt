package com.maypoint.openlauncher

import android.content.Context
import android.content.Intent
import android.media.tv.TvContract
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import android.os.Handler
import android.os.Looper

/** The TV's own inputs (HDMI ports, tuner, ...) via the TV Input Framework. */
class TvInputSource(
    private val context: Context,
    private val onChanged: () -> Unit,
) {
    // Null on devices without the TV Input Framework.
    private val manager = context.getSystemService(Context.TV_INPUT_SERVICE) as? TvInputManager

    private val callback = object : TvInputManager.TvInputCallback() {
        override fun onInputAdded(inputId: String) = onChanged()
        override fun onInputRemoved(inputId: String) = onChanged()
        override fun onInputUpdated(inputId: String) = onChanged()
        override fun onTvInputInfoUpdated(inputInfo: TvInputInfo) = onChanged()
    }

    init {
        manager?.registerCallback(callback, Handler(Looper.getMainLooper()))
    }

    fun dispose() {
        manager?.unregisterCallback(callback)
    }

    fun list(): List<TvInput> =
        manager?.tvInputList.orEmpty()
            .filter { isPhysical(it) && !it.isHidden(context) }
            .map { info ->
                TvInput(
                    id = info.id,
                    label = (info.loadCustomLabel(context) ?: info.loadLabel(context)).toString(),
                    kind = when (info.type) {
                        TvInputInfo.TYPE_HDMI -> TvInputKind.HDMI
                        TvInputInfo.TYPE_TUNER -> TvInputKind.TUNER
                        TvInputInfo.TYPE_COMPOSITE,
                        TvInputInfo.TYPE_COMPONENT,
                        TvInputInfo.TYPE_SVIDEO,
                        TvInputInfo.TYPE_SCART -> TvInputKind.ANALOG
                        else -> TvInputKind.OTHER
                    },
                )
            }

    fun switchTo(inputId: String) {
        val info = manager?.getTvInputInfo(inputId)
            ?: throw FlutterError("unknown-input", "No TV input $inputId")
        // The MIME type is set explicitly: the TV app's filter matches on it,
        // and without it the intent can resolve to an unrelated app.
        val intent = Intent(Intent.ACTION_VIEW).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (info.isPassthroughInput) {
            intent.setDataAndType(
                TvContract.buildChannelUriForPassthroughInput(inputId),
                TvContract.Channels.CONTENT_ITEM_TYPE,
            )
        } else {
            intent.setDataAndType(
                TvContract.buildChannelsUriForInput(inputId),
                TvContract.Channels.CONTENT_TYPE,
            )
        }
        context.startActivity(intent)
    }

    /**
     * Apps can register inputs too (channel apps, video previews); only ports on
     * the TV itself become cards. Hardware input ids end in "/HW<deviceId>".
     */
    private fun isPhysical(info: TvInputInfo) =
        info.isPassthroughInput || HARDWARE_ID.containsMatchIn(info.id)

    private companion object {
        val HARDWARE_ID = Regex("/HW\\d+$")
    }
}
