package com.theparaglidingapp

import android.app.backup.BackupAgentHelper
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FileBackupHelper
import android.app.backup.SharedPreferencesBackupHelper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.*
import java.nio.file.Files
import java.nio.file.Paths

/**
 * Custom backup agent that handles compressed backup of IGC files while keeping
 * the database and preferences backup using standard Android backup helpers.
 *
 * IGC files are compressed during backup (4-5x reduction) but remain uncompressed
 * on the device for fast access during normal operation.
 */
class IGCBackupAgent : BackupAgentHelper() {

    companion object {
        private const val TAG = "IGCBackupAgent"
        private const val PREFS_BACKUP_KEY = "prefs"
        private const val FILES_BACKUP_KEY = "files"
        private const val IGC_BACKUP_KEY = "igc_files"

        // Actual IGC file locations used by this app
        private val IGC_DIRECTORIES = arrayOf(
            "igc_tracks",     // This is where IGC files are actually stored
            "igc_files",      // Legacy location
            "imported_igc",   // Alternative location
            "flight_tracks"   // Alternative location
        )

        /**
         * Data class to hold IGC compression statistics for diagnostic purposes
         */
        data class IGCBackupStats(
            val fileCount: Int,
            val originalSizeBytes: Long,
            val compressedSizeBytes: Long,
            val compressionRatio: Double,
            val estimatedBackupSizeMB: Double
        )


        /**
         * Helper method to find IGC files - made static for testing
         */
        private fun findIGCFilesInDir(filesDir: File): List<File> {
            val igcFiles = mutableListOf<File>()

            for (dirName in IGC_DIRECTORIES) {
                val dir = File(filesDir, dirName)
                if (dir.exists() && dir.isDirectory) {
                    dir.listFiles { file ->
                        file.isFile && (file.extension.equals("igc", ignoreCase = true))
                    }?.let { files ->
                        igcFiles.addAll(files)
                        Log.d(TAG, "Found ${files.size} IGC files in $dirName")
                    }
                }
            }

            return igcFiles
        }
    }

    override fun onCreate() {
        Log.d(TAG, "IGCBackupAgent onCreate - setting up backup helpers")

        // Set up standard backup helpers for preferences and database
        val prefsHelper = SharedPreferencesBackupHelper(this,
            packageName + "_preferences",
            "FlutterSharedPreferences"
        )
        addHelper(PREFS_BACKUP_KEY, prefsHelper)

        // Database files are handled by full backup rules (backup_rules.xml)
        Log.d(TAG, "Backup helpers configured")
    }

    override fun onBackup(
        oldState: ParcelFileDescriptor?,
        data: BackupDataOutput,
        newState: ParcelFileDescriptor
    ) {
        Log.d(TAG, "Starting backup process with IGC compression")

        // First, run the standard backup for prefs and database
        super.onBackup(oldState, data, newState)

        // Then handle IGC files with compression
        backupIGCFiles(data)

        Log.d(TAG, "Backup process completed")
    }

    override fun onRestore(
        data: BackupDataInput,
        appVersionCode: Int,
        newState: ParcelFileDescriptor
    ) {
        Log.d(TAG, "Starting restore process")

        // First restore standard data
        super.onRestore(data, appVersionCode, newState)

        // Then handle compressed IGC files
        restoreIGCFiles(data)

        Log.d(TAG, "Restore process completed")
    }

    private fun backupIGCFiles(data: BackupDataOutput) {
        try {
            val igcFiles = findIGCFiles()
            Log.d(TAG, "Found ${igcFiles.size} IGC files to backup")

            for ((index, file) in igcFiles.withIndex()) {
                try {
                    val compressed = IGCCompressionHelper.compressIGCFile(file)
                    val key = "igc_$index:${file.name}"

                    data.writeEntityHeader(key, compressed.size)
                    data.writeEntityData(compressed, compressed.size)

                    val ratio = IGCCompressionHelper.calculateCompressionRatio(
                        file.length(),
                        compressed.size.toLong()
                    )
                    Log.d(TAG, "Backed up ${file.name}: ${file.length()} -> ${compressed.size} bytes (${String.format("%.1f", ratio)}x compression)")

                } catch (e: Exception) {
                    Log.e(TAG, "Failed to backup IGC file: ${file.name}", e)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error during IGC files backup", e)
        }
    }

    private fun restoreIGCFiles(data: BackupDataInput) {
        try {
            var totalRestored = 0

            while (data.readNextHeader()) {
                val key = data.key

                if (key.startsWith("igc_")) {
                    try {
                        val size = data.dataSize
                        val compressedData = ByteArray(size)
                        data.readEntityData(compressedData, 0, size)

                        // Extract filename from key (format: "igc_0:filename.igc")
                        val filename = key.substringAfter(":")
                        val outputFile = File(filesDir, "igc_files/$filename")

                        IGCCompressionHelper.decompressToFile(compressedData, outputFile)
                        totalRestored++

                        Log.d(TAG, "Restored IGC file: $filename (${compressedData.size} -> ${outputFile.length()} bytes)")

                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to restore IGC file from key: $key", e)
                    }
                }
            }

            Log.d(TAG, "Successfully restored $totalRestored IGC files")

        } catch (e: Exception) {
            Log.e(TAG, "Error during IGC files restore", e)
        }
    }

    private fun findIGCFiles(): List<File> {
        return findIGCFilesInDir(filesDir)
    }
}
