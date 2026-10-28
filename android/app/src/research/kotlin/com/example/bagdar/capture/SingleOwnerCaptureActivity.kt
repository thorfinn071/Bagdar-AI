package com.example.bagdar.capture

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView
import com.google.ar.core.ArCoreApk
import java.util.concurrent.atomic.AtomicBoolean

/** Native Research entry: no Flutter engine, guidance, models, microphone or SOS. */
class SingleOwnerCaptureActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var consent: CheckBox
    private lateinit var start: Button
    private lateinit var stop: Button
    private var recorder: SingleOwnerCaptureRecorder? = null
    private var foreground = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (20 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }
        status = TextView(this).apply {
            text = "Bagdar Research: запись RGB, raw depth, confidence и позы. " +
                "Стойте на месте. Снимайте только согласованную сцену без посторонних. " +
                "Данные останутся локально. Подсказки движения отключены."
        }
        consent = CheckBox(this).apply {
            text = "Я стою на месте и согласен сохранить эту сцену локально"
        }
        start = Button(this).apply {
            text = "Начать запись до 10 секунд"
            setOnClickListener { startCapture() }
        }
        stop = Button(this).apply {
            text = "Остановить и сохранить"
            isEnabled = false
            setOnClickListener { recorder?.stop("user_stop") }
        }
        layout.addView(status)
        layout.addView(consent)
        layout.addView(start)
        layout.addView(stop)
        setContentView(layout)
    }

    override fun onResume() {
        super.onResume()
        foreground = true
    }

    private fun startCapture() {
        if (!foreground || recorder != null) return
        if (!consent.isChecked) {
            status.text = "Для записи подтвердите неподвижность и согласие."
            return
        }
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 71)
            status.text = "После разрешения камеры нажмите «Начать» ещё раз."
            return
        }
        try {
            if (ArCoreApk.getInstance().requestInstall(this, true) == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                status.text = "После установки ARCore нажмите «Начать» ещё раз."
                return
            }
        } catch (error: Exception) {
            status.text = "ARCore недоступен: ${error.javaClass.simpleName}"
            return
        }
        if (!captureLease.compareAndSet(false, true)) {
            status.text = "Предыдущая запись ещё освобождает камеру. Дождитесь завершения."
            return
        }
        start.isEnabled = false
        consent.isEnabled = false
        stop.isEnabled = true
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val next = SingleOwnerCaptureRecorder(this) { message, finished ->
            runOnUiThread {
                if (finished) {
                    captureLease.set(false)
                    recorder = null
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                if (!isDestroyed) {
                    status.text = message
                    start.isEnabled = finished
                    consent.isEnabled = finished
                    stop.isEnabled = !finished
                    if (finished) consent.isChecked = false
                }
            }
        }
        recorder = next
        next.start()
    }

    override fun onPause() {
        foreground = false
        recorder?.stop("activity_background")
        super.onPause()
    }

    override fun onDestroy() {
        recorder?.stop("activity_destroyed")
        super.onDestroy()
    }

    companion object {
        // Holds across Activity recreation until the old worker has closed Session/GL.
        private val captureLease = AtomicBoolean(false)
    }
}
