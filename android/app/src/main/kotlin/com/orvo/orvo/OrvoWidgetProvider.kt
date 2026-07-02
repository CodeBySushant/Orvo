package com.orvo.orvo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver

/// 4x1 now-playing widget. Transport buttons broadcast media-key events to
/// audio_service's MediaButtonReceiver, so they control playback even when
/// the UI isn't open (the playback foreground service handles them).
class OrvoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context, null, null, false, -1L))
        }
    }

    companion object {
        fun push(
            context: Context,
            title: String,
            artist: String,
            playing: Boolean,
            albumId: Long
        ) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, OrvoWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val views = buildViews(context, title, artist, playing, albumId)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(
            context: Context,
            title: String?,
            artist: String?,
            playing: Boolean,
            albumId: Long
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.orvo_widget)
            views.setTextViewText(R.id.widget_title, title ?: "Orvo")
            views.setTextViewText(R.id.widget_artist, artist ?: "Tap to open")
            views.setImageViewResource(
                R.id.widget_play,
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play
            )
            if (albumId > 0) {
                views.setImageViewUri(
                    R.id.widget_art,
                    Uri.parse("content://media/external/audio/albumart/$albumId")
                )
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
