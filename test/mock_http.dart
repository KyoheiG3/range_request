import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:range_request/src/http.dart';

/// Mock implementation for testing
class MockHttp extends Http {
  final Map<String, MockResponse> _responses = {};
  final Map<String, int> _callCounts = {};
  final List<MockRequest> _requestHistory = [];

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) async {
    // Use MockClient to handle the HEAD request
    final client = createClient() as MockClient;
    try {
      return await client.head(url, headers: headers);
    } finally {
      client.close();
    }
  }

  /// Register a mock response for a URL pattern
  void registerResponse(
    String urlPattern, {
    required int statusCode,
    Map<String, String>? headers,
    dynamic body,
    Duration? delay,
  }) {
    _responses[urlPattern] = MockResponse(
      statusCode: statusCode,
      headers: headers ?? {},
      body: body,
      delay: delay,
    );
  }

  /// Register a HEAD response with common headers
  void registerHeadResponse(
    String urlPattern, {
    int statusCode = 200,
    int? contentLength,
    bool acceptRanges = true,
    String? fileName,
  }) {
    final headers = <String, String>{};
    if (contentLength != null) {
      headers['content-length'] = contentLength.toString();
    }
    if (acceptRanges) {
      headers['accept-ranges'] = 'bytes';
    }
    if (fileName != null) {
      headers['content-disposition'] = 'attachment; filename="$fileName"';
    }

    registerResponse(
      'HEAD:$urlPattern',
      statusCode: statusCode,
      headers: headers,
      body: '',
    );
  }

  /// Register a GET response with range support
  void registerRangeResponse(
    String urlPattern,
    List<int> fullData, {
    Duration? delay,
  }) {
    // Store the full data for range requests
    _responses['GET:$urlPattern:FULL'] = MockResponse(
      statusCode: 200,
      headers: {'content-length': fullData.length.toString()},
      body: fullData,
      delay: delay,
    );

    // This will be handled dynamically based on range header
    _responses['GET:$urlPattern:RANGE'] = MockResponse(
      statusCode: 206,
      headers: {},
      body: fullData, // Will be sliced based on range
      delay: delay,
    );
  }

  @override
  http.Client createClient() {
    return MockClient((request) async {
      final url = request.url.toString();
      final method = request.method;

      // Record request
      _requestHistory.add(
        MockRequest(method: method, url: url, headers: request.headers),
      );

      // Find matching response
      final response = _findResponse(method, url, request.headers);

      if (response != null) {
        // Apply delay if specified
        if (response.delay != null) {
          await Future.delayed(response.delay!);
        }

        // Check for Range header (case-insensitive)
        String? rangeHeader;
        request.headers.forEach((key, value) {
          if (key.toLowerCase() == 'range') {
            rangeHeader = value;
          }
        });

        // Handle range requests - only return 206 if explicitly a range response
        if (method == 'GET' &&
            rangeHeader != null &&
            response.statusCode == 206) {
          return _handleRangeRequest(url, rangeHeader!, response);
        }

        // Return normal response
        if (response.body is List<int>) {
          return http.Response.bytes(
            response.body as List<int>,
            response.statusCode,
            headers: response.headers,
          );
        } else if (response.body is String) {
          return http.Response(
            response.body as String,
            response.statusCode,
            headers: response.headers,
          );
        } else {
          return http.Response(
            json.encode(response.body),
            response.statusCode,
            headers: {...response.headers, 'content-type': 'application/json'},
          );
        }
      }

      // Default 404 response
      return http.Response('Not Found', 404);
    });
  }

  /// Handle range request
  http.Response _handleRangeRequest(
    String url,
    String rangeHeader,
    MockResponse response,
  ) {
    if (!rangeHeader.startsWith('bytes=')) {
      return http.Response('Invalid Range', 400);
    }

    final rangeParts = rangeHeader.substring(6).split('-');
    final start = int.parse(rangeParts[0]);

    // Handle different body types
    List<int> fullData;
    if (response.body is List<int>) {
      fullData = response.body as List<int>;
    } else if (response.body is String) {
      // For String bodies, just return 206 with the string as-is
      return http.Response(
        response.body as String,
        206,
        headers: {
          ...response.headers,
          'content-range':
              'bytes $start-$start/${(response.body as String).length}',
          'content-length': '1',
        },
      );
    } else {
      // Convert other types to JSON string
      final jsonBody = json.encode(response.body);
      return http.Response(
        jsonBody,
        206,
        headers: {
          ...response.headers,
          'content-type': 'application/json',
          'content-range': 'bytes $start-$start/${jsonBody.length}',
          'content-length': '1',
        },
      );
    }

    final end = rangeParts[1].isEmpty
        ? fullData.length - 1
        : int.parse(rangeParts[1]);

    final responseData = fullData.sublist(start, end + 1);

    return http.Response.bytes(
      responseData,
      206,
      headers: {
        ...response.headers,
        'content-range': 'bytes $start-$end/${fullData.length}',
        'content-length': responseData.length.toString(),
      },
    );
  }

  /// Find matching response
  MockResponse? _findResponse(
    String method,
    String url,
    Map<String, String> headers,
  ) {
    // Track call count
    final key = '$method:$url';
    _callCounts[key] = (_callCounts[key] ?? 0) + 1;

    // Check if request has Range header (case-insensitive)
    bool hasRangeHeader = headers.keys.any((k) => k.toLowerCase() == 'range');

    // Try exact match with method
    var response = _responses['$method:$url'];
    if (response != null) return response;

    // Try with RANGE suffix for GET with range header
    if (method == 'GET' && hasRangeHeader) {
      response = _responses['$method:$url:RANGE'];
      if (response != null) return response;
    }

    // Try without RANGE suffix for normal GET
    if (method == 'GET' && !hasRangeHeader) {
      response = _responses['$method:$url:FULL'];
      if (response != null) return response;
    }

    // Try without method prefix
    response = _responses[url];
    if (response != null) return response;

    // Try pattern matching
    for (final pattern in _responses.keys) {
      if (_matchesPattern('$method:$url', pattern) ||
          _matchesPattern(url, pattern)) {
        return _responses[pattern];
      }
    }

    return null;
  }

  /// Simple wildcard pattern matching
  bool _matchesPattern(String text, String pattern) {
    if (pattern.contains('*')) {
      final regexPattern = pattern.replaceAll('*', '.*').replaceAll('?', '.');
      return RegExp('^$regexPattern\$').hasMatch(text);
    }
    return text == pattern;
  }

  /// Get call count for specific endpoint
  int getCallCount(String method, String url) {
    return _callCounts['$method:$url'] ?? 0;
  }

  /// Get request history
  List<MockRequest> get requestHistory => _requestHistory;

  /// Reset all mocks
  void reset() {
    _responses.clear();
    _callCounts.clear();
    _requestHistory.clear();
  }
}

/// Mock response data
class MockResponse {
  final int statusCode;
  final Map<String, String> headers;
  final dynamic body;
  final Duration? delay;

  MockResponse({
    required this.statusCode,
    required this.headers,
    this.body,
    this.delay,
  });
}

/// Mock request record
class MockRequest {
  final String method;
  final String url;
  final Map<String, String> headers;

  MockRequest({required this.method, required this.url, required this.headers});
}
