package com.orvo.orvo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver

/// 4x1 now-playing widget. Transport buttons broadcast media-key events to
/// audio_service's MediaButtonReceiver, so they control playback even when
/// the UI isn't open (the playback foreground service handles them).
///
/// FIX (#13): album art now arrives as raw bytes from the Flutter side and
/// is rendered with setImageViewBitmap. The previous content://.../albumart
/// URI approach failed on most launchers, which lack permission to read
/// media-store album art — art rendered blank.
class OrvoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                id, buildViews(context, null, null, false, null)
            )
        }
    }

    companion object {
        fun push(
            context: Context,
            title: String,
            artist: String,
            playing: Boolean,
            art: ByteArray?
        ) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, OrvoWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val views = buildViews(context, title, artist, playing, art)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(
            context: Context,
            title: String?,
            artist: String?,
            playing: Boolean,
            art: ByteArray?
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.orvo_widget)
            views.setTextViewText(R.id.widget_title, title ?: "Orvo")
            views.setTextViewText(R.id.widget_artist, artist ?: "Tap to open")
            views.setImageViewResource(
                R.id.widget_play,
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play
            )

            val bitmap: Bitmap? = art?.let {
                try {
                    BitmapFactory.decodeByteArray(it, 0, it.size)
                } catch (e: Exception) {
                    null
                }
            }
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_art, bitmap)
            } else {
                views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
            }

            views.setOnClickPendingIntent(
                R.id.widget_prev,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 1)
            )
            views.setOnClickPendingIntent(
                R.id.widget_play,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 2)
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT, 3)
            )

            // Tapping the body opens the app.
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context, 0, launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }
            return views
        }

        private fun mediaButton(
            context: Context,
            keyCode: Int,
            requestCode: Int
        ): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setClass(context, MediaButtonReceiver::class.java)
                .putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                )
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
