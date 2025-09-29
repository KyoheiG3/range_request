import 'package:range_request/src/models.dart';
import 'package:test/test.dart';

void main() {
  group('ChecksumType', () {
    test('should have all expected values', () {
      // Given: The ChecksumType enum
      // When: Accessing values
      final values = ChecksumType.values;

      // Then: Should have exactly 3 types
      expect(values.length, equals(3));
      expect(
        values,
        containsAll([ChecksumType.sha256, ChecksumType.md5, ChecksumType.none]),
      );
    });
  });

  group('DownloadStatus', () {
    test('should have all expected values', () {
      // Given: The DownloadStatus enum
      // When: Accessing values
      final values = DownloadStatus.values;

      // Then: Should have exactly 2 statuses
      expect(values.length, equals(2));
      expect(
        values,
        containsAll([
          DownloadStatus.downloading,
          DownloadStatus.calculatingChecksum,
        ]),
      );
    });
  });

  group('FileConflictStrategy', () {
    test('should have all expected values', () {
      // Given: The FileConflictStrategy enum
      // When: Accessing values
      final values = FileConflictStrategy.values;

      // Then: Should have exactly 3 strategies
      expect(values.length, equals(3));
      expect(
        values,
        containsAll([
          FileConflictStrategy.overwrite,
          FileConflictStrategy.rename,
          FileConflictStrategy.error,
        ]),
      );
    });
  });

  group('RangeRequestConfig', () {
    group('with default constructor', () {
      test('should have correct default values', () {
        // Given/When: Creating config with defaults
        const config = RangeRequestConfig();

        // Then: All defaults should be set correctly
        expect(
          config.chunkSize,
          equals(10 * 1024 * 1024),
          reason: 'Default chunk size should be 10MB',
        );
        expect(
          config.maxConcurrentRequests,
          equals(8),
          reason: 'Default concurrent requests should be 8',
        );
        expect(
          config.headers,
          equals(const {}),
          reason: 'Default headers should be empty',
        );
        expect(
          config.maxRetries,
          equals(3),
          reason: 'Default max retries should be 3',
        );
        expect(
          config.retryDelayMs,
          equals(1000),
          reason: 'Default retry delay should be 1000ms',
        );
        expect(
          config.tempFileExtension,
          equals('.tmp'),
          reason: 'Default temp extension should be .tmp',
        );
        expect(
          config.connectionTimeout,
          equals(const Duration(seconds: 30)),
          reason: 'Default timeout should be 30s',
        );
        expect(
          config.progressInterval,
          equals(const Duration(milliseconds: 500)),
          reason: 'Default progress interval should be 500ms',
        );
      });
    });

    group('with custom values', () {
      test('should accept all custom parameters', () {
        // Given: Custom configuration values
        const customHeaders = {'Authorization': 'Bearer token'};
        const customTimeout = Duration(seconds: 60);
        const customProgressInterval = Duration(milliseconds: 100);

        // When: Creating config with custom values
        const config = RangeRequestConfig(
          chunkSize: 5 * 1024 * 1024,
          maxConcurrentRequests: 4,
          headers: customHeaders,
          maxRetries: 5,
          retryDelayMs: 2000,
          tempFileExtension: '.download',
          connectionTimeout: customTimeout,
          progressInterval: customProgressInterval,
        );

        // Then: All custom values should be set
        expect(config.chunkSize, equals(5 * 1024 * 1024));
        expect(config.maxConcurrentRequests, equals(4));
        expect(config.headers, equals(customHeaders));
        expect(config.maxRetries, equals(5));
        expect(config.retryDelayMs, equals(2000));
        expect(config.tempFileExtension, equals('.download'));
        expect(config.connectionTimeout, equals(customTimeout));
        expect(config.progressInterval, equals(customProgressInterval));
      });

      test('should support partial customization', () {
        // Given/When: Creating config with only some custom values
        const config = RangeRequestConfig(chunkSize: 1024, maxRetries: 10);

        // Then: Custom values should be set, defaults should remain
        expect(config.chunkSize, equals(1024));
        expect(config.maxRetries, equals(10));
        // Defaults
        expect(config.maxConcurrentRequests, equals(8));
        expect(config.headers, equals(const {}));
        expect(config.retryDelayMs, equals(1000));
        expect(config.tempFileExtension, equals('.tmp'));
        expect(config.connectionTimeout, equals(const Duration(seconds: 30)));
        expect(
          config.progressInterval,
          equals(const Duration(milliseconds: 500)),
        );
      });
    });

    group('edge cases', () {
      test('should accept minimum values', () {
        // Given/When: Creating config with minimum values
        const config = RangeRequestConfig(
          chunkSize: 1,
          maxConcurrentRequests: 1,
          maxRetries: 0,
          retryDelayMs: 0,
          tempFileExtension: '',
          connectionTimeout: Duration.zero,
        );

        // Then: Minimum values should be accepted
        expect(config.chunkSize, equals(1));
        expect(config.maxConcurrentRequests, equals(1));
        expect(config.maxRetries, equals(0));
        expect(config.retryDelayMs, equals(0));
        expect(config.tempFileExtension, isEmpty);
        expect(config.connectionTimeout, equals(Duration.zero));
      });

      test('should accept large values', () {
        // Given/When: Creating config with large values
        const config = RangeRequestConfig(
          chunkSize: 1024 * 1024 * 1024, // 1GB
          maxConcurrentRequests: 100,
          maxRetries: 1000,
          retryDelayMs: 60000,
          connectionTimeout: Duration(hours: 1),
        );

        // Then: Large values should be accepted
        expect(config.chunkSize, equals(1024 * 1024 * 1024));
        expect(config.maxConcurrentRequests, equals(100));
        expect(config.maxRetries, equals(1000));
        expect(config.retryDelayMs, equals(60000));
        expect(config.connectionTimeout, equals(const Duration(hours: 1)));
      });

      test('should handle complex headers', () {
        // Given: Multiple header entries
        const headers = {
          'Authorization': 'Bearer token',
          'User-Agent': 'MyApp/1.0',
          'X-Custom-Header': 'value',
          'Accept': 'application/json',
        };

        // When: Creating config with multiple headers
        const config = RangeRequestConfig(headers: headers);

        // Then: All headers should be preserved
        expect(config.headers.length, equals(4));
        expect(config.headers['Authorization'], equals('Bearer token'));
        expect(config.headers['User-Agent'], equals('MyApp/1.0'));
        expect(config.headers['X-Custom-Header'], equals('value'));
        expect(config.headers['Accept'], equals('application/json'));
      });
    });

    group('copyWith method', () {
      test('should create new instance with updated fields', () {
        // Given: Original config
        const original = RangeRequestConfig();

        // When: Using copyWith to update some fields
        final updated = original.copyWith(
          chunkSize: 5 * 1024 * 1024,
          maxRetries: 10,
          progressInterval: const Duration(seconds: 1),
        );

        // Then: Updated fields should be changed, others should remain
        expect(updated.chunkSize, equals(5 * 1024 * 1024));
        expect(updated.maxRetries, equals(10));
        expect(updated.progressInterval, equals(const Duration(seconds: 1)));
        // Unchanged fields
        expect(
          updated.maxConcurrentRequests,
          equals(original.maxConcurrentRequests),
        );
        expect(updated.headers, equals(original.headers));
        expect(updated.retryDelayMs, equals(original.retryDelayMs));
        expect(updated.tempFileExtension, equals(original.tempFileExtension));
        expect(updated.connectionTimeout, equals(original.connectionTimeout));
      });

      test('should preserve all fields when no arguments provided', () {
        // Given: Original config with custom values
        const original = RangeRequestConfig(
          chunkSize: 1024,
          maxConcurrentRequests: 2,
          headers: {'key': 'value'},
          maxRetries: 5,
          retryDelayMs: 500,
          tempFileExtension: '.part',
          connectionTimeout: Duration(seconds: 10),
          progressInterval: Duration(seconds: 2),
        );

        // When: Using copyWith with no arguments
        final copy = original.copyWith();

        // Then: All fields should be identical
        expect(copy.chunkSize, equals(original.chunkSize));
        expect(
          copy.maxConcurrentRequests,
          equals(original.maxConcurrentRequests),
        );
        expect(copy.headers, equals(original.headers));
        expect(copy.maxRetries, equals(original.maxRetries));
        expect(copy.retryDelayMs, equals(original.retryDelayMs));
        expect(copy.tempFileExtension, equals(original.tempFileExtension));
        expect(copy.connectionTimeout, equals(original.connectionTimeout));
        expect(copy.progressInterval, equals(original.progressInterval));
      });

      test('should update all fields when all arguments provided', () {
        // Given: Original config
        const original = RangeRequestConfig();
        const newHeaders = {'Authorization': 'Bearer xyz'};

        // When: Using copyWith to update all fields
        final updated = original.copyWith(
          chunkSize: 2048,
          maxConcurrentRequests: 16,
          headers: newHeaders,
          maxRetries: 6,
          retryDelayMs: 3000,
          tempFileExtension: '.downloading',
          connectionTimeout: const Duration(minutes: 2),
          progressInterval: const Duration(milliseconds: 250),
        );

        // Then: All fields should be updated
        expect(updated.chunkSize, equals(2048));
        expect(updated.maxConcurrentRequests, equals(16));
        expect(updated.headers, equals(newHeaders));
        expect(updated.maxRetries, equals(6));
        expect(updated.retryDelayMs, equals(3000));
        expect(updated.tempFileExtension, equals('.downloading'));
        expect(updated.connectionTimeout, equals(const Duration(minutes: 2)));
        expect(
          updated.progressInterval,
          equals(const Duration(milliseconds: 250)),
        );
      });

      test('should handle headers update correctly', () {
        // Given: Original config with headers
        const original = RangeRequestConfig(headers: {'X-Original': 'value'});

        // When: Updating headers
        final updated = original.copyWith(headers: {'X-New': 'new-value'});

        // Then: Headers should be replaced entirely
        expect(updated.headers, equals({'X-New': 'new-value'}));
        expect(updated.headers.containsKey('X-Original'), isFalse);
      });

      test('should create new instance (not modify original)', () {
        // Given: Original config
        const original = RangeRequestConfig(chunkSize: 1000);

        // When: Creating a copy with changes
        final copy = original.copyWith(chunkSize: 2000);

        // Then: Original should be unchanged
        expect(original.chunkSize, equals(1000));
        expect(copy.chunkSize, equals(2000));
        expect(identical(original, copy), isFalse);
      });
    });
  });

  group('Record types', () {
    group('DownloadResult', () {
      test('should work with all fields populated', () {
        // Given/When: Creating a download result with all fields
        const result = (
          filePath: '/downloads/file.txt',
          fileSize: 1024,
          checksum: 'abc123',
          checksumType: ChecksumType.sha256,
        );

        // Then: All fields should be accessible
        expect(result.filePath, equals('/downloads/file.txt'));
        expect(result.fileSize, equals(1024));
        expect(result.checksum, equals('abc123'));
        expect(result.checksumType, equals(ChecksumType.sha256));
      });

      test('should work with null checksum', () {
        // Given/When: Creating a result without checksum
        const result = (
          filePath: '/downloads/file.txt',
          fileSize: 2048,
          checksum: null,
          checksumType: ChecksumType.none,
        );

        // Then: Should handle null checksum correctly
        expect(result.filePath, equals('/downloads/file.txt'));
        expect(result.fileSize, equals(2048));
        expect(result.checksum, isNull);
        expect(result.checksumType, equals(ChecksumType.none));
      });
    });

    group('ServerInfo', () {
      test('should work with all fields populated', () {
        // Given/When: Creating server info with all fields
        const info = (
          acceptRanges: true,
          contentLength: 1000000,
          fileName: 'document.pdf',
        );

        // Then: All fields should be accessible
        expect(info.acceptRanges, isTrue);
        expect(info.contentLength, equals(1000000));
        expect(info.fileName, equals('document.pdf'));
      });

      test('should work with null fileName', () {
        // Given/When: Creating server info without file name
        const info = (acceptRanges: false, contentLength: 5000, fileName: null);

        // Then: Should handle null fileName correctly
        expect(info.acceptRanges, isFalse);
        expect(info.contentLength, equals(5000));
        expect(info.fileName, isNull);
      });
    });

    group('ChunkRange', () {
      test('should work with start and end values', () {
        // Given/When: Creating a chunk range
        const range = (start: 0, end: 1023);

        // Then: Values should be accessible
        expect(range.start, equals(0));
        expect(range.end, equals(1023));
      });

      test('should work with different byte ranges', () {
        // Given/When: Creating a range in the middle of a file
        const range = (start: 1024, end: 2047);

        // Then: Values should be accessible
        expect(range.start, equals(1024));
        expect(range.end, equals(2047));
      });
    });
  });
}
