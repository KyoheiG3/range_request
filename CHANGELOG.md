# Changelog

## 0.1.0

Initial release of the range_request package for efficient HTTP file downloads with range request support.

### Features

- **Parallel chunked downloads** - Split large files into chunks for concurrent downloading
- **Automatic resume capability** - Continue interrupted downloads from where they left off
- **Checksum verification** - Verify file integrity with MD5/SHA256 algorithms
- **Smart server fallback** - Automatically falls back to serial download if server doesn't support range requests
- **Real-time progress tracking** - Monitor download progress with customizable update intervals
- **Graceful cancellation** - Cancel downloads cleanly using CancelToken
- **File conflict strategies** - Handle existing files with overwrite, rename, or error options
- **Temporary file cleanup** - Utility for removing incomplete download files
- **Isolate-based file I/O** - Non-blocking file operations prevent UI freezing
- **Exponential backoff retry** - Smart retry logic for failed chunks with increasing delays
- **Memory-efficient streaming** - Process large files without loading entire content into memory
- **Configurable parameters** - Fine-tune chunk size, concurrency, timeouts, and retry behavior

### Infrastructure

- Cross-platform support for iOS, Android, Web, Windows, macOS, and Linux
- Minimal dependencies: `http: ^1.1.0` and `crypto: ^3.0.0`
- Dart SDK requirement: ^3.8.0
- Example Flutter app demonstrating package capabilities