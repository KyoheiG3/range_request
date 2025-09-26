import 'package:range_request/src/retry_handler.dart';
import 'package:test/test.dart';

void main() {
  group('RetryHandler', () {
    group('when handling errors', () {
      group('with maxRetries set to 3', () {
        late RetryHandler handler;

        setUp(() {
          // Given: A retry handler with max 3 retries
          handler = RetryHandler(maxRetries: 3, initialDelayMs: 10);
        });

        test('should allow retries up to maxRetries', () async {
          // Given: Initial state
          expect(handler.shouldRetry, isTrue);

          // When: First error occurs
          final firstRetry = await handler.handleError();
          // Then: Should allow retry
          expect(firstRetry, isTrue);
          expect(handler.shouldRetry, isTrue);

          // When: Second error occurs
          final secondRetry = await handler.handleError();
          // Then: Should allow retry
          expect(secondRetry, isTrue);
          expect(handler.shouldRetry, isTrue);

          // When: Third error occurs
          final thirdRetry = await handler.handleError();
          // Then: Should allow retry
          expect(thirdRetry, isTrue);
          expect(handler.shouldRetry, isTrue);

          // When: Fourth error occurs (exceeding max)
          final fourthRetry = await handler.handleError();
          // Then: Should not allow retry
          expect(fourthRetry, isFalse);
          expect(handler.shouldRetry, isFalse);
        });
      });

      group('with maxRetries set to 0', () {
        test('should not allow any retries', () async {
          // Given: A retry handler with no retries allowed
          final handler = RetryHandler(maxRetries: 0, initialDelayMs: 10);

          // Then: Initial attempt should be allowed
          expect(handler.shouldRetry, isTrue);

          // When: First error occurs
          final result = await handler.handleError();

          // Then: Should not allow retry
          expect(result, isFalse);
          expect(handler.shouldRetry, isFalse);
        });
      });

      group('with maxRetries set to 1', () {
        test('should allow exactly one retry', () async {
          // Given: A retry handler with single retry
          final handler = RetryHandler(maxRetries: 1, initialDelayMs: 5);

          // Then: Initial state should allow retry
          expect(handler.shouldRetry, isTrue);

          // When: First error occurs
          final firstRetry = await handler.handleError();
          // Then: Should allow retry
          expect(firstRetry, isTrue);
          expect(handler.shouldRetry, isTrue);

          // When: Second error occurs
          final secondRetry = await handler.handleError();
          // Then: Should not allow retry
          expect(secondRetry, isFalse);
          expect(handler.shouldRetry, isFalse);
        });
      });
    });

    group('exponential backoff', () {
      group('with initialDelayMs of 10ms', () {
        late RetryHandler handler;

        setUp(() {
          // Given: A retry handler with 10ms initial delay
          handler = RetryHandler(maxRetries: 3, initialDelayMs: 10);
        });

        test('should apply exponential delays correctly', () async {
          // When: First retry (2^1 * 10ms = 20ms)
          final start1 = DateTime.now();
          await handler.handleError();
          final duration1 = DateTime.now().difference(start1);

          // Then: Delay should be ~20ms
          expect(duration1.inMilliseconds, greaterThanOrEqualTo(20));

          // When: Second retry (2^2 * 10ms = 40ms)
          final start2 = DateTime.now();
          await handler.handleError();
          final duration2 = DateTime.now().difference(start2);

          // Then: Delay should be ~40ms
          expect(duration2.inMilliseconds, greaterThanOrEqualTo(40));

          // When: Third retry (2^3 * 10ms = 80ms)
          final start3 = DateTime.now();
          await handler.handleError();
          final duration3 = DateTime.now().difference(start3);

          // Then: Delay should be ~80ms
          expect(duration3.inMilliseconds, greaterThanOrEqualTo(80));
        });

        test('should calculate delays using bit shifting', () async {
          // Given: Expected delays based on bit shifting formula
          // 1 << 1 = 2, so first delay = 10 * 2 = 20ms
          // 1 << 2 = 4, so second delay = 10 * 4 = 40ms
          // 1 << 3 = 8, so third delay = 10 * 8 = 80ms
          final delays = <int>[];

          // When: Three retries occur
          for (var i = 0; i < 3; i++) {
            final start = DateTime.now();
            await handler.handleError();
            final duration = DateTime.now().difference(start).inMilliseconds;
            delays.add(duration);
          }

          // Then: Delays should match expected exponential pattern
          expect(delays[0], greaterThanOrEqualTo(20));
          expect(delays[0], lessThan(30));
          expect(delays[1], greaterThanOrEqualTo(40));
          expect(delays[1], lessThan(50));
          expect(delays[2], greaterThanOrEqualTo(80));
          expect(delays[2], lessThan(90));
        });
      });

      group('with initialDelayMs of 0ms', () {
        test('should have minimal delay', () async {
          // Given: A retry handler with no initial delay
          final handler = RetryHandler(maxRetries: 1, initialDelayMs: 0);

          // When: An error is handled
          final start = DateTime.now();
          await handler.handleError();
          final duration = DateTime.now().difference(start);

          // Then: Delay should be minimal
          expect(duration.inMilliseconds, lessThan(10));
        });
      });
    });

    group('shouldRetry state', () {
      test('should maintain state correctly through retry lifecycle', () async {
        // Given: A retry handler with 2 max retries
        final handler = RetryHandler(maxRetries: 2, initialDelayMs: 5);

        // Then: Initial state should allow retry
        expect(handler.shouldRetry, isTrue);

        // When: First error is handled
        await handler.handleError();
        // Then: Should still allow retry
        expect(handler.shouldRetry, isTrue);

        // When: Second error is handled
        await handler.handleError();
        // Then: Should still allow retry
        expect(handler.shouldRetry, isTrue);

        // When: Third error is handled (exceeding max)
        await handler.handleError();
        // Then: Should not allow retry
        expect(handler.shouldRetry, isFalse);
      });
    });

    group('edge cases', () {
      test('should handle large retry counts without performance issues', () async {
        // Given: A retry handler with many retries allowed
        final handler = RetryHandler(maxRetries: 10, initialDelayMs: 1);

        // Then: Initial state should allow retry
        expect(handler.shouldRetry, isTrue);

        // When: Many retries occur
        for (var i = 0; i < 10; i++) {
          final result = await handler.handleError();
          // Then: Each retry should be allowed
          expect(result, isTrue);
          expect(handler.shouldRetry, isTrue);
        }

        // When: One more retry beyond max
        final finalResult = await handler.handleError();
        // Then: Should not allow retry
        expect(finalResult, isFalse);
        expect(handler.shouldRetry, isFalse);
      });
    });
  });
}