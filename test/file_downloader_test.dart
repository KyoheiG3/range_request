import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:range_request/src/cancel_token.dart';
import 'package:range_request/src/exceptions.dart';
import 'package:range_request/src/file_downloader.dart';
import 'package:range_request/src/models.dart';
import 'package:range_request/src/range_request_client.dart';
import 'package:test/test.dart';

import 'mock_http.dart';

void main() {
  group('FileDownloader', () {
    group('constructors', () {
      test('should create with default client', () {
        // Given/When: Creating downloader without client
        final downloader = FileDownloader();

        // Then: Should have a client
        expect(downloader.client, isNotNull);
      });

      test('should create with fromConfig factory', () {
        // Given: Configuration with custom settings
        const config = RangeRequestConfig(
          chunkSize: 1024,
          maxConcurrentRequests: 5,
        );

        // When: Creating downloader with factory
        final downloader = FileDownloader.fromConfig(config);

        // Then: Should have client with provided config
        expect(downloader.client, isNotNull);
        expect(downloader.client.config.chunkSize, equals(1024));
        expect(downloader.client.config.maxConcurrentRequests, equals(5));
      });
    });

    late MockHttp mockHttp;
    late Uri testUrl;
    late Directory tempDir;
    const testData =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz';
    final testBytes = utf8.encode(testData);
    final testSha256 = sha256.convert(testBytes).toString();
    final testMd5 = md5.convert(testBytes).toString();

    setUp(() async {
      mockHttp = MockHttp();
      testUrl = Uri.parse('http://test.example.com/file');
      tempDir = await Directory.systemTemp.createTemp('range_request_test_');
    });

    tearDown(() async {
      mockHttp.reset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('downloadToFile', () {
      group('basic download operations', () {
        test('should download file successfully with range support', () async {
          // Given: Server with range support
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(testUrl.toString(), testBytes);

          // When: Downloading file
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);
          final targetPath = '${tempDir.path}/downloaded.txt';

          final result = await downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: 'downloaded.txt',
          );

          // Then: File should be downloaded successfully
          expect(result.filePath, equals(targetPath));
          expect(result.fileSize, equals(testBytes.length));

          final file = File(targetPath);
          expect(await file.exists(), isTrue);
          expect(await file.readAsBytes(), equals(testBytes));
        });

        test(
          'should download file successfully without range support',
          () async {
            // Given: Server without range support
            mockHttp.registerHeadResponse(
              testUrl.toString(),
              contentLength: testBytes.length,
              acceptRanges: false,
            );
            mockHttp.registerResponse(
              'GET:$testUrl:FULL',
              statusCode: 200,
              body: testBytes,
            );

            // When: Downloading file
            final client = RangeRequestClient(http: mockHttp);
            final downloader = FileDownloader(client);
            final targetPath = '${tempDir.path}/downloaded.txt';

            final result = await downloader.downloadToFile(
              testUrl,
              tempDir.path,
              outputFileName: 'downloaded.txt',
            );

            // Then: File should be downloaded successfully
            expect(result.filePath, equals(targetPath));
            expect(result.fileSize, equals(testBytes.length));

            final file = File(targetPath);
            expect(await file.exists(), isTrue);
            expect(await file.readAsBytes(), equals(testBytes));
          },
        );

        test('should create target directory if it does not exist', () async {
          // Given: Non-existent target directory
          final targetDir = '${tempDir.path}/new/nested/dir';
          final targetFileName = 'file.txt';

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );
          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 200,
            body: testBytes,
          );

          // When: Downloading to non-existent directory
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);
          final result = await downloader.downloadToFile(
            testUrl,
            targetDir,
            outputFileName: targetFileName,
          );

          // Then: Directory should be created
          expect(await Directory(targetDir).exists(), isTrue);
          expect(result.filePath, equals('$targetDir/$targetFileName'));

          final file = File(result.filePath);
          expect(await file.exists(), isTrue);
        });
      });

      group('resume functionality', () {
        test('should resume partial download from existing file', () async {
          // Given: Partially downloaded file
          final targetPath = '${tempDir.path}/partial.txt';
          final partialData = testBytes.sublist(0, 20);
          // FileDownloader uses .tmp extension for temp files
          final tempFilePath = '$targetPath.tmp';
          await File(tempFilePath).writeAsBytes(partialData);

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(testUrl.toString(), testBytes);

          // When: Resuming download
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);
          final result = await downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: targetPath.split('/').last,
            resume: true,
          );

          // Then: Should have complete file after resume
          expect(result.fileSize, equals(testBytes.length));

          final file = File(targetPath);
          expect(await file.readAsBytes(), equals(testBytes));
        });

        test('should handle completed file when resuming', () async {
          // Given: Fully downloaded file
          final targetPath = '${tempDir.path}/complete.txt';
          final tempFilePath = '$targetPath.tmp';
          await File(tempFilePath).writeAsBytes(testBytes);

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );

          // When: Attempting to resume completed download
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);
          final result = await downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: targetPath.split('/').last,
            resume: true,
          );

          // Then: Should recognize file is complete
          expect(result.fileSize, equals(testBytes.length));

          final file = File(targetPath);
          expect(await file.readAsBytes(), equals(testBytes));
        });
      });

      group('checksum calculation', () {
        test('should calculate SHA256 checksum', () async {
          // Given: Request for SHA256 checksum
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );
          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 200,
            body: testBytes,
          );

          // When: Downloading with checksum calculation
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);

          final result = await downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: 'file.txt',
            checksumType: ChecksumType.sha256,
          );

          // Then: Should calculate correct checksum
          expect(result.checksum, equals(testSha256));
          expect(result.checksumType, equals(ChecksumType.sha256));
        });

        test('should calculate MD5 checksum', () async {
          // Given: Request for MD5 checksum
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );
          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 200,
            body: testBytes,
          );

          // When: Downloading with MD5 checksum
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);

          final result = await downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: 'file.txt',
            checksumType: ChecksumType.md5,
          );

          // Then: Should calculate correct MD5
          expect(result.checksum, equals(testMd5));
          expect(result.checksumType, equals(ChecksumType.md5));
        });
      });

      group('progress tracking', () {
        test('should report download progress', () async {
          // Given: Progress callback
          final progressUpdates = <(int, int)>[];

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(testUrl.toString(), testBytes);

          // When: Downloading with progress tracking
          const config = RangeRequestConfig(
            chunkSize: 10,
            progressInterval: Duration(milliseconds: 10),
          );
          final client = RangeRequestClient(config: config, http: mockHttp);
          final downloader = FileDownloader(client);

          await downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: 'file.txt',
            onProgress: (bytes, total, status) =>
                progressUpdates.add((bytes, total)),
          );

          // Then: Should report progress
          expect(progressUpdates.isNotEmpty, isTrue);
          final lastUpdate = progressUpdates.last;
          expect(lastUpdate.$1, equals(testBytes.length));
          expect(lastUpdate.$2, equals(testBytes.length));
        });
      });

      group('cancellation', () {
        test('should handle cancellation during download', () async {
          // Given: Cancel token
          final cancelToken = CancelToken();

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );
          mockHttp.registerRangeResponse(
            testUrl.toString(),
            testBytes,
            delay: const Duration(milliseconds: 50),
          );

          // When: Starting download and cancelling
          const config = RangeRequestConfig(chunkSize: 5);
          final client = RangeRequestClient(config: config, http: mockHttp);
          final downloader = FileDownloader(client);

          final downloadFuture = downloader.downloadToFile(
            testUrl,
            tempDir.path,
            outputFileName: 'file.txt',
            cancelToken: cancelToken,
          );

          // Cancel after a short delay
          await Future.delayed(const Duration(milliseconds: 10));
          cancelToken.cancel();

          // Then: Should throw cancelled exception
          await expectLater(
            downloadFuture,
            throwsA(
              isA<RangeRequestException>().having(
                (e) => e.code,
                'code',
                RangeRequestErrorCode.cancelled,
              ),
            ),
          );
        });
      });

      group('file conflict strategies', () {
        test(
          'should rename file when FileConflictStrategy.rename is used',
          () async {
            // Given: Existing file with same name
            final existingFile = File('${tempDir.path}/conflict.txt');
            await existingFile.writeAsString('existing content');

            mockHttp.registerHeadResponse(
              testUrl.toString(),
              contentLength: testBytes.length,
              acceptRanges: false,
            );
            mockHttp.registerResponse(
              'GET:$testUrl:FULL',
              statusCode: 200,
              body: testBytes,
            );

            // When: Downloading with rename strategy
            final client = RangeRequestClient(http: mockHttp);
            final downloader = FileDownloader(client);
            final result = await downloader.downloadToFile(
              testUrl,
              tempDir.path,
              outputFileName: 'conflict.txt',
              conflictStrategy: FileConflictStrategy.rename,
            );

            // Then: Should create new file with (1) suffix
            expect(result.filePath, equals('${tempDir.path}/conflict(1).txt'));
            expect(await File(result.filePath).exists(), isTrue);
            expect(
              await File(result.filePath).readAsBytes(),
              equals(testBytes),
            );
            // Original file should still exist
            expect(
              await existingFile.readAsString(),
              equals('existing content'),
            );
          },
        );

        test(
          'should throw error when FileConflictStrategy.error is used',
          () async {
            // Given: Existing file with same name
            final existingFile = File('${tempDir.path}/error.txt');
            await existingFile.writeAsString('existing content');

            mockHttp.registerHeadResponse(
              testUrl.toString(),
              contentLength: testBytes.length,
              acceptRanges: false,
            );
            mockHttp.registerResponse(
              'GET:$testUrl:FULL',
              statusCode: 200,
              body: testBytes,
            );

            // When/Then: Should throw file error
            final client = RangeRequestClient(http: mockHttp);
            final downloader = FileDownloader(client);

            await expectLater(
              downloader.downloadToFile(
                testUrl,
                tempDir.path,
                outputFileName: 'error.txt',
                conflictStrategy: FileConflictStrategy.error,
              ),
              throwsA(
                isA<RangeRequestException>()
                    .having(
                      (e) => e.code,
                      'code',
                      RangeRequestErrorCode.fileError,
                    )
                    .having(
                      (e) => e.message,
                      'message',
                      contains('File already exists'),
                    ),
              ),
            );
          },
        );
      });

      group('error handling', () {
        test('should throw on server error', () async {
          // Given: Server returning error
          mockHttp.registerResponse(
            'HEAD:$testUrl',
            statusCode: 404,
            body: 'Not Found',
          );

          // When/Then: Should throw exception
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);

          await expectLater(
            downloader.downloadToFile(
              testUrl,
              tempDir.path,
              outputFileName: 'file.txt',
            ),
            throwsA(
              isA<RangeRequestException>().having(
                (e) => e.code,
                'code',
                RangeRequestErrorCode.serverError,
              ),
            ),
          );
        });

        test('should throw when local file exceeds remote size', () async {
          // Given: Corrupted local file (too large)
          final targetPath = '${tempDir.path}/corrupted.txt';
          final tempFilePath = '$targetPath.tmp';
          final corruptedData = List<int>.filled(
            testBytes.length + 100,
            65,
          ); // File larger than remote
          await File(tempFilePath).writeAsBytes(corruptedData);

          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: true,
          );

          // When/Then: Should throw file error
          final client = RangeRequestClient(http: mockHttp);
          final downloader = FileDownloader(client);

          await expectLater(
            downloader.downloadToFile(
              testUrl,
              tempDir.path,
              outputFileName: 'corrupted.txt',
              resume: true,
            ),
            throwsA(
              isA<RangeRequestException>()
                  .having(
                    (e) => e.code,
                    'code',
                    RangeRequestErrorCode.fileError,
                  )
                  .having(
                    (e) => e.message,
                    'message',
                    contains('exceeds remote file size'),
                  ),
            ),
          );
        });

        test('should delete temp file on error when not resuming', () async {
          // Given: Server that fails after headers
          mockHttp.registerHeadResponse(
            testUrl.toString(),
            contentLength: testBytes.length,
            acceptRanges: false,
          );
          mockHttp.registerResponse(
            'GET:$testUrl:FULL',
            statusCode: 500,
            body: 'Server Error',
          );

          // When: Download fails without resume (with no retries for faster test)
          const config = RangeRequestConfig(
            maxRetries: 0, // Disable retries for faster test
          );
          final client = RangeRequestClient(config: config, http: mockHttp);
          final downloader = FileDownloader(client);
          final targetPath = '${tempDir.path}/failed.txt';
          final tempFilePath = '$targetPath.tmp';

          try {
            await downloader.downloadToFile(
              testUrl,
              tempDir.path,
              outputFileName: 'failed.txt',
              resume: false,
            );
          } catch (_) {
            // Expected error
          }

          // Then: Temp file should be deleted
          expect(await File(tempFilePath).exists(), isFalse);
        });
      });
    });

    group('cleanupTempFiles', () {
      test('should remove temporary files with specified extension', () async {
        // Given: Temporary files with various extensions
        const tempExt = '.download';
        await File('${tempDir.path}/file1$tempExt').create();
        await File('${tempDir.path}/file2$tempExt').create();
        await File('${tempDir.path}/keep.txt').create();

        final client = RangeRequestClient(http: mockHttp);
        final downloader = FileDownloader(client);

        // When: Cleaning up temp files
        final deletedCount = await downloader.cleanupTempFiles(
          tempDir.path,
          tempFileExtension: tempExt,
        );

        // Then: Should remove only temp files
        expect(deletedCount, equals(2));
        expect(await File('${tempDir.path}/file1$tempExt').exists(), isFalse);
        expect(await File('${tempDir.path}/file2$tempExt').exists(), isFalse);
        expect(await File('${tempDir.path}/keep.txt').exists(), isTrue);
      });

      test('should filter by age if specified', () async {
        // Given: Files with different ages
        const tempExt = '.download';
        final oldFile = File('${tempDir.path}/old$tempExt');
        final newFile = File('${tempDir.path}/new$tempExt');

        await oldFile.create();
        await newFile.create();

        // Make old file older
        final oldTime = DateTime.now().subtract(const Duration(hours: 2));
        await oldFile.setLastModified(oldTime);

        final client = RangeRequestClient(http: mockHttp);
        final downloader = FileDownloader(client);

        // When: Cleaning files older than 1 hour
        final deletedCount = await downloader.cleanupTempFiles(
          tempDir.path,
          tempFileExtension: tempExt,
          olderThan: const Duration(hours: 1),
        );

        // Then: Should remove only old file
        expect(deletedCount, equals(1));
        expect(await oldFile.exists(), isFalse);
        expect(await newFile.exists(), isTrue);
      });

      test('should handle non-existent directory', () async {
        // Given: Non-existent directory
        final nonExistentDir = '${tempDir.path}/nonexistent';

        final client = RangeRequestClient(http: mockHttp);
        final downloader = FileDownloader(client);

        // When: Cleaning non-existent directory
        final deletedCount = await downloader.cleanupTempFiles(nonExistentDir);

        // Then: Should return 0
        expect(deletedCount, equals(0));
      });
    });
  });
}
