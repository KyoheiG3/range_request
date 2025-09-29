/// Type of checksum to calculate during download
enum ChecksumType { sha256, md5, none }

/// Status of the download operation
enum DownloadStatus { downloading, calculatingChecksum }

/// File conflict resolution strategy
enum FileConflictStrategy {
  /// Overwrite existing file
  overwrite,

  /// Keep existing file and add number suffix
  rename,

  /// Throw error if file exists
  error,
}

/// Result of downloadToFile operation
typedef DownloadResult = ({
  /// Full path to the downloaded file
  String filePath,

  /// Size of the downloaded file in bytes
  int fileSize,

  /// Calculated checksum (null if ChecksumType.none)
  String? checksum,

  /// Type of checksum that was calculated
  ChecksumType checksumType,
});

/// Information about server capabilities for range requests
typedef ServerInfo = ({
  /// Whether the server accepts range requests
  bool acceptRanges,

  /// Total size of the content in bytes
  int contentLength,

  /// Filename from Content-Disposition header (if available)
  String? fileName,
});

/// A byte range for chunked downloads
typedef ChunkRange = ({
  /// Starting byte position (inclusive)
  int start,

  /// Ending byte position (inclusive)
  int end,
});

/// Configuration for range requests
class RangeRequestConfig {
  /// Size of each chunk in bytes (default: 10MB)
  final int chunkSize;

  /// Maximum number of concurrent downloads (default: 8)
  final int maxConcurrentRequests;

  /// Optional headers to include in requests (e.g., authorization)
  final Map<String, String> headers;

  /// Maximum number of retry attempts for failed requests (default: 3)
  final int maxRetries;

  /// Initial delay between retries in milliseconds (default: 1000)
  final int retryDelayMs;

  /// Extension for temporary files during download (default: '.tmp')
  final String tempFileExtension;

  /// Connection timeout for HTTP requests (default: 30 seconds)
  final Duration connectionTimeout;

  /// Interval for progress callbacks (default: 500 milliseconds)
  final Duration progressInterval;

  const RangeRequestConfig({
    this.chunkSize = 10 * 1024 * 1024, // 10MB
    this.maxConcurrentRequests = 8,
    this.headers = const {},
    this.maxRetries = 3,
    this.retryDelayMs = 1000,
    this.tempFileExtension = '.tmp',
    this.connectionTimeout = const Duration(seconds: 30),
    this.progressInterval = const Duration(milliseconds: 500),
  });

  /// Creates a copy of this configuration with the given fields replaced with new values
  RangeRequestConfig copyWith({
    int? chunkSize,
    int? maxConcurrentRequests,
    Map<String, String>? headers,
    int? maxRetries,
    int? retryDelayMs,
    String? tempFileExtension,
    Duration? connectionTimeout,
    Duration? progressInterval,
  }) {
    return RangeRequestConfig(
      chunkSize: chunkSize ?? this.chunkSize,
      maxConcurrentRequests: maxConcurrentRequests ?? this.maxConcurrentRequests,
      headers: headers ?? this.headers,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelayMs: retryDelayMs ?? this.retryDelayMs,
      tempFileExtension: tempFileExtension ?? this.tempFileExtension,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      progressInterval: progressInterval ?? this.progressInterval,
    );
  }
}
