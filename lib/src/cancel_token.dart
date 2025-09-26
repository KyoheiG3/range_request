import 'package:http/http.dart' as http;

import 'exceptions.dart';

/// Token for cancelling download operations
class CancelToken {
  var _isCancelled = false;
  http.Client? _activeClient;

  /// Whether the operation has been cancelled
  bool get isCancelled => _isCancelled;

  /// Cancel the operation
  void cancel() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  /// Register a client for cancellation (used internally by fetch operations)
  void registerClient(http.Client client) {
    if (_isCancelled) {
      client.close();
    } else {
      _activeClient = client;
    }
  }

  /// Unregister the client
  void unregisterClient() {
    _activeClient = null;
  }

  /// Check if cancelled and throw exception if true
  void throwIfCancelled() {
    if (_isCancelled) {
      throw RangeRequestException(
        code: RangeRequestErrorCode.cancelled,
        message: 'Operation was cancelled',
      );
    }
  }
}
