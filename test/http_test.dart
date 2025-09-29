import 'package:http/http.dart';
import 'package:range_request/src/http.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultHttp', () {
    late DefaultHttp defaultHttp;

    setUp(() {
      defaultHttp = const DefaultHttp();
    });

    group('createClient', () {
      test('should create a new HTTP client', () {
        // When: Creating a client
        final client = defaultHttp.createClient();

        // Then: Should return a valid client
        expect(client, isNotNull);
        expect(client, isA<Client>());

        // Clean up
        client.close();
      });

      test('should create independent client instances', () {
        // When: Creating multiple clients
        final client1 = defaultHttp.createClient();
        final client2 = defaultHttp.createClient();

        // Then: Should be different instances
        expect(client1, isNot(same(client2)));

        // Clean up
        client1.close();
        client2.close();
      });
    });

    group('head', () {
      test('should be able to call head method', () {
        // Given: DefaultHttp instance
        final defaultHttp = const DefaultHttp();

        // Then: Should have head method available
        expect(defaultHttp.head, isNotNull);
      });

      test('should return const constructor instance', () {
        // Given/When: Creating multiple instances
        const http1 = DefaultHttp();
        const http2 = DefaultHttp();

        // Then: Should be the same instance due to const
        expect(identical(http1, http2), isTrue);
      });

      test('should throw ArgumentError for invalid URL', () async {
        // Given: DefaultHttp instance and invalid URL
        final defaultHttp = const DefaultHttp();
        final invalidUrl = Uri.parse('not-a-valid-url');

        // When/Then: Calling head with invalid URL should throw ArgumentError
        await expectLater(defaultHttp.head(invalidUrl), throwsArgumentError);
      });

      test('should handle network errors gracefully', () async {
        // Given: DefaultHttp instance and unreachable URL
        final defaultHttp = const DefaultHttp();
        final unreachableUrl = Uri.parse('http://192.0.2.1:12345/unreachable');

        // When/Then: Calling head on unreachable host should throw
        await expectLater(
          defaultHttp
              .head(unreachableUrl)
              .timeout(
                const Duration(milliseconds: 100),
                onTimeout: () => throw Exception('Connection timeout'),
              ),
          throwsException,
        );
      });
    });
  });
}
