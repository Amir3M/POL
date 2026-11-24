package com.arman.firefoxvpn

import android.content.Context
import java.io.IOException
import java.security.GeneralSecurityException

/** Native storage for a future authorized session. No provider path uses this store yet. */
internal object AuthorizedVpnSession {
    private const val MAX_BYTES = 65_536
    private val storage = KeystoreSessionStorage(
        fileName = "pol-authorized.session",
        keyAlias = "pol.authorized.session.v1",
        payloadBytes = 1..MAX_BYTES,
    )

    /** A missing session returns null. A damaged or unreadable session requires explicit reset. */
    fun read(context: Context): String? = try {
        storage.read(context)?.let { payload ->
            try {
                payload.decodeToString(throwOnInvalidSequence = true)
            } finally {
                payload.fill(0)
            }
        }
    } catch (_: GeneralSecurityException) {
        throw UnreadableSession()
    } catch (_: IOException) {
        throw UnreadableSession()
    } catch (_: IllegalStateException) {
        throw UnreadableSession()
    }

    fun write(context: Context, session: String) {
        require(session.length in 1..MAX_BYTES) { "Invalid session payload size" }
        val payload = session.encodeToByteArray(throwOnInvalidSequence = true)
        try {
            storage.write(context, payload)
        } finally {
            payload.fill(0)
        }
    }

    fun clear(context: Context) = storage.clear(context)

    class UnreadableSession : IllegalStateException("The encrypted Android session could not be read.")
}
