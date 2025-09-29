import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:range_request/src/models.dart';
import 'package:range_request/src/range_request_client.dart';
import 'package:test/test.dart';

void main() {
  group('RangeRequestClient', () {
    late HttpServer server;
    late Uri serverUrl;
    const testData = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final testBytes = utf8.encode(testData);

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      serverUrl = Uri.parse('http://localhost:${server.port}/test.txt');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    void setupServerWithRangeSupport({String? fileName}) {
      server.listen((request) async {
        if (request.method == 'HEAD') {
          request.response.statusCode = 200;
          request.response.headers.set('content-length', testBytes.length.toString());
          request.response.headers.set('accept-ranges', 'bytes');
          if (fileName != null) {
            request.response.headers.set('content-disposition', 'attachment; filename="$fileName"');
          }
        } else if (request.method == 'GET') {
          final rangeHeader = request.headers['range']?.first;
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final rangeParts = rangeHeader.substring(6).split('-');
            final start = int.parse(rangeParts[0]);
            final end = rangeParts[1].isEmpty
              ? testBytes.length - 1
              : int.parse(rangeParts[1]);
            request.response.statusCode = 206;
            request.response.add(testBytes.sublist(start, end + 1));
          } else {
            request.response.statusCode = 200;
            request.response.add(testBytes);
          }
        }
        await request.response.close();
      });
    }

    void setupServerWithoutRangeSupport() {
      server.listen((request) async {
        if (request.method == 'HEAD') {
          request.response.statusCode = 200;
          request.response.headers.set('content-length', testBytes.length.toString());
          request.response.headers.set('accept-ranges', 'none');
        } else if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.add(testBytes);
        }
        await request.response.close();
      });
    }

    group('checkServerInfo', () {
      group('when server supports range requests', () {
        test('should return complete server capabilities', () async {
          // Given: Server with range support and file metadata
          setupServerWithRangeSupport(fileName: 'test.txt');

          // When: Checking server info
          final client = RangeRequestClient();
          final info = await client.checkServerInfo(serverUrl);

          // Then: Should return all server capabilities
          expect(info.acceptRanges, isTrue);
          expect(info.contentLength, equals(testBytes.length));
          expect(info.fileName, equals('test.txt'));
        });

        test('should parse quoted filename correctly', () async {
          // Given: Server with quoted filename in content-disposition
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', '1000');
              request.response.headers.set('content-disposition', 'attachment; filename="my file.txt"');
            }
            await request.response.close();
          });

          // When: Checking server info
          final client = RangeRequestClient();
          final info = await client.checkServerInfo(serverUrl);

          // Then: Should parse filename with spaces correctly
          expect(info.fileName, equals('my file.txt'));
        });

        test('should parse unquoted filename correctly', () async {
          // Given: Server with unquoted filename
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', '1000');
              request.response.headers.set('content-disposition', 'attachment; filename=document.pdf');
            }
            await request.response.close();
          });

          // When: Checking server info
          final client = RangeRequestClient();
          final info = await client.checkServerInfo(serverUrl);

          // Then: Should parse simple filename correctly
          expect(info.fileName, equals('document.pdf'));
        });
      });

      group('when server does not support range requests', () {
        test('should indicate no range support', () async {
          // Given: Server without range support
          setupServerWithoutRangeSupport();

          // When: Checking server info
          final client = RangeRequestClient();
          final info = await client.checkServerInfo(serverUrl);

          // Then: Should indicate no range support
          expect(info.acceptRanges, isFalse);
          expect(info.contentLength, equals(testBytes.length));
          expect(info.fileName, isNull);
        });
      });

      group('with custom headers', () {
        test('should include authorization headers', () async {
          // Given: Server that expects auth header
          var receivedAuth = '';
          server.listen((request) async {
            receivedAuth = request.headers['authorization']?.first ?? '';
            request.response.statusCode = 200;
            request.response.headers.set('content-length', '1000');
            await request.response.close();
          });

          // When: Checking server info with auth
          const config = RangeRequestConfig(
            headers: {'Authorization': 'Bearer token123'},
          );
          final client = RangeRequestClient(config: config);
          await client.checkServerInfo(serverUrl);

          // Then: Should send authorization header
          expect(receivedAuth, equals('Bearer token123'));
        });
      });

      group('error handling', () {
        test('should throw on non-200 status', () async {
          // Given: Server returning 404
          server.listen((request) async {
            request.response.statusCode = 404;
            await request.response.close();
          });

          // When/Then: Should throw server error
          final client = RangeRequestClient();
          expect(
            () => client.checkServerInfo(serverUrl),
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.serverError)
              .having((e) => e.message, 'message', contains('404'))),
          );
        });

        test('should throw on missing content-length', () async {
          // Given: Server without content-length header
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              // No content-length header
            }
            await request.response.close();
          });

          // When/Then: Should throw invalid response error
          final client = RangeRequestClient();
          expect(
            () => client.checkServerInfo(serverUrl),
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.invalidResponse)
              .having((e) => e.message, 'message', contains('Content-Length'))),
          );
        });

        test('should respect connection timeout', () async {
          // Given: Server that never responds
          server.listen((request) async {
            await Future.delayed(const Duration(seconds: 10));
          });

          // When/Then: Should timeout
          const config = RangeRequestConfig(
            connectionTimeout: Duration(milliseconds: 100),
          );
          final client = RangeRequestClient(config: config);
          expect(
            () => client.checkServerInfo(serverUrl),
            throwsA(isA<TimeoutException>()),
          );
        });
      });
    });

    group('fetch', () {
      group('when server supports range requests', () {
        setUp(() {
          setupServerWithRangeSupport();
        });

        test('should use parallel chunked downloads', () async {
          // Given: Configuration for chunked downloads
          const config = RangeRequestConfig(chunkSize: 10);
          final client = RangeRequestClient(config: config);

          // When: Fetching data
          final receivedData = <int>[];
          await for (final chunk in client.fetch(serverUrl)) {
            receivedData.addAll(chunk);
          }

          // Then: Should receive complete data
          expect(receivedData, equals(testBytes));
        });

      });

      group('when resuming from specific position', () {
        test('should resume from specified byte position', () async {
          // Given: Resume from byte 10
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', testBytes.length.toString());
              request.response.headers.set('accept-ranges', 'bytes');
            } else if (request.method == 'GET') {
              final rangeHeader = request.headers['range']?.first;
              if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
                final rangeParts = rangeHeader.substring(6).split('-');
                final start = int.parse(rangeParts[0]);
                final end = rangeParts[1].isEmpty
                  ? testBytes.length - 1
                  : int.parse(rangeParts[1]);

                // Verify resume position
                expect(start, greaterThanOrEqualTo(10));

                request.response.statusCode = 206;
                request.response.headers.set('content-range', 'bytes $start-$end/${testBytes.length}');
                request.response.headers.set('content-length', '${end - start + 1}');
                request.response.add(testBytes.sublist(start, end + 1));
              }
            }
            await request.response.close();
          });

          // When: Fetching with start offset
          const config = RangeRequestConfig(chunkSize: 10);
          final client = RangeRequestClient(config: config);

          final receivedData = <int>[];
          await for (final chunk in client.fetch(
            serverUrl,
            startBytes: 10,
          )) {
            receivedData.addAll(chunk);
          }

          // Then: Should receive data from offset
          expect(receivedData, equals(testBytes.sublist(10)));
        });
      });

      group('when server does not support range requests', () {
        setUp(() {
          setupServerWithoutRangeSupport();
        });

        test('should fall back to serial download', () async {
          // Given: Client with range request configuration
          final client = RangeRequestClient();

          // When: Fetching from server without range support
          final receivedData = <int>[];
          await for (final chunk in client.fetch(serverUrl)) {
            receivedData.addAll(chunk);
          }

          // Then: Should still receive complete data
          expect(receivedData, equals(testBytes));
        });

      });

      group('with retry behavior', () {
        test('should retry on failure for serial fetch', () async {
          // Given: Server that fails first 2 attempts
          var requestCount = 0;
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', testBytes.length.toString());
              request.response.headers.set('accept-ranges', 'none');
            } else if (request.method == 'GET') {
              requestCount++;
              if (requestCount <= 2) {
                // Fail first two attempts
                request.response.statusCode = 500;
              } else {
                // Succeed on third attempt
                request.response.statusCode = 200;
                request.response.add(testBytes);
              }
            }
            await request.response.close();
          });

          // When: Fetching with retry configuration
          const config = RangeRequestConfig(
            maxRetries: 3,
            retryDelayMs: 10,
          );
          final client = RangeRequestClient(config: config);

          final receivedData = <int>[];
          await for (final chunk in client.fetch(serverUrl)) {
            receivedData.addAll(chunk);
          }

          // Then: Should succeed after retries
          expect(receivedData, equals(testBytes));
          expect(requestCount, equals(3));
        });
      });

      group('with provided server info', () {
        test('should skip HEAD request when info provided', () async {
          // Given: Server that only handles GET
          server.listen((request) async {
            // Should not receive HEAD request
            expect(request.method, equals('GET'));

            if (request.method == 'GET') {
              final rangeHeader = request.headers['range']?.first;
              if (rangeHeader != null) {
                request.response.statusCode = 206;
                request.response.add(testBytes);
              }
            }
            await request.response.close();
          });

          // When: Fetching with pre-provided server info
          final client = RangeRequestClient();

          final receivedData = <int>[];
          await for (final chunk in client.fetch(
            serverUrl,
            contentLength: testBytes.length,
            acceptRanges: true,
          )) {
            receivedData.addAll(chunk);
          }

          // Then: Should fetch data without HEAD request
          expect(receivedData, equals(testBytes));
        });
      });

      group('progress tracking', () {
        test('should report progress periodically', () async {
          // Given: Server that sends data in chunks with range support
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', testBytes.length.toString());
              request.response.headers.set('accept-ranges', 'bytes');
            } else if (request.method == 'GET') {
              final rangeHeader = request.headers['range']?.first;
              if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
                // Handle range request
                final rangeParts = rangeHeader.substring(6).split('-');
                final start = int.parse(rangeParts[0]);
                final end = rangeParts[1].isEmpty
                  ? testBytes.length - 1
                  : int.parse(rangeParts[1]);

                request.response.statusCode = 206;
                request.response.headers.set('content-range', 'bytes $start-$end/${testBytes.length}');
                request.response.headers.set('content-length', '${end - start + 1}');

                // Send requested range in small chunks with delays
                for (var i = start; i <= end; i += 5) {
                  final chunkEnd = (i + 5).clamp(start, end + 1);
                  request.response.add(testBytes.sublist(i, chunkEnd));
                  await request.response.flush();
                  await Future.delayed(const Duration(milliseconds: 10));
                }
              } else {
                // Regular GET without range
                request.response.statusCode = 200;
                for (var i = 0; i < testBytes.length; i += 5) {
                  final end = (i + 5).clamp(0, testBytes.length);
                  request.response.add(testBytes.sublist(i, end));
                  await request.response.flush();
                  await Future.delayed(const Duration(milliseconds: 10));
                }
              }
            }
            await request.response.close();
          });

          // When: Fetching with progress callback
          final client = RangeRequestClient(
            config: RangeRequestConfig(
              progressInterval: const Duration(milliseconds: 20),
            ),
          );
          final progressReports = <(int, int)>[];

          await for (final _ in client.fetch(
            serverUrl,
            onProgress: (bytes, total) {
              progressReports.add((bytes, total));
            },
          )) {
            // Drain stream
          }

          // Then: Should have progress reports
          expect(progressReports.isNotEmpty, isTrue);
          expect(progressReports.last.$1, equals(testBytes.length));
          expect(progressReports.last.$2, equals(testBytes.length));
        });

        test('should report final progress after completion', () async {
          // Given: Standard server
          setupServerWithRangeSupport();

          // When: Fetching with progress tracking
          final client = RangeRequestClient();
          var finalProgress = (0, 0);

          await for (final _ in client.fetch(
            serverUrl,
            onProgress: (bytes, total) {
              finalProgress = (bytes, total);
            },
          )) {
            // Drain stream
          }

          // Then: Final progress should be complete
          expect(finalProgress.$1, equals(testBytes.length));
          expect(finalProgress.$2, equals(testBytes.length));
        });
      });

      group('cancellation', () {
        test('should handle cancellation during fetch', () async {
          // Given: Slow server response
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', '1000');
              request.response.headers.set('accept-ranges', 'bytes');
            } else if (request.method == 'GET') {
              request.response.statusCode = 200;
              // Send data slowly
              for (var i = 0; i < 100; i++) {
                request.response.add([i]);
                await Future.delayed(const Duration(milliseconds: 50));
              }
            }
            await request.response.close();
          });

          // When: Starting fetch then cancelling
          final client = RangeRequestClient();
          final cancelToken = CancelToken();

          // Cancel after a short delay
          Timer(const Duration(milliseconds: 100), () {
            cancelToken.cancel();
          });

          // Then: Should throw cancelled exception
          expect(
            () async {
              await for (final _ in client.fetch(
                serverUrl,
                cancelToken: cancelToken,
              )) {
                // Keep fetching
              }
            },
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.cancelled)),
          );
        });

        test('should not start fetch if already cancelled', () async {
          // Given: Pre-cancelled token
          final cancelToken = CancelToken();
          cancelToken.cancel();

          // When/Then: Should throw immediately
          final client = RangeRequestClient();
          expect(
            () async {
              await for (final _ in client.fetch(
                serverUrl,
                cancelToken: cancelToken,
              )) {
                // Should not execute
              }
            },
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.cancelled)),
          );
        });
      });

      group('with custom headers', () {
        test('should include headers in all requests', () async {
          // Given: Server that checks headers
          var receivedUserAgent = '';
          server.listen((request) async {
            if (request.method == 'GET') {
              receivedUserAgent = request.headers['user-agent']?.first ?? '';
              request.response.statusCode = 200;
              request.response.add(testBytes);
            } else if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', testBytes.length.toString());
            }
            await request.response.close();
          });

          // When: Fetching with custom headers
          const config = RangeRequestConfig(
            headers: {'User-Agent': 'CustomApp/1.0'},
          );
          final client = RangeRequestClient(config: config);

          await for (final _ in client.fetch(serverUrl)) {
            break; // Just need one chunk
          }

          // Then: Should include custom header
          expect(receivedUserAgent, equals('CustomApp/1.0'));
        });
      });

      group('error handling', () {
        test('should fail after max retries for serial fetch', () async {
          // Given: Server that always fails
          server.listen((request) async {
            if (request.method == 'HEAD') {
              request.response.statusCode = 200;
              request.response.headers.set('content-length', '1000');
              request.response.headers.set('accept-ranges', 'none');
            } else if (request.method == 'GET') {
              // Always fail
              request.response.statusCode = 500;
            }
            await request.response.close();
          });

          // When/Then: Should throw after retries exhausted
          const config = RangeRequestConfig(
            maxRetries: 2,
            retryDelayMs: 10,
          );
          final client = RangeRequestClient(config: config);

          expect(
            () async {
              await for (final _ in client.fetch(serverUrl)) {
                // Try to fetch
              }
            },
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.serverError)),
          );
        });
      });
    });
  });
}