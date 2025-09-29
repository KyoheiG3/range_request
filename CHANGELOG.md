# Changelog

## [v0.2.0]

### Breaking Changes

- Moved `progressInterval` parameter from method calls to configuration
  - `RangeRequestClient.fetch()` no longer accepts `progressInterval` parameter
  - `FileDownloader.downloadToFile()` no longer accepts `progressInterval` parameter
  - Migration: Pass `progressInterval` via `RangeRequestConfig` instead:
    ```dart
    // Before
    client.fetch(url, progressInterval: Duration(seconds: 1))

    // After
    final client = RangeRequestClient(
      config: RangeRequestConfig(progressInterval: Duration(seconds: 1))
    );
    client.fetch(url)
    ```

### Features

- Added `CancelTokenGroup` class for managing multiple cancel tokens
  - Cancel all tokens simultaneously with `cancelAll()`
  - Check group cancellation status
  - Add/remove tokens dynamically
  - Clear tokens without cancelling

- Added `cancelAndClear()` method to `RangeRequestClient`
  - Cancel all active operations and clear tokens in a single call
  - Useful for resetting download state

- Added `copyWith()` method to `RangeRequestConfig`
  - Easily create modified configuration instances

- Made `FileDownloader` constructor parameter optional
  - Can now instantiate without arguments: `FileDownloader()`

- Added simplified HTTP abstraction with `Http` and `DefaultHttp` classes
  - Cleaner API for HTTP client customization

### Improvements

- Significantly improved test execution speed (5s → 200ms for cancellation tests)
- Enhanced test reliability with mock-based infrastructure
- Better API ergonomics with shorter class names
- Unified HTTP client abstraction pattern

### Documentation

- Added "Managing Multiple Downloads" section to README
- Enhanced API reference with new cancellation methods
- Improved code examples and migration guides

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