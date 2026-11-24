package com.arman.firefoxvpn

import android.content.Context
import android.util.Base64
import java.security.SecureRandom

/** Stores only an opaque local fixture ID. Neither the ID nor the key goes through Dart. */
internal object TunnelTestSession {
    private const val ID_BYTES = 32
    private val storage = KeystoreSessionStorage(
        fileName = "pol-tunnel-test.session",
        keyAlias = "pol.tunnel-test.session.v1",
        payloadBytes = ID_BYTES..ID_BYTES,
    )

    @Synchronized
    fun read(context: Context): String? = storage.read(context)?.let(::encode)

    @Synchronized
    fun exists(context: Context): Boolean {
        val id = storage.read(context) ?: return false
        id.fill(0)
        return true
    }

    @Synchronized
    fun create(context: Context): Boolean {
        if (exists(context)) return false
        val id = ByteArray(ID_BYTES).also(SecureRandom()::nextBytes)
        try {
            storage.write(context, id)
            return true
        } finally {
            id.fill(0)
        }
    }

    @Synchronized
    fun clear(context: Context) = storage.clear(context)

    private fun encode(id: ByteArray): String = try {
        Base64.encodeToString(id, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    } finally {
        id.fill(0)
    }
}
