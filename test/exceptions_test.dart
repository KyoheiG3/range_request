import 'package:range_request/src/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('RangeRequestException', () {
    group('when creating an exception', () {
      test('should store code and message correctly', () {
        // Given: Error code and message
        const code = RangeRequestErrorCode.networkError;
        const message = 'Network connection failed';

        // When: Exception is created
        const exception = RangeRequestException(code: code, message: message);

        // Then: Properties should match
        expect(exception.code, equals(code));
        expect(exception.message, equals(message));
      });
    });

    group('toString()', () {
      test('should format exception as readable string', () {
        // Given: An exception with server error
        const exception = RangeRequestException(
          code: RangeRequestErrorCode.serverError,
          message: 'Server returned an error',
        );

        // When: toString is called
        final result = exception.toString();

        // Then: Should format correctly with code name
        expect(
          result,
          equals(
            'RangeRequestException [serverError]: Server returned an error',
          ),
        );
      });

      group('for each error code', () {
        final testCases = [
          (RangeRequestErrorCode.networkError, 'networkError'),
          (RangeRequestErrorCode.serverError, 'serverError'),
          (RangeRequestErrorCode.invalidResponse, 'invalidResponse'),
          (RangeRequestErrorCode.fileError, 'fileError'),
          (RangeRequestErrorCode.checksumMismatch, 'checksumMismatch'),
          (RangeRequestErrorCode.unsupportedOperation, 'unsupportedOperation'),
          (RangeRequestErrorCode.cancelled, 'cancelled'),
        ];

        for (final (code, expectedName) in testCases) {
          test('should format $expectedName correctly', () {
            // Given: An exception with specific error code
            final exception = RangeRequestException(
              code: code,
              message: 'Test message',
            );

            // When: toString is called
            final result = exception.toString();

            // Then: Should include correct code name
            expect(
              result,
              equals('RangeRequestException [$expectedName]: Test message'),
            );
          });
        }
      });
    });
  });

  group('RangeRequestErrorCode', () {
    group('enum values', () {
      test('should contain all expected error codes', () {
        // Given: The RangeRequestErrorCode enum

        // When: Accessing values
        final values = RangeRequestErrorCode.values;

        // Then: Should have exactly 7 error codes
        expect(values.length, equals(7));
        expect(
          values,
          containsAll([
            RangeRequestErrorCode.networkError,
            RangeRequestErrorCode.serverError,
            RangeRequestErrorCode.invalidResponse,
            RangeRequestErrorCode.fileError,
            RangeRequestErrorCode.checksumMismatch,
            RangeRequestErrorCode.unsupportedOperation,
            RangeRequestErrorCode.cancelled,
          ]),
        );
      });

      test('should have correct name property for each code', () {
        // Given: Each error code enum value

        // When: Accessing the name property
        // Then: Should return the correct string representation
        expect(RangeRequestErrorCode.networkError.name, equals('networkError'));
        expect(RangeRequestErrorCode.serverError.name, equals('serverError'));
        expect(
          RangeRequestErrorCode.invalidResponse.name,
          equals('invalidResponse'),
        );
        expect(RangeRequestErrorCode.fileError.name, equals('fileError'));
        expect(
          RangeRequestErrorCode.checksumMismatch.name,
          equals('checksumMismatch'),
        );
        expect(
          RangeRequestErrorCode.unsupportedOperation.name,
          equals('unsupportedOperation'),
        );
        expect(RangeRequestErrorCode.cancelled.name, equals('cancelled'));
      });
    });
  });
}
