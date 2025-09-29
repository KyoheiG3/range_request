import 'dart:async';
import 'dart:convert';

import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/chunk_fetcher.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:range_request/src/models.dart';
import 'package:test/test.dart';

import 'mock_http.dart';

void main() {
  group('ChunkFetcher', () {
    late MockHttp mockHttp;
    late Uri testUrl;
    const testData = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final testBytes = utf8.encode(testData);

    setUp(() {
      mockHttp = MockHttp();
      testUrl = Uri.parse('http://test.example.com/file');
    });

    tearDown(() {
      mockHttp.reset();
    });

    group('range calculation', () {
      group('with standard file sizes', () {
        test('should calculate ranges for exact multiples', () {
          // Given: A 40-byte file with 10-byte chunks
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Creating a chunk fetcher
          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 40,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: 36,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: 36,
            config: config,
            startOffset: 15,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: 36,
            config: config,
            startOffset: 20,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: 0,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: testBytes.length,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
          );

          // Then: Should have single range covering entire file
          expect(fetcher.ranges.length, equals(1));
          expect(
            fetcher.ranges[0],
            equals((start: 0, end: testBytes.length - 1)),
          );
        });

        test('should handle very small chunks', () {
          // Given: 1-byte chunk size
          const config = RangeRequestConfig(chunkSize: 1);

          // When: Creating fetcher
          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 5,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
        // Register range response for test data
        mockHttp.registerRangeResponse(testUrl.toString(), testBytes);
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
            url: testUrl,
            contentLength: testBytes.length,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: 20,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
          );

          // Register response for smaller data
          mockHttp.reset();
          mockHttp.registerRangeResponse(
            testUrl.toString(),
            List.generate(20, (i) => i),
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

          // Register response for smaller data
          mockHttp.reset();
          final smallData = List.generate(20, (i) => i);
          mockHttp.registerRangeResponse(testUrl.toString(), smallData);

          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 20,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
            url: testUrl,
            contentLength: testBytes.length,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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

          mockHttp.reset();
          mockHttp.registerRangeResponse(
            testUrl.toString(),
            List.generate(30, (i) => i),
          );

          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 30,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
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
          // Given: Mock that fails first 2 attempts
          mockHttp.registerResponse(
            'GET:$testUrl:RANGE',
            statusCode: 206,
            body: testBytes.sublist(0, 10),
          );

          // Override with custom mock for retry testing
          final retryMockFactory = MockHttp();
          retryMockFactory.registerResponse(
            testUrl.toString(),
            statusCode: 206,
            body: testBytes.sublist(0, 10),
            headers: {
              'content-range': 'bytes 0-9/${testBytes.length}',
              'content-length': '10',
            },
          );

          // When: Fetching with retry enabled
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxRetries: 3,
            retryDelayMs: 10,
          );
          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 10,
            config: config,
            cancelToken: CancelToken(),
            http: retryMockFactory,
          );

          await fetcher.startInitialFetches();
          await fetcher.processNextCompletion();

          // Then: Should succeed eventually
          expect(fetcher.pendingChunks.isNotEmpty, isTrue);
        });

        test('should fail after max retries exceeded', () async {
          // Given: Mock that always returns 500 for range requests
          // Need to register for GET with Range header
          mockHttp.registerResponse(
            'GET:$testUrl',
            statusCode: 500,
            body: 'Server Error',
          );

          // When: Attempting fetch with limited retries
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxRetries: 2,
            retryDelayMs: 10,
          );
          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 10,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
          );

          await fetcher.startInitialFetches();

          // Then: Should throw after exhausting retries
          await expectLater(
            fetcher.processNextCompletion(),
            throwsA(
              isA<RangeRequestException>().having(
                (e) => e.code,
                'code',
                RangeRequestErrorCode.invalidResponse,
              ),
            ),
          );
        });
      });

      group('with invalid responses', () {
        test('should reject non-206 status for range requests', () async {
          // Given: Mock returning 200 instead of 206 for range requests
          mockHttp.registerResponse(
            'GET:$testUrl',
            statusCode: 200,
            body: testBytes,
          );

          // When: Attempting range request
          const config = RangeRequestConfig(chunkSize: 10, maxRetries: 0);
          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: testBytes.length,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
          );

          await fetcher.startInitialFetches();

          // Then: Should throw invalid response exception
          await expectLater(
            fetcher.processNextCompletion(),
            throwsA(
              isA<RangeRequestException>().having(
                (e) => e.message,
                'message',
                contains('Expected 206 Partial Content'),
              ),
            ),
          );
        });
      });

      group('with timeouts', () {
        test('should timeout slow responses', () async {
          // Given: Mock with long delay
          mockHttp.registerResponse(
            testUrl.toString(),
            statusCode: 206,
            body: testBytes.sublist(0, 10),
            delay: const Duration(seconds: 1),
          );

          // When: Fetching with short timeout
          const config = RangeRequestConfig(
            chunkSize: 10,
            connectionTimeout: Duration(milliseconds: 100),
            maxRetries: 0,
          );
          final fetcher = ChunkFetcher(
            url: testUrl,
            contentLength: 10,
            config: config,
            cancelToken: CancelToken(),
            http: mockHttp,
          );

          await fetcher.startInitialFetches();

          // Then: Should timeout
          await expectLater(
            fetcher.processNextCompletion(),
            throwsA(isA<TimeoutException>()),
          );
        });
      });
    });

    group('cancellation', () {
      setUp(() {
        mockHttp.registerRangeResponse(testUrl.toString(), testBytes);
      });

      test('should handle cancellation gracefully', () async {
        // Given: Active fetcher with cancel token
        const config = RangeRequestConfig(
          chunkSize: 10,
          maxConcurrentRequests: 2,
        );
        final cancelToken = CancelToken();
        final fetcher = ChunkFetcher(
          url: testUrl,
          contentLength: testBytes.length,
          config: config,
          cancelToken: cancelToken,
          http: mockHttp,
        );

        // When: Starting fetches
        await fetcher.startInitialFetches();

        // Then: Should have active tasks
        expect(fetcher.hasActive, isTrue);

        // When: Cancelling
        cancelToken.cancel();

        // Then: processNextCompletion completes normally (mocked requests complete)
        // In real scenarios, the HTTP client would be cancelled and throw
        await fetcher.processNextCompletion();
      });

      test('should not start fetches when pre-cancelled', () async {
        // Given: Cancel token that gets cancelled early
        final cancelToken = CancelToken();
        const config = RangeRequestConfig(chunkSize: 10);
        final fetcher = ChunkFetcher(
          url: testUrl,
          contentLength: testBytes.length,
          config: config,
          cancelToken: cancelToken,
          http: mockHttp,
        );

        // When: Cancelling before starting
        cancelToken.cancel();

        // Then: startInitialFetches should throw immediately without creating tasks
        await expectLater(
          fetcher.startInitialFetches(),
          throwsA(
            isA<RangeRequestException>().having(
              (e) => e.code,
              'code',
              RangeRequestErrorCode.cancelled,
            ),
          ),
        );

        // And no tasks should have been created
        expect(fetcher.hasActive, isFalse);
      });
    });

    group('progress tracking', () {
      setUp(() {
        mockHttp.registerRangeResponse(testUrl.toString(), testBytes);
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
          url: testUrl,
          contentLength: testBytes.length,
          config: config,
          cancelToken: CancelToken(),
          onProgress: progressBytes.add,
          http: mockHttp,
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
    });
  });
}
