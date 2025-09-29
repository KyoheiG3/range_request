import 'package:http/http.dart' as http;

/// Factory for creating HTTP clients
/// This allows for easy mocking in tests and consistent lifecycle management
abstract class Http {
  const Http();

  /// Create a new HTTP client
  /// The caller is responsible for closing the client when done
  http.Client createClient();

  /// Perform a HEAD request with automatic client lifecycle management
  Future<http.Response> head(Uri url, {Map<String, String>? headers});
}

/// Default implementation using real HTTP
class DefaultHttp extends Http {
  const DefaultHttp();

  @override
  http.Client createClient() => http.Client();

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) async {
    return http.head(url, headers: headers);
  }
}
