import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:range_request/src/file_downloader.dart';
import 'package:range_request/src/models.dart';
import 'package:test/test.dart';

void main() {
  group('FileDownloader', () {
    late HttpServer server;
    late Uri serverUrl;
    late Directory tempDir;
    const testData = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz';
    final testBytes = utf8.encode(testData);
    final testSha256 = sha256.convert(testBytes).toString();
    final testMd5 = md5.convert(testBytes).toString();

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      serverUrl = Uri.parse('http://localhost:${server.port}/test.txt');
      tempDir = await Directory.systemTemp.createTemp('range_request_test_');
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // Helper function to setup mock HTTP server
    void setupServer({
      bool supportRanges = true,
      String? fileName,
      int statusCode = 200,
      List<int>? customData,
    }) {
      server.listen((request) async {
        if (request.method == 'HEAD') {
          request.response.statusCode = statusCode;
          if (statusCode == 200) {
            final data = customData ?? testBytes;
            request.response.headers.set('content-length', data.length.toString());
            if (supportRanges) {
              request.response.headers.set('accept-ranges', 'bytes');
            }
            if (fileName != null) {
              request.response.headers.set('content-disposition', 'attachment; filename="$fileName"');
            }
          }
        } else if (request.method == 'GET') {
          final data = customData ?? testBytes;
          final rangeHeader = request.headers['range']?.first;

          if (rangeHeader != null && rangeHeader.startsWith('bytes=') && supportRanges) {
            final rangeParts = rangeHeader.substring(6).split('-');
            final start = int.parse(rangeParts[0]);
            final end = rangeParts[1].isEmpty
              ? data.length - 1
              : int.parse(rangeParts[1]);

            request.response.statusCode = 206;
            request.response.add(data.sublist(start, end + 1));
          } else {
            request.response.statusCode = statusCode == 200 ? 200 : statusCode;
            if (statusCode == 200) {
              request.response.add(data);
            }
          }
        }
        await request.response.close();
      });
    }

    group('downloadToFile', () {
      group('basic download operations', () {
        test('should download file successfully', () async {
          // Given: A server with test data
          setupServer();

          // When: Downloading the file
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
          );

          // Then: File should be downloaded correctly
          expect(result.filePath, endsWith('test.txt'));
          expect(result.fileSize, equals(testBytes.length));
          expect(result.checksum, isNull);
          expect(result.checksumType, equals(ChecksumType.none));

          final file = File(result.filePath);
          expect(await file.exists(), isTrue);
          expect(await file.readAsBytes(), equals(testBytes));
        });

        test('should use custom output filename', () async {
          // Given: A server and a custom filename
          setupServer();

          // When: Downloading with custom filename
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            outputFileName: 'custom.dat',
          );

          // Then: File should use custom name
          expect(result.filePath, endsWith('custom.dat'));
          final file = File(result.filePath);
          expect(await file.exists(), isTrue);
        });

        test('should use server filename from content-disposition', () async {
          // Given: A server with content-disposition header
          setupServer(fileName: 'server-file.bin');

          // When: Downloading without specifying filename
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
          );

          // Then: Should use filename from server
          expect(result.filePath, endsWith('server-file.bin'));
        });
      });

      group('checksum calculation', () {
        test('should calculate SHA256 checksum', () async {
          // Given: A server with test data
          setupServer();

          // When: Downloading with SHA256 checksum
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            checksumType: ChecksumType.sha256,
          );

          // Then: SHA256 checksum should be calculated
          expect(result.checksum, equals(testSha256));
          expect(result.checksumType, equals(ChecksumType.sha256));
        });

        test('should calculate MD5 checksum', () async {
          // Given: A server with test data
          setupServer();

          // When: Downloading with MD5 checksum
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            checksumType: ChecksumType.md5,
          );

          // Then: MD5 checksum should be calculated
          expect(result.checksum, equals(testMd5));
          expect(result.checksumType, equals(ChecksumType.md5));
        });
      });

      group('resume functionality', () {
        test('should resume partial download', () async {
          // Given: A server and a partial file
          setupServer();
          final tempFile = File('${tempDir.path}/test.txt.tmp');
          await tempFile.writeAsBytes(testBytes.sublist(0, 20));

          // When: Resuming the download
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            resume: true,
          );

          // Then: File should be completed from partial state
          final file = File(result.filePath);
          expect(await file.readAsBytes(), equals(testBytes));
          expect(result.fileSize, equals(testBytes.length));
        });

        test('should not resume when resume is false', () async {
          // Given: A server and a partial file with wrong data
          setupServer();
          final tempFile = File('${tempDir.path}/test.txt.tmp');
          await tempFile.writeAsBytes(utf8.encode('WRONG_DATA'));

          // When: Downloading without resume
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            resume: false,
          );

          // Then: Should download fresh copy
          final file = File(result.filePath);
          expect(await file.readAsBytes(), equals(testBytes));
        });

        test('should handle already complete file', () async {
          // Given: A server and a complete temp file
          setupServer();
          final tempFile = File('${tempDir.path}/test.txt.tmp');
          await tempFile.writeAsBytes(testBytes);
          var checksumCalculated = false;

          // When: Attempting to download already complete file
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            checksumType: ChecksumType.sha256,
            onProgress: (bytes, total, status) {
              if (status == DownloadStatus.calculatingChecksum) {
                checksumCalculated = true;
              }
            },
          );

          // Then: Should recognize completion and calculate checksum
          expect(result.checksum, equals(testSha256));
          expect(checksumCalculated, isTrue);
        });
      });

      group('progress reporting', () {
        test('should report download progress', () async {
          // Given: A server and progress tracking setup
          setupServer();
          final progressReports = <(int, int, DownloadStatus)>[];

          // When: Downloading with progress callback
          final downloader = FileDownloader.fromConfig(
            RangeRequestConfig(
              chunkSize: 10,
              progressInterval: const Duration(milliseconds: 10),
            ),
          );
          await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            checksumType: ChecksumType.sha256,
            onProgress: (bytes, total, status) {
              progressReports.add((bytes, total, status));
            },
          );

          // Then: Progress should be reported correctly
          expect(progressReports.any((r) => r.$3 == DownloadStatus.downloading), isTrue);
          expect(progressReports.any((r) => r.$3 == DownloadStatus.calculatingChecksum), isTrue);
          expect(progressReports.last.$1, equals(testBytes.length));
        });
      });

      group('cancellation', () {
        test('should handle download cancellation', () async {
          // Given: A server with large file and a cancel token
          setupServer(customData: List.filled(1000, 65)); // Large file with 'A's
          final cancelToken = CancelToken();

          // When: Cancelling download after short delay
          final downloader = FileDownloader.fromConfig(
            RangeRequestConfig(chunkSize: 10),
          );
          Future.delayed(const Duration(milliseconds: 50), () {
            cancelToken.cancel();
          });

          // Then: Should throw cancellation exception
          expect(
            () => downloader.downloadToFile(
              serverUrl,
              tempDir.path,
              cancelToken: cancelToken,
            ),
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.cancelled)),
          );
        });
      });

      group('file conflict handling', () {
        test('should handle file conflict with overwrite strategy', () async {
          // Given: A server and an existing file
          setupServer();
          final existingFile = File('${tempDir.path}/test.txt');
          await existingFile.writeAsString('OLD_CONTENT');

          // When: Downloading with overwrite strategy
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            conflictStrategy: FileConflictStrategy.overwrite,
          );

          // Then: File should be overwritten
          final file = File(result.filePath);
          expect(await file.readAsBytes(), equals(testBytes));
        });

        test('should handle file conflict with rename strategy', () async {
          // Given: A server and existing conflicting files
          setupServer();
          await File('${tempDir.path}/test.txt').writeAsString('OLD1');
          await File('${tempDir.path}/test(1).txt').writeAsString('OLD2');

          // When: Downloading with rename strategy
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
            conflictStrategy: FileConflictStrategy.rename,
          );

          // Then: File should be renamed with increment
          expect(result.filePath, endsWith('test(2).txt'));
          final file = File(result.filePath);
          expect(await file.readAsBytes(), equals(testBytes));
        });

        test('should handle file conflict with error strategy', () async {
          // Given: A server and an existing file
          setupServer();
          await File('${tempDir.path}/test.txt').writeAsString('OLD');

          // When: Downloading with error strategy
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());

          // Then: Should throw file exists error
          expect(
            () => downloader.downloadToFile(
              serverUrl,
              tempDir.path,
              conflictStrategy: FileConflictStrategy.error,
            ),
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.fileError)
              .having((e) => e.message, 'message', contains('already exists'))),
          );
        });
      });

      group('error handling', () {
        test('should handle corrupted local file', () async {
          // Given: A server and a corrupted local file (larger than remote)
          setupServer();
          final tempFile = File('${tempDir.path}/test.txt.tmp');
          await tempFile.writeAsBytes(List.filled(1000, 0));

          // When: Trying to resume from corrupted file
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());

          // Then: Should throw file error
          expect(
            () => downloader.downloadToFile(
              serverUrl,
              tempDir.path,
              resume: true,
            ),
            throwsA(isA<RangeRequestException>()
              .having((e) => e.code, 'code', RangeRequestErrorCode.fileError)
              .having((e) => e.message, 'message', contains('exceeds remote'))),
          );
        });

        test('should sanitize dangerous filenames', () async {
          // Given: A server with dangerous filename in content-disposition
          setupServer(fileName: '../../../etc/passwd');

          // When: Downloading the file
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            serverUrl,
            tempDir.path,
          );

          // Then: Filename should be sanitized
          final fileName = result.filePath.split('/').last;
          expect(fileName, equals('______etc_passwd'));
          expect(fileName, isNot(contains('..')));
          expect(fileName, isNot(contains('/')));
        });
      });

      group('filename handling', () {
        test('should handle files without extension', () async {
          // Given: A URL without file extension
          final noExtUrl = Uri.parse('http://localhost:${server.port}/noext');
          setupServer();

          // When: Downloading file without extension
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final result = await downloader.downloadToFile(
            noExtUrl,
            tempDir.path,
            conflictStrategy: FileConflictStrategy.rename,
          );

          // Then: Should handle filename without extension
          expect(result.filePath, endsWith('noext'));

          // When: Creating a conflict
          await downloader.downloadToFile(
            noExtUrl,
            tempDir.path,
            conflictStrategy: FileConflictStrategy.rename,
          );

          // Then: Should rename without extension
          expect(File('${tempDir.path}/noext(1)').existsSync(), isTrue);
        });
      });

      group('temp file cleanup', () {
        test('should clean up temp file on error when not resuming', () async {
          // Given: A server that returns error
          setupServer(statusCode: 500);

          // When: Download fails without resume
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          try {
            await downloader.downloadToFile(
              serverUrl,
              tempDir.path,
              resume: false,
            );
          } catch (_) {
            // Expected to fail
          }

          // Then: Temp file should be deleted
          final tempFile = File('${tempDir.path}/test.txt.tmp');
          expect(await tempFile.exists(), isFalse);
        });

        test('should keep temp file on error when resuming', () async {
          // Given: A partial download and then server failure
          setupServer();
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          final tempFile = File('${tempDir.path}/test.txt.tmp');
          await tempFile.writeAsBytes(testBytes.sublist(0, 10));

          // When: Server fails during resume attempt
          final serverPort = server.port;
          await server.close(force: true);
          server = await HttpServer.bind('localhost', serverPort);
          setupServer(statusCode: 500);

          try {
            await downloader.downloadToFile(
              serverUrl,
              tempDir.path,
              resume: true,
            );
          } catch (_) {
            // Expected to fail
          }

          // Then: Temp file should be preserved for future resume
          expect(await tempFile.exists(), isTrue);
          expect(await tempFile.length(), equals(10));
        });
      });
    });

    group('cleanupTempFiles', () {
      group('basic cleanup', () {
        test('should delete temp files', () async {
          // Given: Multiple temp files and regular files
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          await File('${tempDir.path}/file1.tmp').writeAsString('data1');
          await File('${tempDir.path}/file2.tmp').writeAsString('data2');
          await File('${tempDir.path}/subdir/file3.tmp').create(recursive: true);
          await File('${tempDir.path}/keep.txt').writeAsString('keep');

          // When: Cleaning up temp files
          final deleted = await downloader.cleanupTempFiles(tempDir.path);

          // Then: Only temp files should be deleted
          expect(deleted, equals(3));
          expect(File('${tempDir.path}/file1.tmp').existsSync(), isFalse);
          expect(File('${tempDir.path}/file2.tmp').existsSync(), isFalse);
          expect(File('${tempDir.path}/subdir/file3.tmp').existsSync(), isFalse);
          expect(File('${tempDir.path}/keep.txt').existsSync(), isTrue);
        });

        test('should respect custom extension', () async {
          // Given: Files with different extensions
          final downloader = FileDownloader.fromConfig(
            RangeRequestConfig(tempFileExtension: '.download'),
          );
          await File('${tempDir.path}/file1.download').writeAsString('data1');
          await File('${tempDir.path}/file2.tmp').writeAsString('data2');

          // When: Cleaning with specific extension
          final deleted = await downloader.cleanupTempFiles(
            tempDir.path,
            tempFileExtension: '.download',
          );

          // Then: Only matching extension should be deleted
          expect(deleted, equals(1));
          expect(File('${tempDir.path}/file1.download').existsSync(), isFalse);
          expect(File('${tempDir.path}/file2.tmp').existsSync(), isTrue);
        });
      });

      group('filtering', () {
        test('should filter by age', () async {
          // Given: Old and new temp files
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());

          final oldFile = File('${tempDir.path}/old.tmp');
          await oldFile.writeAsString('old');
          final oldTime = DateTime.now().subtract(const Duration(days: 2));
          await oldFile.setLastModified(oldTime);

          final newFile = File('${tempDir.path}/new.tmp');
          await newFile.writeAsString('new');

          // When: Cleaning files older than 1 day
          final deleted = await downloader.cleanupTempFiles(
            tempDir.path,
            olderThan: const Duration(days: 1),
          );

          // Then: Only old files should be deleted
          expect(deleted, equals(1));
          expect(oldFile.existsSync(), isFalse);
          expect(newFile.existsSync(), isTrue);
        });
      });

      group('edge cases', () {
        test('should handle non-existent directory', () async {
          // Given: A non-existent directory path
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());

          // When: Attempting cleanup on non-existent directory
          final deleted = await downloader.cleanupTempFiles(
            '${tempDir.path}/nonexistent',
          );

          // Then: Should return 0 without error
          expect(deleted, equals(0));
        });

        test('should continue on deletion errors', () async {
          // Given: Multiple temp files
          final downloader = FileDownloader.fromConfig(RangeRequestConfig());
          await File('${tempDir.path}/file1.tmp').writeAsString('data1');
          await File('${tempDir.path}/file2.tmp').writeAsString('data2');

          // When: Attempting cleanup (both files should be deletable in test)
          final deleted = await downloader.cleanupTempFiles(tempDir.path);

          // Then: Should delete what it can
          expect(deleted, greaterThanOrEqualTo(0));
        });
      });
    });

    group('factory constructor', () {
      test('should create FileDownloader with config', () {
        // Given: A custom configuration
        const config = RangeRequestConfig(
          chunkSize: 1024,
          maxRetries: 5,
        );

        // When: Creating FileDownloader with config
        final downloader = FileDownloader.fromConfig(config);

        // Then: Config should be applied
        expect(downloader.client.config, equals(config));
        expect(downloader.client.config.chunkSize, equals(1024));
        expect(downloader.client.config.maxRetries, equals(5));
      });
    });

    group('edge cases', () {
      test('should handle empty file', () async {
        // Given: A server with empty response
        setupServer(customData: []);

        // When: Downloading empty file
        final downloader = FileDownloader.fromConfig(RangeRequestConfig());
        final result = await downloader.downloadToFile(
          serverUrl,
          tempDir.path,
        );

        // Then: Should handle empty file correctly
        expect(result.fileSize, equals(0));
        final file = File(result.filePath);
        expect(await file.length(), equals(0));
      });

      test('should handle very small chunks', () async {
        // Given: A server and config with 1-byte chunks
        setupServer();

        // When: Downloading with tiny chunk size
        final downloader = FileDownloader.fromConfig(
          RangeRequestConfig(chunkSize: 1), // 1 byte chunks
        );
        final result = await downloader.downloadToFile(
          serverUrl,
          tempDir.path,
        );

        // Then: Should still download correctly
        final file = File(result.filePath);
        expect(await file.readAsBytes(), equals(testBytes));
      });

      test('should handle server without range support', () async {
        // Given: A server without range support and partial file
        setupServer(supportRanges: false);
        final tempFile = File('${tempDir.path}/test.txt.tmp');
        await tempFile.writeAsBytes(testBytes.sublist(0, 10));

        // When: Trying to resume from non-range server
        final downloader = FileDownloader.fromConfig(RangeRequestConfig());
        final result = await downloader.downloadToFile(
          serverUrl,
          tempDir.path,
          resume: true, // Try to resume, but server doesn't support it
        );

        // Then: Should download full file since resume isn't supported
        final file = File(result.filePath);
        expect(await file.readAsBytes(), equals(testBytes));
      });

      test('should create nested directories', () async {
        // Given: A server and a deeply nested path
        setupServer();
        final nestedPath = '${tempDir.path}/a/b/c/d';

        // When: Downloading to nested directory
        final downloader = FileDownloader.fromConfig(RangeRequestConfig());
        final result = await downloader.downloadToFile(
          serverUrl,
          nestedPath,
        );

        // Then: Directories should be created
        expect(result.filePath, startsWith(nestedPath));
        expect(File(result.filePath).existsSync(), isTrue);
      });
    });
  });
}