import 'dart:async';

import 'package:http/http.dart';

import 'cancel_token.dart';
import 'exceptions.dart';
import 'http.dart';
import 'models.dart';
import 'retry_handler.dart';

/// Fetches chunks in parallel and yields them in sequential order
class ChunkFetcher {
  final Uri url;
  final int contentLength;
  final RangeRequestConfig config;
  final List<ChunkRange> ranges;
  final Map<int, Future<List<int>>> activeTasks = {};
  final Map<int, List<int>> pendingChunks = {};
  final void Function(int)? onProgress;
  final int startOffset;
  final CancelToken cancelToken;
  final Http http;

  int nextChunkIndex = 0;
  int nextWriteIndex = 0;

  ChunkFetcher({
    required this.url,
    required this.contentLength,
    required this.config,
    this.startOffset = 0,
    required this.cancelToken,
    this.onProgress,
    required this.http,
  }) : ranges = _calculateRanges(contentLength, config.chunkSize, startOffset);

  bool get hasMore => activeTasks.isNotEmpty || pendingChunks.isNotEmpty;
  bool get hasActive => activeTasks.isNotEmpty;

  Future<void> startInitialFetches() async {
    while (activeTasks.length < config.maxConcurrentRequests &&
        nextChunkIndex < ranges.length) {
      cancelToken.throwIfCancelled();
      nextChunkIndex = _queueFetch(nextChunkIndex);
    }
  }

  Future<void> processNextCompletion() async {
    // Wait for any download to complete
    final completed = await Future.any(
      activeTasks.entries.map((entry) async {
        final data = await entry.value;
        return (index: entry.key, data: data);
      }),
    );

    // Move from active to pending
    activeTasks.remove(completed.index);
    pendingChunks[completed.index] = completed.data;

    // Update progress immediately when chunk is received
    onProgress?.call(completed.data.length);

    // Queue next fetch if available
    if (nextChunkIndex < ranges.length && !cancelToken.isCancelled) {
      nextChunkIndex = _queueFetch(nextChunkIndex);
    }
  }

  Stream<List<int>> yieldReadyChunks() async* {
    // Yield all consecutive chunks starting from nextWriteIndex
    while (pendingChunks.containsKey(nextWriteIndex)) {
      final chunk = pendingChunks.remove(nextWriteIndex)!;
      yield chunk;
      nextWriteIndex++;
    }
  }

  int _queueFetch(int index) {
    final range = ranges[index];
    activeTasks[index] = _fetchChunk(range);
    return index + 1;
  }

  Future<List<int>> _fetchChunk(ChunkRange range) async {
    final retryHandler = RetryHandler(
      maxRetries: config.maxRetries,
      initialDelayMs: config.retryDelayMs,
    );

    while (retryHandler.shouldRetry) {
      cancelToken.throwIfCancelled();

      // Create client using factory
      final client = http.createClient();
      cancelToken.registerClient(client);

      try {
        final request = Request('GET', url);
        request.headers['Range'] = 'bytes=${range.start}-${range.end}';
        request.headers.addAll(config.headers);

        final streamedResponse = await client
            .send(request)
            .timeout(config.connectionTimeout);

        if (streamedResponse.statusCode != 206) {
          throw RangeRequestException(
            code: RangeRequestErrorCode.invalidResponse,
            message:
                'Expected 206 Partial Content but got ${streamedResponse.statusCode}',
          );
        }

        final response = await Response.fromStream(streamedResponse);
        return response.bodyBytes;
      } catch (e) {
        if (!await retryHandler.handleError()) {
          rethrow;
        }
      } finally {
        cancelToken.unregisterClient();
        client.close();
      }
    }

    // This should never be reached
    throw RangeRequestException(
      code: RangeRequestErrorCode.networkError,
      message: 'Failed to fetch chunk after ${config.maxRetries} retries',
    );
  }

  static List<ChunkRange> _calculateRanges(
    int totalLength,
    int chunkSize,
    int offset,
  ) {
    final ranges = <ChunkRange>[];
    // Start from offset position
    for (var start = offset; start < totalLength; start += chunkSize) {
      final end = (start + chunkSize - 1).clamp(start, totalLength - 1);
      ranges.add((start: start, end: end));
    }
    return ranges;
  }
}
