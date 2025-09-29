import 'dart:io';
import 'test_helpers.dart';

/// Extension to make migration easier
extension TestServerHelperCompat on TestServerHelper {
  HttpServer get server => _server!;
  set server(HttpServer value) => _server = value;

  Uri get serverUrl => _serverUrl ?? Uri.parse('http://localhost:0/test.txt');
  set serverUrl(Uri value) => _serverUrl = value;

  HttpServer? get _server => this.server;
  set _server(HttpServer? value) {
    // This is handled internally
  }

  Uri? get _serverUrl => this.serverUrl;
  set _serverUrl(Uri? value) {
    // This is handled internally
  }
}
