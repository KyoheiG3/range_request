import 'dart:async';

import 'package:http/http.dart';

import 'cancel_token.dart';
import 'cancel_token_group.dart';
import 'chunk_fetcher.dart';
import 'exceptions.dart';
import 'http.dart';
import 'models.dart';
import 'retry_handler.dart';

/// Client for performing HTTP range requests
class RangeRequestClient {
  final RangeRequestConfig config;
  final _cancelTokenGroup = CancelTokenGroup();

  /// Factory for creating HTTP clients
  final Http http;

  RangeRequestClient({
    this.config = const RangeRequestConfig(),
    this.http = const DefaultHttp(),
  });

  /// Check if server supports range requests and get content length
  Future<ServerInfo> checkServerInfo(Uri url) async {
    final response = await http
        .head(url, headers: config.headers)
        .timeout(config.connectionTimeout);

    if (response.statusCode != 200) {
      throw RangeRequestException(
        code: RangeRequestErrorCode.serverError,
        message: 'Failed to get file metadata: ${response.statusCode}',
      );
    }

    final contentLength = int.tryParse(
      response.headers['content-length'] ?? '',
    );
    if (contentLength == null) {
      throw RangeRequestException(
        code: RangeRequestErrorCode.invalidResponse,
        message: 'Could not determine file size from Content-Length header',
      );
    }

    // Check if server supports range requests
    final acceptRanges = response.headers['accept-ranges'];

    // Extract filename from Content-Disposition header
    String? fileName;
    final contentDisposition = response.headers['content-disposition'];
    if (contentDisposition != null) {
      // Parse filename from Content-Disposition header
      // Supports: filename="file.txt" and filename=file.txt
      final filenameMatch = RegExp(
        r'filename\s*=\s*("([^"]*)"|([^;]+))',
      ).firstMatch(contentDisposition);
      if (filenameMatch != null) {
        // Group 2 is for quoted filename, group 3 is for unquoted
        fileName = filenameMatch.group(2) ?? filenameMatch.group(3)?.trim();
      }
    }

    return (
      acceptRanges: acceptRanges != null && acceptRanges != 'none',
      contentLength: contentLength,
      fileName: fileName,
    );
  }

  /// Fetch content as a stream without range requests
  Stream<List<int>> _serialFetch(
    Uri url, {
    required CancelToken cancelToken,
    void Function(int bytes)? onProgress,
  }) async* {
    // Simple retry for streaming downloads (when range requests are not supported) - retry the entire download on failure
    final retryHandler = RetryHandler(
      maxRetries: config.maxRetries,
      initialDelayMs: config.retryDelayMs,
    );

    while (retryHandler.shouldRetry) {
      cancelToken.throwIfCancelled();

      final request = Request('GET', url);
      request.headers.addAll(config.headers);

      // Create client using factory
      final client = http.createClient();
      cancelToken.registerClient(client);

      try {
        final response = await client
            .send(request)
            .timeout(config.connectionTimeout);

        if (response.statusCode != 200) {
          throw RangeRequestException(
            code: RangeRequestErrorCode.serverError,
            message: 'Failed to fetch: HTTP ${response.statusCode}',
          );
        }

        await for (final chunk in response.stream) {
          onProgress?.call(chunk.length);
          yield chunk;
        }

        break; // Success, exit retry loop
      } catch (e) {
        if (!await retryHandler.handleError()) {
          rethrow;
        }
      } finally {
        cancelToken.unregisterClient();
        client.close();
      }
    }
  }

  /// Fetch content using range requests for parallel fetching
  Stream<List<int>> _rangeFetch(
    Uri url,
    int contentLength, {
    int startBytes = 0,
    required CancelToken cancelToken,
    void Function(int bytes)? onProgress,
  }) async* {
    final chunks = ChunkFetcher(
      url: url,
      contentLength: contentLength,
      config: config,
      startOffset: startBytes,
      cancelToken: cancelToken,
      onProgress: onProgress,
      http: http,
    );

    await chunks.startInitialFetches();

    while (chunks.hasMore) {
      cancelToken.throwIfCancelled();

      // Wait for and process next completed chunk
      if (chunks.hasActive) {
        await chunks.processNextCompletion();
      }

      // Yield any ready chunks in order
      yield* chunks.yieldReadyChunks();
    }
  }

  /// Fetch content with optional progress callback
  Stream<List<int>> fetch(
    Uri url, {
    int? contentLength,
    bool? acceptRanges,
    int startBytes = 0,
    CancelToken? cancelToken,
    void Function(int bytes, int total)? onProgress,
  }) async* {
    // Use provided token or create internal token for cancelAll functionality
    final effectiveToken = cancelToken ?? CancelToken();

    // Register token with the group
    _cancelTokenGroup.addToken(effectiveToken);

    var receivedBytes = startBytes;

    // Check server info if not provided
    final info = (contentLength != null && acceptRanges != null)
        ? (
            contentLength: contentLength,
            acceptRanges: acceptRanges,
            fileName: null,
          )
        : await checkServerInfo(url);

    // Set up progress timer if callback provided
    Timer? progressTimer;
    if (onProgress != null) {
      progressTimer = Timer.periodic(config.progressInterval, (_) {
        if (receivedBytes > 0) {
          onProgress(receivedBytes, info.contentLength);
        }
      });
    }

    try {
      // Progress callback to update received bytes
      void updateProgress(int bytes) => receivedBytes += bytes;

      // Choose fetch strategy based on server capabilities
      final stream = info.acceptRanges
          ? _rangeFetch(
              url,
              info.contentLength,
              startBytes: startBytes,
              cancelToken: effectiveToken,
              onProgress: updateProgress,
            )
          : _serialFetch(
              url,
              cancelToken: effectiveToken,
              onProgress: updateProgress,
            );

      await for (final chunk in stream) {
        yield chunk;
      }

      // Send final progress
      onProgress?.call(receivedBytes, info.contentLength);
    } finally {
      progressTimer?.cancel();
    }
  }

  /// Cancel all active operations managed by this client
  void cancelAll() {
    _cancelTokenGroup.cancelAll();
  }

  /// Clear all tokens from the group without cancelling them
  void clearTokens() {
    _cancelTokenGroup.clear();
  }
}
