# Range Request Example

A Flutter example application demonstrating the capabilities of the `range_request` package for HTTP range requests with parallel downloads.

## Features

This example app showcases:

- **Parallel Chunked Downloads** - Downloads files in 2MB chunks with up to 4 concurrent connections
- **Progress Tracking** - Real-time progress display with percentage and MB downloaded/total
- **SHA256 Checksum Verification** - Automatic checksum calculation to ensure file integrity
- **Download Cancellation** - Cancel ongoing downloads with proper cleanup
- **File Management** - Delete downloaded files directly from the app
- **Auto-Retry** - Automatic retry with exponential backoff (up to 3 attempts per chunk)
- **Resume Support** - Downloads can be resumed if interrupted

## Running the Example

1. Ensure Flutter is installed and configured
2. Navigate to the example directory
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## How It Works

The example downloads a 270MB GGUF model file from HuggingFace to demonstrate:

1. **Server capability check** - Verifies if the server supports range requests
2. **Parallel chunk fetching** - Splits the file into 2MB chunks and downloads up to 4 simultaneously
3. **Progress reporting** - Updates UI with download progress in real-time
4. **Checksum verification** - Calculates SHA256 hash in a separate isolate after download
5. **Error handling** - Implements retry logic for failed chunks

## Configuration

The download behavior can be customized by modifying the `RangeRequestConfig`:

```dart
RangeRequestConfig(
  chunkSize: 1024 * 1024 * 2,     // 2MB chunks
  maxConcurrentRequests: 4,        // 4 parallel downloads
  maxRetries: 3,                   // 3 retry attempts
)
```

## UI Controls

- **Download Button** - Starts the download process
- **Cancel Button** - Interrupts the download (enabled during download)
- **Delete Button** - Removes the downloaded file (enabled after successful download)

## File Storage

Downloaded files are saved to the application's documents directory using the `path_provider` package.