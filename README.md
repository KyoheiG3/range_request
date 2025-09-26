# Range Request

[![pub package](https://img.shields.io/pub/v/range_request.svg)](https://pub.dev/packages/range_request)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

A high-performance Dart package for HTTP range requests, enabling efficient file downloads with support for parallel chunked downloads, automatic resume capability, and checksum verification.

## Features

- 🚀 **Parallel chunked downloads** - Split large files into chunks for concurrent downloading
- 🔄 **Automatic resume** - Continue interrupted downloads from where they left off
- ✅ **Checksum verification** - Verify file integrity with MD5/SHA256
- 🎯 **Smart fallback** - Automatically falls back to serial download if server doesn't support range requests
- 📊 **Progress tracking** - Real-time download progress with customizable intervals
- ❌ **Cancellation support** - Gracefully cancel downloads with CancelToken
- 🔧 **Highly configurable** - Fine-tune chunk size, concurrency, retries, and more
- 🏗️ **Isolate-based I/O** - Non-blocking file operations using Dart isolates
- 🧹 **Temporary file cleanup** - Manual cleanup utility for incomplete downloads

## Installation

```bash
dart pub add range_request
```

Or add it manually to your `pubspec.yaml`:

```yaml
dependencies:
  range_request:
```

Then run:

```bash
dart pub get
```

## Usage

### Basic Streaming Download

```dart
import 'package:range_request/range_request.dart';

void main() async {
  final client = RangeRequestClient();
  final url = Uri.parse('https://example.com/large-file.zip');

  // Stream download with automatic chunking if supported
  await for (final chunk in client.fetch(url)) {
    // Process each chunk (e.g., write to file, update UI, etc.)
    print('Received ${chunk.length} bytes');
  }
}
```

### File Download with Progress Tracking

```dart
import 'package:range_request/range_request.dart';

void main() async {
  final downloader = FileDownloader.fromConfig(
    RangeRequestConfig(
      chunkSize: 5 * 1024 * 1024, // 5MB chunks
      maxConcurrentRequests: 4,
    ),
  );

  final result = await downloader.downloadToFile(
    Uri.parse('https://example.com/video.mp4'),
    '/downloads',
    outputFileName: 'my_video.mp4',
    onProgress: (bytes, total, status) {
      final progress = (bytes / total * 100).toStringAsFixed(1);
      print('Progress: $progress% - Status: $status');
    },
  );

  print('Downloaded to: ${result.filePath}');
  print('File size: ${result.fileSize} bytes');
}
```

### Download with Resume Support

```dart
// Downloads will automatically resume if interrupted
final result = await downloader.downloadToFile(
  Uri.parse('https://example.com/large-file.iso'),
  '/downloads',
  resume: true, // Enable resume (default: true)
  onProgress: (bytes, total, status) {
    if (bytes > 0) {
      print('Resuming from ${bytes} bytes...');
    }
  },
);
```

> **Note**: While resume support can continue interrupted downloads, it cannot detect file corruption that may occur during write operations (e.g., if the application crashes while writing buffered data to disk). In such cases, the resumed download may result in a corrupted file. Consider using checksum verification to ensure file integrity after completion.

### Checksum Verification

```dart
final result = await downloader.downloadToFile(
  Uri.parse('https://example.com/software.exe'),
  '/downloads',
  checksumType: ChecksumType.sha256,
  onProgress: (bytes, total, status) {
    if (status == DownloadStatus.calculatingChecksum) {
      print('Verifying file integrity...');
    }
  },
);

print('SHA256: ${result.checksum}');
```

### Using Cancellation Tokens

```dart
final cancelToken = CancelToken();

// Start download in a separate async operation
final downloadFuture = downloader.downloadToFile(
  Uri.parse('https://example.com/huge-file.bin'),
  '/downloads',
  cancelToken: cancelToken,
);

// Cancel the download after 5 seconds
Future.delayed(Duration(seconds: 5), () {
  cancelToken.cancel();
  print('Download cancelled');
});

try {
  await downloadFuture;
} on RangeRequestException catch (e) {
  if (e.code == RangeRequestErrorCode.cancelled) {
    print('Download was cancelled');
  }
}
```

### Configuration Options

```dart
final config = RangeRequestConfig(
  chunkSize: 10 * 1024 * 1024,        // 10MB chunks
  maxConcurrentRequests: 8,           // 8 parallel connections
  maxRetries: 3,                      // Retry failed chunks 3 times
  retryDelayMs: 1000,                 // Wait 1 second before retry
  connectionTimeout: Duration(seconds: 30),
  tempFileExtension: '.tmp',          // Extension for partial downloads
  headers: {                          // Custom headers
    'Authorization': 'Bearer token',
  },
);

final client = RangeRequestClient(config: config);
```

### File Conflict Handling

```dart
// Choose how to handle existing files
final result = await downloader.downloadToFile(
  url,
  '/downloads',
  conflictStrategy: FileConflictStrategy.rename, // Creates "file(1).ext" if exists
  // or FileConflictStrategy.overwrite (default)
  // or FileConflictStrategy.error (throws exception)
);
```

### Cleanup Temporary Files

```dart
// Remove incomplete downloads older than 1 day
final deletedCount = await downloader.cleanupTempFiles(
  '/downloads',
  olderThan: Duration(days: 1),
);
print('Cleaned up $deletedCount temporary files');
```

## API Reference

### Core Classes

- **`RangeRequestClient`**: Main client for performing HTTP range requests

  - `fetch()`: Stream download with optional progress callback
  - `checkServerInfo()`: Check if server supports range requests

- **`FileDownloader`**: High-level file download operations

  - `downloadToFile()`: Download directly to file with resume support
  - `cleanupTempFiles()`: Clean up temporary download files

- **`RangeRequestConfig`**: Configuration for download behavior

  - Chunk size, concurrency, retries, timeouts, and more

- **`CancelToken`**: Token for cancelling download operations
  - `cancel()`: Cancel the associated download
  - `isCancelled`: Check if operation was cancelled

### Enums

- **`ChecksumType`**: Algorithm for file verification (`sha256`, `md5`, `none`)
- **`DownloadStatus`**: Current operation status (`downloading`, `calculatingChecksum`)
- **`FileConflictStrategy`**: How to handle existing files (`overwrite`, `rename`, `error`)

## Advanced Features

### Parallel Chunked Downloads

When the server supports range requests, files are automatically split into chunks and downloaded in parallel:

```
File: [====================] 100MB
       ↓
Chunks: [====][====][====][====][====]  5 x 20MB
         ↓  ↓  ↓  ↓  ↓
      Parallel Downloads (up to maxConcurrentRequests)
         ↓  ↓  ↓  ↓  ↓
Reassembled: [====================]
```

### Retry Logic

Failed chunks are automatically retried with exponential backoff:

- First retry: 2 seconds delay (2x initial delay)
- Second retry: 4 seconds delay (4x initial delay)
- Third retry: 8 seconds delay (8x initial delay)

### Memory Efficiency

- Streaming API prevents loading entire files into memory
- Configurable buffer sizes for optimal performance
- Isolate-based checksum calculation prevents UI blocking

## Error Handling

```dart
try {
  await downloader.downloadToFile(url, '/downloads');
} on RangeRequestException catch (e) {
  switch (e.code) {
    case RangeRequestErrorCode.networkError:
      print('Network connection failed');
    case RangeRequestErrorCode.serverError:
      print('Server returned an error');
    case RangeRequestErrorCode.fileError:
      print('File system error occurred');
    case RangeRequestErrorCode.checksumMismatch:
      print('Downloaded file is corrupted');
    case RangeRequestErrorCode.cancelled:
      print('Download was cancelled');
    case RangeRequestErrorCode.invalidResponse:
      print('Invalid response from server');
    case RangeRequestErrorCode.unsupportedOperation:
      print('Operation not supported');
  }
}
```

## License

[BSD 3-Clause License](LICENSE)
