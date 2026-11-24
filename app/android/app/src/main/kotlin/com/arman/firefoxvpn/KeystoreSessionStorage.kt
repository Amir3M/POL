package com.arman.firefoxvpn

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.DataInputStream
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** A private file containing one AES-GCM payload. The key alias is also authenticated. */
internal class KeystoreSessionStorage(
    private val fileName: String,
    private val keyAlias: String,
    private val payloadBytes: IntRange,
) {
    private val associatedData = keyAlias.toByteArray(Charsets.UTF_8)

    @Synchronized
    fun read(context: Context): ByteArray? {
        val stream = try {
            file(context).openRead()
        } catch (_: FileNotFoundException) {
            return null
        }
        return stream.use {
            // Version byte, IV, encrypted payload, authentication tag.
            val length = stream.channel.size() - 1 - IV_BYTES - TAG_BYTES
            check(length in payloadBytes.first.toLong()..payloadBytes.last.toLong()) {
                "Invalid encrypted session size"
            }
            val input = DataInputStream(stream)
            check(input.readUnsignedByte() == FORMAT) { "Unsupported encrypted session format" }
            val iv = ByteArray(IV_BYTES).also(input::readFully)
            val encrypted = ByteArray(length.toInt() + TAG_BYTES).also(input::readFully)
            check(input.read() == -1) { "Unexpected encrypted session data" }

            val key = keyStore().getKey(keyAlias, null) as? SecretKey
                ?: throw IllegalStateException("Session key unavailable")
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            cipher.updateAAD(associatedData)
            cipher.doFinal(encrypted)
        }
    }

    @Synchronized
    fun write(context: Context, payload: ByteArray) {
        require(payload.size in payloadBytes) { "Invalid session payload size" }
        val key = keyStore().getKey(keyAlias, null) as? SecretKey ?: generateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(associatedData)
        val encrypted = cipher.doFinal(payload)
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
    }

    @Synchronized
    fun clear(context: Context) {
        // A residual file cannot be decrypted once its key is deleted.
        keyStore().deleteEntry(keyAlias)
        file(context).delete()
    }

    private fun file(context: Context): AtomicFile =
        AtomicFile(File(context.noBackupFilesDir, fileName))

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun generateKey(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
        }.generateKey()

    private companion object {
        const val FORMAT = 1
        const val IV_BYTES = 12
        const val TAG_BITS = 128
        const val TAG_BYTES = TAG_BITS / Byte.SIZE_BITS
        const val KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
