import 'cancel_token.dart';

/// Group of CancelTokens that can be cancelled together
class CancelTokenGroup {
  final List<CancelToken> _tokens = [];

  /// Get the number of tokens in the group
  int get length => _tokens.length;

  /// Check if any token in the group is cancelled
  bool get isAnyCancelled => _tokens.any((token) => token.isCancelled);

  /// Check if all tokens in the group are cancelled
  bool get areAllCancelled => _tokens.every((token) => token.isCancelled);

  /// Create a new CancelToken and add it to the group
  CancelToken createToken() {
    final token = CancelToken();
    _tokens.add(token);
    return token;
  }

  /// Add an existing token to the group
  void addToken(CancelToken token) {
    if (!_tokens.contains(token)) {
      _tokens.add(token);
    }
  }

  /// Remove a token from the group
  void removeToken(CancelToken token) {
    _tokens.remove(token);
  }

  /// Cancel all tokens in the group
  void cancelAll() {
    for (final token in _tokens) {
      if (!token.isCancelled) {
        token.cancel();
      }
    }
  }

  /// Clear all tokens from the group (does not cancel them)
  void clear() {
    _tokens.clear();
  }

  /// Cancel all tokens and clear the group
  void cancelAndClear() {
    cancelAll();
    clear();
  }
}
