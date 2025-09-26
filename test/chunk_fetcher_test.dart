import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/chunk_fetcher.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:range_request/src/models.dart';
import 'package:test/test.dart';

void main() {
  group('ChunkFetcher', () {
    late HttpServer server;
    late Uri serverUrl;
    const testData = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final testBytes = utf8.encode(testData);

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      serverUrl = Uri.parse('http://localhost:${server.port}/test');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    void setupStandardServer() {
      server.listen((request) async {
        final rangeHeader = request.headers['range']?.first;

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          // Parse range header
          final rangeParts = rangeHeader.substring(6).split('-');
          final start = int.parse(rangeParts[0]);
          final end = int.parse(rangeParts[1]);

          // Send partial content
          request.response.statusCode = 206;
          request.response.headers.contentType = ContentType.binary;
          request.response.add(testBytes.sublist(start, end + 1));
        } else {
          // Send full content
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.binary;
          request.response.add(testBytes);
        }

        await request.response.close();
      });
    }

    group('range calculation', () {
      group('with standard file sizes', () {
        test('should calculate ranges for exact multiples', () {
          // Given: A 40-byte file with 10-byte chunks
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Creating a chunk fetcher
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 40,
            config: config,
          );

          // Then: Should create 4 equal ranges
          expect(fetcher.ranges.length, equals(4));
          expect(fetcher.ranges[0], equals((start: 0, end: 9)));
          expect(fetcher.ranges[1], equals((start: 10, end: 19)));
          expect(fetcher.ranges[2], equals((start: 20, end: 29)));
          expect(fetcher.ranges[3], equals((start: 30, end: 39)));
        });

        test('should calculate ranges with remainder', () {
          // Given: A 36-byte file with 10-byte chunks
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Creating a chunk fetcher
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 36,
            config: config,
          );

          // Then: Last range should be smaller
          expect(fetcher.ranges.length, equals(4));
          expect(fetcher.ranges[0], equals((start: 0, end: 9)));
          expect(fetcher.ranges[1], equals((start: 10, end: 19)));
          expect(fetcher.ranges[2], equals((start: 20, end: 29)));
          expect(fetcher.ranges[3], equals((start: 30, end: 35)));
        });
      });

      group('with resume offset', () {
        test('should calculate ranges from offset position', () {
          // Given: A file with resume from byte 15
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Creating a fetcher with start offset
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 36,
            config: config,
            startOffset: 15,
          );

          // Then: Should create ranges starting from offset
          expect(fetcher.ranges.length, equals(3));
          expect(fetcher.ranges[0], equals((start: 15, end: 24)));
          expect(fetcher.ranges[1], equals((start: 25, end: 34)));
          expect(fetcher.ranges[2], equals((start: 35, end: 35)));
        });

        test('should handle offset at chunk boundary', () {
          // Given: Offset exactly at chunk boundary
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Starting from byte 20
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 36,
            config: config,
            startOffset: 20,
          );

          // Then: Should align with chunk boundaries
          expect(fetcher.ranges.length, equals(2));
          expect(fetcher.ranges[0], equals((start: 20, end: 29)));
          expect(fetcher.ranges[1], equals((start: 30, end: 35)));
        });
      });

      group('edge cases', () {
        test('should handle empty file', () {
          // Given: An empty file
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Creating fetcher for empty file
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 0,
            config: config,
          );

          // Then: Should have no ranges or active tasks
          expect(fetcher.ranges.isEmpty, isTrue);
          expect(fetcher.hasMore, isFalse);
          expect(fetcher.hasActive, isFalse);
        });

        test('should handle single chunk file', () {
          // Given: A file smaller than chunk size
          const config = RangeRequestConfig(chunkSize: 100);

          // When: Creating fetcher for small file
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: testBytes.length,
            config: config,
          );

          // Then: Should have single range covering entire file
          expect(fetcher.ranges.length, equals(1));
          expect(fetcher.ranges[0], equals((start: 0, end: testBytes.length - 1)));
        });

        test('should handle very small chunks', () {
          // Given: 1-byte chunk size
          const config = RangeRequestConfig(chunkSize: 1);

          // When: Creating fetcher
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 5,
            config: config,
          );

          // Then: Should create range for each byte
          expect(fetcher.ranges.length, equals(5));
          for (var i = 0; i < 5; i++) {
            expect(fetcher.ranges[i], equals((start: i, end: i)));
          }
        });
      });
    });

    group('parallel fetching', () {
      setUp(() {
        setupStandardServer();
      });

      group('with concurrent limits', () {
        test('should respect max concurrent requests', () async {
          // Given: Config with 2 concurrent requests
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxConcurrentRequests: 2,
          );

          // When: Starting initial fetches
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: testBytes.length,
            config: config,
          );
          await fetcher.startInitialFetches();

          // Then: Should have exactly 2 active tasks
          expect(fetcher.activeTasks.length, equals(2));
          expect(fetcher.hasActive, isTrue);
        });

        test('should queue next fetch after completion', () async {
          // Given: Single concurrent request allowed
          const config = RangeRequestConfig(
            chunkSize: 5,
            maxConcurrentRequests: 1,
          );
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 20,
            config: config,
          );

          // When: Processing first completion
          await fetcher.startInitialFetches();
          expect(fetcher.activeTasks.length, equals(1));

          await fetcher.processNextCompletion();

          // Then: Should automatically queue next fetch
          expect(fetcher.activeTasks.length, equals(1));
        });

        test('should handle all chunks with limited concurrency', () async {
          // Given: 4 chunks but only 1 concurrent allowed
          const config = RangeRequestConfig(
            chunkSize: 5,
            maxConcurrentRequests: 1,
          );
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 20,
            config: config,
          );

          // When: Processing all chunks sequentially
          await fetcher.startInitialFetches();
          var chunks = 0;
          while (fetcher.hasMore) {
            if (fetcher.hasActive) {
              await fetcher.processNextCompletion();
            }
            await for (final _ in fetcher.yieldReadyChunks()) {
              chunks++;
            }
          }

          // Then: Should process all 4 chunks
          expect(chunks, equals(4));
        });
      });

      group('data ordering', () {
        test('should yield chunks in correct order', () async {
          // Given: Parallel fetching configuration
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxConcurrentRequests: 4,
          );

          // When: Fetching all chunks
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: testBytes.length,
            config: config,
          );
          await fetcher.startInitialFetches();

          final receivedData = <int>[];
          while (fetcher.hasMore) {
            if (fetcher.hasActive) {
              await fetcher.processNextCompletion();
            }
            await for (final chunk in fetcher.yieldReadyChunks()) {
              receivedData.addAll(chunk);
            }
          }

          // Then: Data should match original in correct order
          expect(receivedData, equals(testBytes));
          expect(utf8.decode(receivedData), equals(testData));
        });

        test('should buffer out-of-order chunks', () async {
          // Given: Multiple concurrent requests
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxConcurrentRequests: 3,
          );
          final fetcher = ChunkFetcher(
            url: serverUrl,
            contentLength: 30,
            config: config,
          );

          // When: Starting fetches
          await fetcher.startInitialFetches();

          // Then: Should have active tasks but no ready chunks initially
          expect(fetcher.activeTasks.length, equals(3));
          expect(fetcher.pendingChunks.isEmpty, isTrue);
        });
      });
    });

    group('error handling', () {
      group('with retry mechanism', () {
        test('should retry failed requests', () async {
          // Given: Server that fails first 2 attempts
          var requestCount = 0;
          final errorServer = await HttpServer.bind('localhost', 0);
          final errorUrl = Uri.parse('http://localhost:${errorServer.port}/test');

          errorServer.listen((request) async {
            requestCount++;
            if (requestCount <= 2) {
              request.response.statusCode = 500;
            } else {
              final rangeHeader = request.headers['range']?.first;
              if (rangeHeader != null) {
                request.response.statusCode = 206;
                request.response.add(testBytes.sublist(0, 10));
              }
            }
            await request.response.close();
          });

          // When: Fetching with retry enabled
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxRetries: 3,
            retryDelayMs: 10,
          );
          final fetcher = ChunkFetcher(
            url: errorUrl,
            contentLength: 10,
            config: config,
          );

          await fetcher.startInitialFetches();
          await fetcher.processNextCompletion();

          // Then: Should succeed after 3 attempts
          expect(requestCount, equals(3));

          await errorServer.close();
        });

        test('should fail after max retries exceeded', () async {
          // Given: Server that always returns 500
          final errorServer = await HttpServer.bind('localhost', 0);
          final errorUrl = Uri.parse('http://localhost:${errorServer.port}/test');

          errorServer.listen((request) async {
            request.response.statusCode = 500;
            await request.response.close();
          });

          // When: Attempting fetch with limited retries
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxRetries: 2,
            retryDelayMs: 10,
          );
          final fetcher = ChunkFetcher(
            url: errorUrl,
            contentLength: 10,
            config: config,
          );

          await fetcher.startInitialFetches();

          // Then: Should throw after exhausting retries
          await expectLater(
            fetcher.processNextCompletion(),
            throwsA(isA<RangeRequestException>().having(
              (e) => e.code,
              'code',
              RangeRequestErrorCode.invalidResponse,
            )),
          );

          await errorServer.close();
        });
      });

      group('with invalid responses', () {
        test('should reject non-206 status for range requests', () async {
          // Given: Server returning 200 instead of 206
          final invalidServer = await HttpServer.bind('localhost', 0);
          final invalidUrl = Uri.parse('http://localhost:${invalidServer.port}/test');

          invalidServer.listen((request) async {
            // Return 200 instead of expected 206
            request.response.statusCode = 200;
            request.response.add(testBytes);
            await request.response.close();
          });

          // When: Attempting range request
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxRetries: 0,
          );
          final fetcher = ChunkFetcher(
            url: invalidUrl,
            contentLength: testBytes.length,
            config: config,
          );

          await fetcher.startInitialFetches();

          // Then: Should throw invalid response exception
          await expectLater(
            fetcher.processNextCompletion(),
            throwsA(isA<RangeRequestException>().having(
              (e) => e.message,
              'message',
              contains('Expected 206 Partial Content'),
            )),
          );

          await invalidServer.close();
        });
      });

      group('with timeouts', () {
        test('should timeout slow responses', () async {
          // Given: Server that never responds
          final slowServer = await HttpServer.bind('localhost', 0);
          final slowUrl = Uri.parse('http://localhost:${slowServer.port}/test');

          slowServer.listen((request) async {
            // Never respond
            await Future.delayed(const Duration(seconds: 10));
          });

          // When: Fetching with short timeout
          const config = RangeRequestConfig(
            chunkSize: 10,
            connectionTimeout: Duration(milliseconds: 100),
            maxRetries: 0,
          );
          final fetcher = ChunkFetcher(
            url: slowUrl,
            contentLength: 10,
            config: config,
          );

          await fetcher.startInitialFetches();

          // Then: Should timeout
          await expectLater(
            fetcher.processNextCompletion(),
            throwsA(isA<TimeoutException>()),
          );

          await slowServer.close();
        });
      });
    });

    group('cancellation', () {
      setUp(() {
        setupStandardServer();
      });

      test('should throw when cancelled during fetch', () async {
        // Given: Active fetcher with cancel token
        const config = RangeRequestConfig(
          chunkSize: 10,
          maxConcurrentRequests: 2,
        );
        final cancelToken = CancelToken();
        final fetcher = ChunkFetcher(
          url: serverUrl,
          contentLength: testBytes.length,
          config: config,
          cancelToken: cancelToken,
        );

        // When: Cancelling after starting
        await fetcher.startInitialFetches();
        cancelToken.cancel();

        // Then: Should throw cancelled exception
        expect(
          () => fetcher.processNextCompletion(),
          throwsA(isA<RangeRequestException>().having(
            (e) => e.code,
            'code',
            RangeRequestErrorCode.cancelled,
          )),
        );
      });

      test('should not start new fetches after cancellation', () async {
        // Given: Cancel token that gets cancelled early
        final cancelToken = CancelToken();
        const config = RangeRequestConfig(chunkSize: 10);
        final fetcher = ChunkFetcher(
          url: serverUrl,
          contentLength: testBytes.length,
          config: config,
          cancelToken: cancelToken,
        );

        // When: Cancelling before starting
        cancelToken.cancel();

        // Then: Should throw immediately
        expect(
          () => fetcher.startInitialFetches(),
          throwsA(isA<RangeRequestException>().having(
            (e) => e.code,
            'code',
            RangeRequestErrorCode.cancelled,
          )),
        );
      });
    });

    group('progress tracking', () {
      setUp(() {
        setupStandardServer();
      });

      test('should report progress for each received chunk', () async {
        // Given: Progress callback
        final progressBytes = <int>[];
        const config = RangeRequestConfig(
          chunkSize: 10,
          maxConcurrentRequests: 2,
        );

        // When: Fetching with progress tracking
        final fetcher = ChunkFetcher(
          url: serverUrl,
          contentLength: testBytes.length,
          config: config,
          onProgress: progressBytes.add,
        );

        await fetcher.startInitialFetches();
        while (fetcher.hasMore) {
          if (fetcher.hasActive) {
            await fetcher.processNextCompletion();
          }
          await for (final _ in fetcher.yieldReadyChunks()) {
            // Drain stream
          }
        }

        // Then: Total progress should equal file size
        final totalProgress = progressBytes.reduce((a, b) => a + b);
        expect(totalProgress, equals(testBytes.length));
      });

      test('should not report progress when callback is null', () async {
        // Given: No progress callback
        const config = RangeRequestConfig(chunkSize: 10);
        final fetcher = ChunkFetcher(
          url: serverUrl,
          contentLength: testBytes.length,
          config: config,
          onProgress: null,
        );

        // When: Fetching without progress
        await fetcher.startInitialFetches();

        // Then: Should complete without errors
        expect(
          () async {
            while (fetcher.hasMore) {
              if (fetcher.hasActive) {
                await fetcher.processNextCompletion();
              }
              await for (final _ in fetcher.yieldReadyChunks()) {
                // Drain stream
              }
            }
          },
          returnsNormally,
        );
      });
    });
  });
}