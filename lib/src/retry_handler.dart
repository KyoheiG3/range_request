/// Handles retry logic for failed operations
class RetryHandler {
  final int maxRetries;
  final int initialDelayMs;
  int _attempts = 0;

  RetryHandler({required this.maxRetries, required this.initialDelayMs});

  /// Handles an error - returns true if retrying should continue, false if max retries have been exceeded
  Future<bool> handleError() async {
    _attempts++;
    if (_attempts > maxRetries) {
      return false; // Should rethrow
    }

    // Exponential backoff: initialDelay * (2^attempt_number), starting with 2^1
    final delayMs = initialDelayMs * (1 << _attempts); // 1 << n is 2^n
    await Future.delayed(Duration(milliseconds: delayMs));
    return true; // Continue retrying
  }

  /// Whether retry should continue
  bool get shouldRetry => _attempts <= maxRetries;
}
