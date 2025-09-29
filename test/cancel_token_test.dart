import 'package:http/http.dart' as http;
import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('CancelToken', () {
    late CancelToken cancelToken;

    setUp(() {
      cancelToken = CancelToken();
    });

    group('initial state', () {
      test('should not be cancelled', () {
        // Given: A new cancel token
        // When: Checking initial state
        // Then: Should not be cancelled
        expect(cancelToken.isCancelled, isFalse);
      });

      test('should not throw when checking if cancelled', () {
        // Given: A new cancel token
        // When: Checking if cancelled
        // Then: Should not throw
        expect(() => cancelToken.throwIfCancelled(), returnsNormally);
      });
    });

    group('when cancel is called', () {
      test('should update cancelled state', () {
        // Given: An uncancelled token
        expect(cancelToken.isCancelled, isFalse);

        // When: Cancel is called
        cancelToken.cancel();

        // Then: Should be marked as cancelled
        expect(cancelToken.isCancelled, isTrue);
      });

      test('should handle multiple cancel calls gracefully', () {
        // Given: A token that has been cancelled once
        cancelToken.cancel();
        expect(cancelToken.isCancelled, isTrue);

        // When: Cancel is called again
        cancelToken.cancel();

        // Then: Should remain cancelled without errors
        expect(cancelToken.isCancelled, isTrue);
      });

      test('should throw exception when throwIfCancelled is called', () {
        // Given: A cancelled token
        cancelToken.cancel();

        // When/Then: throwIfCancelled should throw appropriate exception
        expect(
          () => cancelToken.throwIfCancelled(),
          throwsA(
            isA<RangeRequestException>()
                .having((e) => e.code, 'code', RangeRequestErrorCode.cancelled)
                .having((e) => e.message, 'message', 'Operation was cancelled'),
          ),
        );
      });
    });

    group('client management', () {
      group('when registering a client', () {
        test('should close client when cancelled', () {
          // Given: A mock client and cancel token
          var clientClosed = false;
          final client = _MockHttpClient(() {
            clientClosed = true;
          });

          // When: Client is registered and then cancelled
          cancelToken.registerClient(client);
          expect(clientClosed, isFalse);

          cancelToken.cancel();

          // Then: Client should be closed
          expect(clientClosed, isTrue);
        });

        test('should close client immediately if already cancelled', () {
          // Given: A cancelled token
          var clientClosed = false;
          final client = _MockHttpClient(() {
            clientClosed = true;
          });
          cancelToken.cancel();

          // When: A client is registered after cancellation
          cancelToken.registerClient(client);

          // Then: Client should be closed immediately
          expect(clientClosed, isTrue);
        });

        test('should only close the most recently registered client', () {
          // Given: Two mock clients
          var firstClientClosed = false;
          var secondClientClosed = false;
          final firstClient = _MockHttpClient(() {
            firstClientClosed = true;
          });
          final secondClient = _MockHttpClient(() {
            secondClientClosed = true;
          });

          // When: Both clients are registered sequentially
          cancelToken.registerClient(firstClient);
          cancelToken.registerClient(secondClient);
          cancelToken.cancel();

          // Then: Only the second (most recent) client should be closed
          expect(firstClientClosed, isFalse);
          expect(secondClientClosed, isTrue);
        });
      });

      group('when unregistering a client', () {
        test('should not close unregistered client on cancel', () {
          // Given: A registered client
          var clientClosed = false;
          final client = _MockHttpClient(() {
            clientClosed = true;
          });

          // When: Client is registered, then unregistered, then cancelled
          cancelToken.registerClient(client);
          cancelToken.unregisterClient();
          cancelToken.cancel();

          // Then: Client should not be closed
          expect(clientClosed, isFalse);
        });
      });
    });

    group('after cancellation', () {
      setUp(() {
        cancelToken.cancel();
      });

      test('should clear active client reference', () {
        // Given: A cancelled token with a previously registered client
        var firstClientClosed = false;
        var secondClientClosed = false;

        final firstClient = _MockHttpClient(() {
          firstClientClosed = true;
        });
        final secondClient = _MockHttpClient(() {
          secondClientClosed = true;
        });

        // When: First client was registered before cancel
        CancelToken newToken = CancelToken();
        newToken.registerClient(firstClient);
        newToken.cancel();
        expect(firstClientClosed, isTrue);

        // When: Another client is registered after cancellation
        newToken.registerClient(secondClient);

        // Then: Second client should also be closed immediately
        expect(secondClientClosed, isTrue);
      });
    });
  });
}

// Mock HTTP client for testing
class _MockHttpClient implements http.Client {
  final void Function() onClose;

  _MockHttpClient(this.onClose);

  @override
  void close() => onClose();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError();
  }
}
