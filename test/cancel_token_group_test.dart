import 'package:range_request/range_request.dart';
import 'package:test/test.dart';

void main() {
  group('CancelTokenGroup', () {
    late CancelTokenGroup tokenGroup;

    setUp(() {
      tokenGroup = CancelTokenGroup();
    });

    group('token management', () {
      test('should create and track new tokens', () {
        // When: Creating tokens
        final token1 = tokenGroup.createToken();
        final token2 = tokenGroup.createToken();
        final token3 = tokenGroup.createToken();

        // Then: All tokens should be tracked
        expect(tokenGroup.length, equals(3));
        expect(token1.isCancelled, isFalse);
        expect(token2.isCancelled, isFalse);
        expect(token3.isCancelled, isFalse);
      });

      test('should add existing tokens to tokenGroup', () {
        // Given: Existing tokens
        final externalToken1 = CancelToken();
        final externalToken2 = CancelToken();

        // When: Adding to tokenGroup
        tokenGroup.addToken(externalToken1);
        tokenGroup.addToken(externalToken2);

        // Then: Tokens should be tracked
        expect(tokenGroup.length, equals(2));
      });

      test('should not add duplicate tokens', () {
        // Given: A token
        final token = CancelToken();

        // When: Adding the same token multiple times
        tokenGroup.addToken(token);
        tokenGroup.addToken(token);
        tokenGroup.addToken(token);

        // Then: Token should only be added once
        expect(tokenGroup.length, equals(1));
      });

      test('should remove tokens from tokenGroup', () {
        // Given: Tokens in tokenGroup
        tokenGroup.createToken();
        final token2 = tokenGroup.createToken();
        tokenGroup.createToken();

        // When: Removing a token
        tokenGroup.removeToken(token2);

        // Then: Token should be removed
        expect(tokenGroup.length, equals(2));
      });

      test('should clear all tokens without cancelling', () {
        // Given: Tokens in tokenGroup
        final token1 = tokenGroup.createToken();
        final token2 = tokenGroup.createToken();

        // When: Clearing the tokenGroup
        tokenGroup.clear();

        // Then: Group should be empty but tokens not cancelled
        expect(tokenGroup.length, equals(0));
        expect(token1.isCancelled, isFalse);
        expect(token2.isCancelled, isFalse);
      });
    });

    group('cancellation', () {
      test('should cancel all tokens in tokenGroup', () {
        // Given: Multiple tokens
        final token1 = tokenGroup.createToken();
        final token2 = tokenGroup.createToken();
        final token3 = tokenGroup.createToken();

        // When: Cancelling all
        tokenGroup.cancelAll();

        // Then: All tokens should be cancelled
        expect(token1.isCancelled, isTrue);
        expect(token2.isCancelled, isTrue);
        expect(token3.isCancelled, isTrue);
      });

      test('should handle mixed cancelled and active tokens', () {
        // Given: Some cancelled and some active tokens
        final token1 = tokenGroup.createToken();
        final token2 = tokenGroup.createToken();
        final token3 = tokenGroup.createToken();
        token2.cancel(); // Cancel one token manually

        // When: Cancelling all
        tokenGroup.cancelAll();

        // Then: All should be cancelled
        expect(token1.isCancelled, isTrue);
        expect(token2.isCancelled, isTrue);
        expect(token3.isCancelled, isTrue);
      });

      test('should cancel and clear tokens', () {
        // Given: Tokens in tokenGroup
        final token1 = tokenGroup.createToken();
        final token2 = tokenGroup.createToken();

        // When: Cancel and clear
        tokenGroup.cancelAndClear();

        // Then: Tokens cancelled and tokenGroup empty
        expect(token1.isCancelled, isTrue);
        expect(token2.isCancelled, isTrue);
        expect(tokenGroup.length, equals(0));
      });
    });

    group('status checking', () {
      test('should detect if any token is cancelled', () {
        // Given: Multiple tokens
        tokenGroup.createToken();
        final token2 = tokenGroup.createToken();
        tokenGroup.createToken();

        // Initially none cancelled
        expect(tokenGroup.isAnyCancelled, isFalse);

        // When: Cancelling one token
        token2.cancel();

        // Then: Should detect at least one is cancelled
        expect(tokenGroup.isAnyCancelled, isTrue);
        expect(tokenGroup.areAllCancelled, isFalse);
      });

      test('should detect if all tokens are cancelled', () {
        // Given: Multiple tokens
        tokenGroup.createToken();
        tokenGroup.createToken();
        tokenGroup.createToken();

        // Initially none cancelled
        expect(tokenGroup.areAllCancelled, isFalse);

        // When: Cancelling all tokens
        tokenGroup.cancelAll();

        // Then: Should detect all are cancelled
        expect(tokenGroup.areAllCancelled, isTrue);
        expect(tokenGroup.isAnyCancelled, isTrue);
      });

      test('should handle empty group status checks', () {
        // Given: Empty group
        // Then: Empty group has no cancelled tokens
        expect(tokenGroup.isAnyCancelled, isFalse);
        expect(
          tokenGroup.areAllCancelled,
          isTrue,
        ); // Empty list returns true for 'every'
      });
    });

    group('integration scenarios', () {
      test('should support concurrent download management', () {
        // Simulate managing multiple downloads
        final download1 = tokenGroup.createToken();
        final download2 = tokenGroup.createToken();
        final download3 = tokenGroup.createToken();

        // Check initial state
        expect(tokenGroup.length, equals(3));
        expect(tokenGroup.isAnyCancelled, isFalse);

        // Simulate one download completing (remove from tokenGroup)
        tokenGroup.removeToken(download1);
        expect(tokenGroup.length, equals(2));

        // Cancel remaining downloads
        tokenGroup.cancelAll();
        expect(download2.isCancelled, isTrue);
        expect(download3.isCancelled, isTrue);
        expect(download1.isCancelled, isFalse); // Not cancelled since removed
      });

      test('should support tokenGrouped operations with external tokens', () {
        // Given: Mix of internal and external tokens
        final internal1 = tokenGroup.createToken();
        final internal2 = tokenGroup.createToken();
        final external = CancelToken();
        tokenGroup.addToken(external);

        // When: Cancelling all
        tokenGroup.cancelAll();

        // Then: All tokens in tokenGroup are cancelled
        expect(internal1.isCancelled, isTrue);
        expect(internal2.isCancelled, isTrue);
        expect(external.isCancelled, isTrue);
      });
    });
  });
}
