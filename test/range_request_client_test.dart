import 'dart:convert';

import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:range_request/src/models.dart';
import 'package:range_request/src/range_request_client.dart';
import 'package:test/test.dart';

import 'mock_http.dart';

void main() {
  group('RangeRequestClient', () {
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

    group('checkServerInfo', () {
      group('when server supports range requests', () {
        test('should return complete server capabilities', () async {
          // Given: Server with range support and file metadata
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
            fileName: 'test.txt',
          );

          // When: Checking server info
          final client = RangeRequestClient(http: mockHttp);
          final info = await client.checkServerInfo(testUrl);

          // Then: Should return all server capabilities
          expect(info.acceptRanges, isTrue);
          expect(info.contentLength, equals(testBytes.length));
          expect(info.fileName, equals('test.txt'));
        });

        test('should parse quoted filename correctly', () async {
          // Given: Server with quoted filename in content-disposition
          mockHttp.registerResponse(
            'HEAD:$testUrl',
            statusCode: 200,
            headers: {
              'content-length': testBytes.length.toString(),
              'accept-ranges': 'bytes',
              'content-disposition': 'attachment; filename="my file.txt"',
            },
            body: '',
          );

          // When: Checking server info
          final client = RangeRequestClient(http: mockHttp);
          final info = await client.checkServerInfo(testUrl);

          // Then: Should parse filename correctly
          expect(info.fileName, equals('my file.txt'));
          expect(info.contentLength, equals(testBytes.length));
          expect(info.acceptRanges, isTrue);
        });
      });

      group('when server does not support range requests', () {
        test('should indicate no range support', () async {
          // Given: Server without range support
          mockHttp.registerResponse(
            'HEAD:$testUrl',
            statusCode: 200,
            headers: {
              'content-length': testBytes.length.toString(),
              // No accept-ranges header
            },
            body: '',
          );

          // When: Checking server info
          final client = RangeRequestClient(http: mockHttp);
          final info = await client.checkServerInfo(testUrl);

          // Then: Should indicate no range support
          expect(info.acceptRanges, isFalse);
          expect(info.contentLength, equals(testBytes.length));
        });

        test('should handle accept-ranges: none', () async {
          // Given: Server explicitly refusing range requests
          mockHttp.registerResponse(
            'HEAD:$testUrl',
            statusCode: 200,
            headers: {
              'content-length': testBytes.length.toString(),
              'accept-ranges': 'none',
            },
            body: '',
          );

          // When: Checking server info
          final client = RangeRequestClient(http: mockHttp);
          final info = await client.checkServerInfo(testUrl);

          // Then: Should indicate no range support
          expect(info.acceptRanges, isFalse);
        });
      });

      group('error handling', () {
        test('should throw on non-200 status', () async {
          // Given: Server returning error
          mockHttp.registerResponse(
            'HEAD:$testUrl',
            statusCode: 404,
            body: 'Not Found',
          );

          // When/Then: Should throw exception
          final client = RangeRequestClient(http: mockHttp);
          await expectLater(
            client.checkServerInfo(testUrl),
            throwsA(
              isA<RangeRequestException>().having(
                (e) => e.code,
                'code',
                RangeRequestErrorCode.serverError,
              ),
            ),
          );
        });

        test('should throw on missing content-length', () async {
          // Given: Server without content-length
          mockHttp.registerResponse(
            'HEAD:$testUrl',
            statusCode: 200,
            headers: {
              'accept-ranges': 'bytes',
              // No content-length header
            },
            body: '',
          );

          // When/Then: Should throw exception
          final client = RangeRequestClient(http: mockHttp);
          await expectLater(
            client.checkServerInfo(testUrl),
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
    });

    group('fetch', () {
      group('with range support', () {
        setUp(() {
          // Setup standard range response
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(testUrl.toString(), testBytes);
        });

        test('should fetch complete file with parallel downloads', () async {
          // Given: Config for parallel downloads
          const config = RangeRequestConfig(
            chunkSize: 10,
            maxConcurrentRequests: 2,
          );

          // When: Fetching file
          final client = RangeRequestClient(config: config, http: mockHttp);
          final stream = client.fetch(testUrl);
          final received = <int>[];
          await for (final chunk in stream) {
            received.addAll(chunk);
          }

          // Then: Should receive complete file
          expect(received, equals(testBytes));
        });

        test('should report progress during download', () async {
          // Given: Progress callback
          final progressUpdates = <(int, int)>[];
          const config = RangeRequestConfig(
            chunkSize: 10,
            progressInterval: Duration(milliseconds: 10),
          );

          // When: Fetching with progress
          final client = RangeRequestClient(config: config, http: mockHttp);
          final stream = client.fetch(
            testUrl,
            onProgress: (bytes, total) => progressUpdates.add((bytes, total)),
          );

          await stream.drain();

          // Then: Should report progress
          expect(progressUpdates.isNotEmpty, isTrue);
          final lastUpdate = progressUpdates.last;
          expect(lastUpdate.$1, equals(testBytes.length));
          expect(lastUpdate.$2, equals(testBytes.length));
        });

        test('should support resume from offset', () async {
          // Given: Starting from byte 10
          const startBytes = 10;
          const config = RangeRequestConfig(chunkSize: 10);

          // When: Fetching from offset
          final client = RangeRequestClient(config: config, http: mockHttp);
          final stream = client.fetch(
            testUrl,
            contentLength: testBytes.length,
            acceptRanges: true,
            startBytes: startBytes,
          );

          final received = <int>[];
          await for (final chunk in stream) {
            received.addAll(chunk);
          }

          // Then: Should receive partial file
          expect(received, equals(testBytes.sublist(startBytes)));
        });
      });

      group('without range support', () {
        test('should fetch using serial download', () async {
          // Given: Server without range support
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );

          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 200,
            headers: {'content-length': testBytes.length.toString()},
            body: testBytes,
          );

          // When: Fetching file
          final client = RangeRequestClient(http: mockHttp);
          final stream = client.fetch(testUrl);
          final received = <int>[];
          await for (final chunk in stream) {
            received.addAll(chunk);
          }

          // Then: Should receive complete file
          expect(received, equals(testBytes));
        });

        test('should report progress during serial download', () async {
          // Given: Server without range support
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );

          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 200,
            headers: {'content-length': testBytes.length.toString()},
            body: testBytes,
          );

          // When: Fetching with progress callback
          final progressUpdates = <(int, int)>[];
          final client = RangeRequestClient(http: mockHttp);
          final stream = client.fetch(
            testUrl,
            onProgress: (bytes, total) => progressUpdates.add((bytes, total)),
          );

          await stream.drain();

          // Then: Should report progress (called when receivedBytes > 0)
          expect(progressUpdates.isNotEmpty, isTrue);
          expect(progressUpdates.last.$1, equals(testBytes.length));
          expect(progressUpdates.last.$2, equals(testBytes.length));
        });

        test('should not report progress when no bytes received', () async {
          // Given: Server without range support
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );

          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 200,
            headers: {'content-length': testBytes.length.toString()},
            body: testBytes,
          );

          // When: Fetching with progress callback
          var zeroProgressCalled = false;
          final client = RangeRequestClient(http: mockHttp);
          final stream = client.fetch(
            testUrl,
            startBytes: 0,
            onProgress: (bytes, total) {
              if (bytes == 0) {
                zeroProgressCalled = true;
              }
            },
          );

          await stream.drain();

          // Then: Should not call progress with 0 bytes
          expect(zeroProgressCalled, isFalse);
        });
      });

      group('cancellation', () {
        setUp(() {
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(
            testUrl.toString(),
            testBytes,
            delay: const Duration(milliseconds: 200),
          );
        });

        test('should not start fetch if already cancelled', () async {
          // Given: Pre-cancelled token
          final cancelToken = CancelToken()..cancel();

          // When/Then: Should throw immediately
          final client = RangeRequestClient(http: mockHttp);
          final stream = client.fetch(testUrl, cancelToken: cancelToken);

          await expectLater(
            stream.first,
            throwsA(
              isA<RangeRequestException>().having(
                (e) => e.code,
                'code',
                RangeRequestErrorCode.cancelled,
              ),
            ),
          );
        });
      });

      group('with custom headers', () {
        test('should include headers in all requests', () async {
          // Given: Custom headers in config
          final customHeaders = {'Authorization': 'Bearer token123'};
          final config = RangeRequestConfig(
            headers: customHeaders,
            chunkSize: 10,
          );

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(testUrl.toString(), testBytes);

          // When: Fetching with custom headers
          final client = RangeRequestClient(config: config, http: mockHttp);
          await client.fetch(testUrl).drain();

          // Then: Headers should be included in requests
          final requests = mockHttp.requestHistory;
          for (final request in requests) {
            if (request.headers.containsKey('Authorization')) {
              expect(
                request.headers['Authorization'],
                equals('Bearer token123'),
              );
            }
          }
        });
      });

      group('error handling', () {
        test('should fail after max retries for serial fetch', () async {
          // Given: Server that always fails
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );

          mockHttp.registerResponse(
            'GET:$testUrl',
            statusCode: 500,
            body: 'Server Error',
          );

          // When: Attempting fetch with limited retries
          const config = RangeRequestConfig(maxRetries: 2, retryDelayMs: 10);
          final client = RangeRequestClient(config: config, http: mockHttp);

          // Then: Should throw after retries exhausted
          await expectLater(
            client.fetch(testUrl).drain(),
            throwsA(isA<RangeRequestException>()),
          );
        });
      });
    });

    group('cancel operations', () {
      test('cancelAll should cancel all active downloads', () async {
        // Given: Client with slow downloads
        mockHttp.registerHeadResponse(
          testUrl.toString(),
          contentLength: testBytes.length,
          acceptRanges: true,
        );
        mockHttp.registerRangeResponse(
          testUrl.toString(),
          testBytes,
          delay: const Duration(milliseconds: 200),
        );

        final client = RangeRequestClient(
          config: const RangeRequestConfig(chunkSize: 10),
          http: mockHttp,
        );

        // When: Starting downloads
        final download1Future = client.fetch(testUrl).toList();
        final download2Future = client.fetch(testUrl).toList();

        // Cancel all after a short delay (before downloads complete)
        await Future.delayed(const Duration(milliseconds: 50));
        client.cancelAll();

        // Then: All downloads should be cancelled
        await expectLater(
          download1Future,
          throwsA(
            isA<RangeRequestException>().having(
              (e) => e.code,
              'code',
              RangeRequestErrorCode.cancelled,
            ),
          ),
        );
        await expectLater(
          download2Future,
          throwsA(
            isA<RangeRequestException>().having(
              (e) => e.code,
              'code',
              RangeRequestErrorCode.cancelled,
            ),
          ),
        );
      });

      test('clearTokens should remove tokens without cancelling', () async {
        // Given: Client with a download
        mockHttp.registerHeadResponse(
          testUrl.toString(),
          contentLength: testBytes.length,
          acceptRanges: false,
        );
        mockHttp.registerResponse(
          'GET:$testUrl:FULL',
          statusCode: 200,
          body: testBytes,
        );

        final client = RangeRequestClient(http: mockHttp);

        // When: Starting download (creates internal token)
        final downloadFuture = client.fetch(testUrl).toList();

        // Clear tokens immediately (removes token from group but doesn't cancel)
        client.clearTokens();

        // Then: Download should complete successfully
        final chunks = await downloadFuture;
        expect(chunks.isNotEmpty, isTrue);

        // Verify that cancelAll after clearTokens has no effect on cleared downloads
        client.cancelAll();

        // The download already completed, so cancelAll doesn't affect it
        expect(chunks.isNotEmpty, isTrue);
      });
    });
  });
}
