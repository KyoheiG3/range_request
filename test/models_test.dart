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
      expect(values, containsAll([
        ChecksumType.sha256,
        ChecksumType.md5,
        ChecksumType.none,
      ]));
    });
  });

  group('DownloadStatus', () {
    test('should have all expected values', () {
      // Given: The DownloadStatus enum
      // When: Accessing values
      final values = DownloadStatus.values;

      // Then: Should have exactly 2 statuses
      expect(values.length, equals(2));
      expect(values, containsAll([
        DownloadStatus.downloading,
        DownloadStatus.calculatingChecksum,
      ]));
    });
  });

  group('FileConflictStrategy', () {
    test('should have all expected values', () {
      // Given: The FileConflictStrategy enum
      // When: Accessing values
      final values = FileConflictStrategy.values;

      // Then: Should have exactly 3 strategies
      expect(values.length, equals(3));
      expect(values, containsAll([
        FileConflictStrategy.overwrite,
        FileConflictStrategy.rename,
        FileConflictStrategy.error,
      ]));
    });
  });

  group('RangeRequestConfig', () {
    group('with default constructor', () {
      test('should have correct default values', () {
        // Given/When: Creating config with defaults
        const config = RangeRequestConfig();

        // Then: All defaults should be set correctly
        expect(config.chunkSize, equals(10 * 1024 * 1024), reason: 'Default chunk size should be 10MB');
        expect(config.maxConcurrentRequests, equals(8), reason: 'Default concurrent requests should be 8');
        expect(config.headers, equals(const {}), reason: 'Default headers should be empty');
        expect(config.maxRetries, equals(3), reason: 'Default max retries should be 3');
        expect(config.retryDelayMs, equals(1000), reason: 'Default retry delay should be 1000ms');
        expect(config.tempFileExtension, equals('.tmp'), reason: 'Default temp extension should be .tmp');
        expect(config.connectionTimeout, equals(const Duration(seconds: 30)), reason: 'Default timeout should be 30s');
      });
    });

    group('with custom values', () {
      test('should accept all custom parameters', () {
        // Given: Custom configuration values
        const customHeaders = {'Authorization': 'Bearer token'};
        const customTimeout = Duration(seconds: 60);

        // When: Creating config with custom values
        const config = RangeRequestConfig(
          chunkSize: 5 * 1024 * 1024,
          maxConcurrentRequests: 4,
          headers: customHeaders,
          maxRetries: 5,
          retryDelayMs: 2000,
          tempFileExtension: '.download',
          connectionTimeout: customTimeout,
        );

        // Then: All custom values should be set
        expect(config.chunkSize, equals(5 * 1024 * 1024));
        expect(config.maxConcurrentRequests, equals(4));
        expect(config.headers, equals(customHeaders));
        expect(config.maxRetries, equals(5));
        expect(config.retryDelayMs, equals(2000));
        expect(config.tempFileExtension, equals('.download'));
        expect(config.connectionTimeout, equals(customTimeout));
      });

      test('should support partial customization', () {
        // Given/When: Creating config with only some custom values
        const config = RangeRequestConfig(
          chunkSize: 1024,
          maxRetries: 10,
        );

        // Then: Custom values should be set, defaults should remain
        expect(config.chunkSize, equals(1024));
        expect(config.maxRetries, equals(10));
        // Defaults
        expect(config.maxConcurrentRequests, equals(8));
        expect(config.headers, equals(const {}));
        expect(config.retryDelayMs, equals(1000));
        expect(config.tempFileExtension, equals('.tmp'));
        expect(config.connectionTimeout, equals(const Duration(seconds: 30)));
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
        const info = (
          acceptRanges: false,
          contentLength: 5000,
          fileName: null,
        );

        // Then: Should handle null fileName correctly
        expect(info.acceptRanges, isFalse);
        expect(info.contentLength, equals(5000));
        expect(info.fileName, isNull);
      });
    });

    group('ChunkRange', () {
      test('should work with start and end values', () {
        // Given/When: Creating a chunk range
        const range = (
          start: 0,
          end: 1023,
        );

        // Then: Values should be accessible
        expect(range.start, equals(0));
        expect(range.end, equals(1023));
      });

      test('should work with different byte ranges', () {
        // Given/When: Creating a range in the middle of a file
        const range = (
          start: 1024,
          end: 2047,
        );

        // Then: Values should be accessible
        expect(range.start, equals(1024));
        expect(range.end, equals(2047));
      });
    });
  });
}