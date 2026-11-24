package com.arman.firefoxvpn

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.DataInputStream
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Stores only an opaque local fixture ID. Neither the ID nor the key goes through Dart. */
internal object TunnelTestSession {
    private const val ID_BYTES = 32
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private const val FORMAT = 1
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "pol.tunnel-test.session.v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private val associatedData = ALIAS.toByteArray(Charsets.UTF_8)

    @Synchronized
    fun read(context: Context): String? = readID(context)?.let(::encode)

    @Synchronized
    fun exists(context: Context): Boolean {
        val id = readID(context) ?: return false
        id.fill(0)
        return true
    }

    @Synchronized
    fun create(context: Context): Boolean {
        if (exists(context)) return false
        val id = ByteArray(ID_BYTES).also(SecureRandom()::nextBytes)
        try {
            val key = keyStore().getKey(ALIAS, null) as? SecretKey ?: generateKey()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.updateAAD(associatedData)
            val encrypted = cipher.doFinal(id)
            check(cipher.iv.size == IV_BYTES)
            val file = file(context)
            val output = file.startWrite()
            try {
                output.write(FORMAT)
                output.write(cipher.iv)
                output.write(encrypted)
                file.finishWrite(output)
            } catch (error: Exception) {
                file.failWrite(output)
                throw error
            }
            return true
        } finally {
            id.fill(0)
        }
    }

    @Synchronized
    fun clear(context: Context) {
        // Removing the key invalidates a residual ciphertext even if the filesystem rejects removal.
        keyStore().deleteEntry(ALIAS)
        file(context).delete()
    }

    private fun readID(context: Context): ByteArray? {
        val file = file(context)
        val input = try {
            DataInputStream(file.openRead())
        } catch (_: FileNotFoundException) {
            return null
        }
        input.use {
            check(it.readUnsignedByte() == FORMAT)
            val iv = ByteArray(IV_BYTES).also(it::readFully)
            val encrypted = ByteArray(ID_BYTES + TAG_BITS / Byte.SIZE_BITS).also(it::readFully)
            check(it.read() == -1)
            val key = keyStore().getKey(ALIAS, null) as? SecretKey
                ?: throw IllegalStateException("Fixture session key unavailable")
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            cipher.updateAAD(associatedData)
            return cipher.doFinal(encrypted)
        }
    }

    private fun encode(id: ByteArray): String = try {
        Base64.encodeToString(id, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    } finally {
        id.fill(0)
    }

    private fun file(context: Context): AtomicFile =
        AtomicFile(File(context.noBackupFilesDir, "pol-tunnel-test.session"))

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun generateKey(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
        }.generateKey()
}
