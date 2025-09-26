/// Error codes for range request operations
enum RangeRequestErrorCode {
  networkError,
  serverError,
  invalidResponse,
  fileError,
  checksumMismatch,
  unsupportedOperation,
  cancelled,
}

/// Exception thrown by range request operations
class RangeRequestException implements Exception {
  /// Error code for categorizing the exception
  final RangeRequestErrorCode code;

  /// Human-readable error message
  final String message;

  const RangeRequestException({required this.code, required this.message});

  @override
  String toString() {
    return 'RangeRequestException [${code.name}]: $message';
  }
}
