package com.theparaglidingapp

import java.io.*
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/**
 * Utility class for compressing and decompressing IGC files for backup purposes.
 * Provides transparent compression during backup while keeping original files uncompressed on device.
 */
class IGCCompressionHelper {

    companion object {
        private const val TAG = "IGCCompressionHelper"

        /**
         * Compresses IGC file content using GZIP compression.
         * Typically achieves 4-5x compression ratio for IGC files.
         *
         * @param igcContent The original IGC file content as string
         * @return Compressed byte array
         */
        fun compressIGC(igcContent: String): ByteArray {
            return ByteArrayOutputStream().use { baos ->
                GZIPOutputStream(baos).use { gzip ->
                    gzip.write(igcContent.toByteArray(Charsets.UTF_8))
                }
                baos.toByteArray()
            }
        }

        /**
         * Decompresses GZIP compressed IGC data back to original content.
         *
         * @param compressedData The compressed byte array
         * @return Original IGC file content as string
         */
        fun decompressIGC(compressedData: ByteArray): String {
            return GZIPInputStream(compressedData.inputStream()).use { gzip ->
                gzip.bufferedReader(Charsets.UTF_8).readText()
            }
        }

        /**
         * Reads and compresses an IGC file from the file system.
         *
         * @param file The IGC file to compress
         * @return Compressed byte array
         * @throws IOException if file cannot be read
         */
        fun compressIGCFile(file: File): ByteArray {
            if (!file.exists()) {
                throw FileNotFoundException("IGC file not found: ${file.absolutePath}")
            }

            val content = file.readText(Charsets.UTF_8)
            return compressIGC(content)
        }

        /**
         * Decompresses IGC data and writes it to a file.
         *
         * @param compressedData The compressed byte array
         * @param outputFile The file to write decompressed content to
         * @throws IOException if file cannot be written
         */
        fun decompressToFile(compressedData: ByteArray, outputFile: File) {
            val content = decompressIGC(compressedData)
            outputFile.parentFile?.mkdirs()
            outputFile.writeText(content, Charsets.UTF_8)
        }

        /**
         * Calculates compression ratio for informational purposes.
         *
         * @param originalSize Size of original data in bytes
         * @param compressedSize Size of compressed data in bytes
         * @return Compression ratio (e.g., 4.2 means 4.2x compression)
         */
        fun calculateCompressionRatio(originalSize: Long, compressedSize: Long): Double {
            return if (compressedSize > 0) originalSize.toDouble() / compressedSize.toDouble() else 0.0
        }
    }
}
