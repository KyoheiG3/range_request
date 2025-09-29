import 'dart:async';
import 'dart:io';

/// Test server setup helper for consistent server management
class TestServerHelper {
  HttpServer? _server;
  Uri? _serverUrl;
  final List<StreamSubscription> _subscriptions = [];

  HttpServer? get server => _server;
  Uri get serverUrl => _serverUrl ?? Uri.parse('http://localhost:0/test.txt');

  /// Creates a new server instance, closing any existing one
  Future<void> createServer() async {
    await closeServer();
    _server = await HttpServer.bind('localhost', 0);
    _serverUrl = Uri.parse('http://localhost:${_server!.port}/test.txt');
  }

  /// Closes the current server and cleans up
  Future<void> closeServer() async {
    // Cancel all subscriptions first
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Close the server
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _serverUrl = null;
    }
  }

  /// Sets up a server with the given request handler
  /// Ensures only one listener is active at a time
  Future<void> setupServer(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    if (_server == null) {
      await createServer();
    }

    // Clear any existing listeners
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Add new listener
    final subscription = _server!.listen(
      handler,
      onError: (error) {
        // Log errors instead of crashing
        print('Test server error: $error');
      },
    );
    _subscriptions.add(subscription);
  }

  /// Helper to setup server with range support
  Future<void> setupServerWithRangeSupport({
    required List<int> testBytes,
    String? fileName,
  }) async {
    await setupServer((request) async {
      try {
        if (request.method == 'HEAD') {
          request.response.statusCode = 200;
          request.response.headers.set(
            'content-length',
            testBytes.length.toString(),
          );
          request.response.headers.set('accept-ranges', 'bytes');
          if (fileName != null) {
            request.response.headers.set(
              'content-disposition',
              'attachment; filename="$fileName"',
            );
          }
        } else if (request.method == 'GET') {
          final rangeHeader = request.headers['range']?.first;

          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            // Parse range header
            final rangeParts = rangeHeader.substring(6).split('-');
            final start = int.parse(rangeParts[0]);
            final end = rangeParts[1].isEmpty
                ? testBytes.length - 1
                : int.parse(rangeParts[1]);

            request.response.statusCode = 206;
            request.response.headers.set(
              'content-range',
              'bytes $start-$end/${testBytes.length}',
            );
            request.response.headers.set(
              'content-length',
              '${end - start + 1}',
            );
            request.response.add(testBytes.sublist(start, end + 1));
          } else {
            // Full content response
            request.response.statusCode = 200;
            request.response.headers.set(
              'content-length',
              testBytes.length.toString(),
            );
            request.response.add(testBytes);
          }
        }
        await request.response.close();
      } catch (e) {
        // Ensure response is closed even on error
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  /// Helper to setup server without range support
  Future<void> setupServerWithoutRangeSupport({
    required List<int> testBytes,
  }) async {
    await setupServer((request) async {
      try {
        if (request.method == 'HEAD') {
          request.response.statusCode = 200;
          request.response.headers.set(
            'content-length',
            testBytes.length.toString(),
          );
          request.response.headers.set('accept-ranges', 'none');
        } else if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.add(testBytes);
        }
        await request.response.close();
      } catch (e) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  /// Helper to setup server with custom response behavior
  Future<void> setupCustomServer({
    required Future<void> Function(HttpRequest request, RequestTracker tracker)
    handler,
  }) async {
    final tracker = RequestTracker();

    await setupServer((request) async {
      await handler(request, tracker);
    });
  }
}

/// Tracks request counts and details for assertions
class RequestTracker {
  int headRequestCount = 0;
  int getRequestCount = 0;
  int totalRequestCount = 0;
  final List<String> requestPaths = [];
  final List<String> requestMethods = [];
  final Map<String, String> lastRequestHeaders = {};

  void trackRequest(HttpRequest request) {
    totalRequestCount++;
    requestPaths.add(request.uri.path);
    requestMethods.add(request.method);

    // Track headers
    request.headers.forEach((name, values) {
      lastRequestHeaders[name] = values.join(', ');
    });

    // Count by method
    switch (request.method) {
      case 'HEAD':
        headRequestCount++;
        break;
      case 'GET':
        getRequestCount++;
        break;
    }
  }

  void reset() {
    headRequestCount = 0;
    getRequestCount = 0;
    totalRequestCount = 0;
    requestPaths.clear();
    requestMethods.clear();
    lastRequestHeaders.clear();
  }
}

/// Helper to wait for a condition with timeout
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 10),
}) async {
  final stopwatch = Stopwatch()..start();

  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Condition not met within timeout');
    }
    await Future.delayed(pollInterval);
  }
}
