import 'dart:async';

import 'package:http/http.dart' as http;

import 'cancel_token.dart';
import 'exceptions.dart';
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
  final CancelToken? cancelToken;

  int nextChunkIndex = 0;
  int nextWriteIndex = 0;

  ChunkFetcher({
    required this.url,
    required this.contentLength,
    required this.config,
    this.startOffset = 0,
    this.cancelToken,
    this.onProgress,
  }) : ranges = _calculateRanges(contentLength, config.chunkSize, startOffset);

  bool get hasMore => activeTasks.isNotEmpty || pendingChunks.isNotEmpty;
  bool get hasActive => activeTasks.isNotEmpty;

  Future<void> startInitialFetches() async {
    while (activeTasks.length < config.maxConcurrentRequests &&
        nextChunkIndex < ranges.length) {
      cancelToken?.throwIfCancelled();
      nextChunkIndex = _queueFetch(nextChunkIndex);
    }
  }

  Future<void> processNextCompletion() async {
    cancelToken?.throwIfCancelled();

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
    if (nextChunkIndex < ranges.length &&
        !(cancelToken?.isCancelled ?? false)) {
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
      cancelToken?.throwIfCancelled();

      try {
        final response = await http
            .get(
              url,
              headers: {
                'Range': 'bytes=${range.start}-${range.end}',
                ...config.headers,
              },
            )
            .timeout(config.connectionTimeout);

        if (response.statusCode != 206) {
          throw RangeRequestException(
            code: RangeRequestErrorCode.invalidResponse,
            message:
                'Expected 206 Partial Content but got ${response.statusCode}',
          );
        }

        return response.bodyBytes;
      } catch (e) {
        if (!await retryHandler.handleError()) {
          rethrow;
        }
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
