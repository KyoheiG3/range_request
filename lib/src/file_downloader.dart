import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'cancel_token.dart';
import 'exceptions.dart';
import 'models.dart';
import 'range_request_client.dart';

/// File download functionality for RangeRequestClient
class FileDownloader {
  final RangeRequestClient client;

  const FileDownloader([this.client = const RangeRequestClient()]);

  /// Create a FileDownloader with a new RangeRequestClient using the provided config
  factory FileDownloader.fromConfig(RangeRequestConfig config) {
    return FileDownloader(RangeRequestClient(config: config));
  }

  /// Clean up all temporary files in the specified directory
  Future<int> cleanupTempFiles(
    String directory, {
    String? tempFileExtension,
    Duration? olderThan,
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      return 0;
    }

    // Use provided extension or fall back to config
    final extension = tempFileExtension ?? client.config.tempFileExtension;

    var deletedCount = 0;
    final now = DateTime.now();

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(extension)) {
        // Check age if specified
        if (olderThan != null) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age < olderThan) {
            continue; // Skip files newer than threshold
          }
        }

        try {
          await entity.delete();
          deletedCount++;
        } catch (e) {
          // Continue with other files even if one fails
        }
      }
    }

    return deletedCount;
  }

  /// Downloads content directly to a file with optional progress callback
  /// Supports resuming partial downloads if the file already exists
  /// Calculates checksum based on checksumType parameter
  Future<DownloadResult> downloadToFile(
    Uri url,
    String outputDir, {
    String? outputFileName,
    bool resume = true,
    ChecksumType checksumType = ChecksumType.none,
    FileConflictStrategy conflictStrategy = FileConflictStrategy.overwrite,
    CancelToken? cancelToken,
    void Function(int bytes, int total, DownloadStatus status)? onProgress,
  }) async {
    // Check server info
    final info = await client.checkServerInfo(url);

    // Prepare file path
    final filePath = await _prepareFilePath(
      outputDir: outputDir,
      outputFileName: outputFileName,
      serverFileName: info.fileName,
      url: url,
    );

    // Use temporary file during download
    final tempFilePath = '$filePath${client.config.tempFileExtension}';
    final file = File(tempFilePath);

    // FileMode.write truncates any existing file, FileMode.append preserves existing content for resume
    final raf = await file.open(
      mode: (resume && info.acceptRanges) ? FileMode.append : FileMode.write,
    );

    // Helper to notify completion with status
    void onDownloaded(DownloadStatus status) {
      onProgress?.call(info.contentLength, info.contentLength, status);
    }

    try {
      // Check if we can resume and determine start position
      final startBytes = await _determineStartPosition(
        raf: raf,
        acceptRanges: info.acceptRanges,
        contentLength: info.contentLength,
      );

      // If file is already complete, calculate checksum and rename
      if (startBytes == info.contentLength) {
        onDownloaded(DownloadStatus.downloading);
        if (checksumType != ChecksumType.none) {
          onDownloaded(DownloadStatus.calculatingChecksum);
        }
        return await _finalizeDownload(
          file: file,
          filePath: filePath,
          checksumType: checksumType,
          conflictStrategy: conflictStrategy,
        );
      }

      // Stream data to file with buffering
      await _streamToFile(
        raf: raf,
        url: url,
        info: info,
        startBytes: startBytes,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );

      if (checksumType != ChecksumType.none) {
        onDownloaded(DownloadStatus.calculatingChecksum);
      }

      return await _finalizeDownload(
        file: file,
        filePath: filePath,
        checksumType: checksumType,
        conflictStrategy: conflictStrategy,
      );
    } catch (e) {
      // Clean up temporary file on error if not resuming
      if (!resume) {
        // Need to close before deleting the file
        await raf.close();
        if (await file.exists()) {
          await file.delete();
        }
      }
      rethrow;
    } finally {
      await raf.close();
    }
  }

  /// Prepares the file path, creating directory if needed
  Future<String> _prepareFilePath({
    required String outputDir,
    required String? outputFileName,
    required String? serverFileName,
    required Uri url,
  }) async {
    // Determine filename: prefer provided, then server, then URL
    final fileName = (outputFileName ?? serverFileName ?? url.pathSegments.last)
        .replaceAll(RegExp(r'[/\\]'), '_') // Sanitize path separators
        .replaceAll('..', '_'); // Prevent directory traversal

    // Ensure output directory exists
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return '$outputDir/$fileName';
  }

  /// Stream fetched data to file with buffering
  Future<void> _streamToFile({
    required RandomAccessFile raf,
    required Uri url,
    required ServerInfo info,
    required int startBytes,
    CancelToken? cancelToken,
    void Function(int, int, DownloadStatus)? onProgress,
  }) async {
    final buffer = <int>[];

    // Fetch with progress (resume if possible)
    await for (final chunk in client.fetch(
      url,
      contentLength: info.contentLength,
      acceptRanges: info.acceptRanges,
      startBytes: startBytes,
      cancelToken: cancelToken,
      onProgress: (bytes, total) =>
          onProgress?.call(bytes, total, DownloadStatus.downloading),
    )) {
      // Optimize for large chunks that don't need buffering
      if (buffer.isEmpty && chunk.length >= client.config.chunkSize) {
        await raf.writeFrom(chunk);
      } else {
        buffer.addAll(chunk);

        // Write when buffer is large enough
        if (buffer.length >= client.config.chunkSize) {
          await raf.writeFrom(buffer);
          buffer.clear();
        }
      }
    }

    // Write any remaining buffered data
    if (buffer.isNotEmpty) {
      await raf.writeFrom(buffer);
    }
  }

  /// Determines the starting position for download/resume
  Future<int> _determineStartPosition({
    required RandomAccessFile raf,
    required bool acceptRanges,
    required int contentLength,
  }) async {
    // Get current file size for resume if server supports range requests, otherwise start from beginning
    final currentSize = acceptRanges ? await raf.length() : 0;

    // Check for corrupted/wrong file
    if (currentSize > contentLength) {
      throw RangeRequestException(
        code: RangeRequestErrorCode.fileError,
        message:
            'Local file size ($currentSize bytes) exceeds remote file size '
            '($contentLength bytes). File may be corrupted or from a different source.',
      );
    }

    return currentSize;
  }

  /// Finalize download by calculating checksum and renaming temp file
  Future<DownloadResult> _finalizeDownload({
    required File file,
    required String filePath,
    required ChecksumType checksumType,
    required FileConflictStrategy conflictStrategy,
  }) async {
    // Calculate checksum before renaming (so we can resume if it fails)
    final checksum = await _calculateFileChecksum(file, checksumType);

    // Get file size
    final fileSize = await file.length();

    // Handle file conflicts based on strategy
    final finalPath = await _resolveFileConflict(filePath, conflictStrategy);

    // Rename temp file to final name after successful checksum
    await file.rename(finalPath);

    return (
      filePath: finalPath,
      fileSize: fileSize,
      checksum: checksum,
      checksumType: checksumType,
    );
  }

  /// Resolve file naming conflicts based on strategy
  Future<String> _resolveFileConflict(
    String filePath,
    FileConflictStrategy strategy,
  ) async {
    final targetFile = File(filePath);
    if (!await targetFile.exists()) {
      return filePath; // No conflict
    }

    switch (strategy) {
      case FileConflictStrategy.overwrite:
        await targetFile.delete();
        return filePath;

      case FileConflictStrategy.rename:
        // Find available name with number suffix
        final dir = filePath.substring(0, filePath.lastIndexOf('/'));
        final fullName = filePath.substring(filePath.lastIndexOf('/') + 1);
        final dotIndex = fullName.lastIndexOf('.');
        final name = dotIndex > 0 ? fullName.substring(0, dotIndex) : fullName;
        final ext = dotIndex > 0 ? fullName.substring(dotIndex) : '';

        var counter = 1;
        String newPath;
        do {
          newPath = '$dir/$name($counter)$ext';
          counter++;
        } while (await File(newPath).exists());
        return newPath;

      case FileConflictStrategy.error:
        throw RangeRequestException(
          code: RangeRequestErrorCode.fileError,
          message: 'File already exists: $filePath',
        );
    }
  }

  /// Calculates file checksum using the specified algorithm
  Future<String?> _calculateFileChecksum(
    File file,
    ChecksumType checksumType,
  ) async {
    if (checksumType == ChecksumType.none) {
      return null;
    }

    // Use Isolate for checksum calculation to avoid blocking main thread
    return await Isolate.run(
      () => _calculateChecksumInIsolate(file.path, checksumType),
    );
  }

  /// Isolated checksum calculation function
  static Future<String> _calculateChecksumInIsolate(
    String filePath,
    ChecksumType checksumType,
  ) async {
    final file = File(filePath);
    final input = file.openRead();

    final digest = switch (checksumType) {
      ChecksumType.sha256 => await sha256.bind(input).single,
      ChecksumType.md5 => await md5.bind(input).single,
      ChecksumType.none => throw ArgumentError(
        'ChecksumType.none should not reach here',
      ),
    };

    return digest.toString();
  }
}
