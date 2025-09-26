import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:range_request/range_request.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Range Request Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DownloadPage(),
    );
  }
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  // Using a GGUF model file from HuggingFace (about 270MB)
  final String _sampleUrl = 'https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-UD-IQ2_M.gguf';

  double _progress = 0.0;
  String _status = 'Ready to download';
  bool _isDownloading = false;
  CancelToken? _cancelToken;
  String? _downloadedFilePath;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _status = 'Starting download...';
      _cancelToken = CancelToken();
    });

    try {
      final client = RangeRequestClient(
        config: RangeRequestConfig(
          chunkSize: 1024 * 1024 * 2,
          maxConcurrentRequests: 4,
          maxRetries: 3,
        ),
      );

      final downloader = FileDownloader(client);

      final appDir = await getApplicationDocumentsDirectory();

      final result = await downloader.downloadToFile(
        Uri.parse(_sampleUrl),
        appDir.path,
        outputFileName: 'gemma-3-270m-it.gguf',
        onProgress: (bytes, total, status) {
          if (total > 0) {
            final percentage = (bytes / total * 100);
            final downloadedMB = bytes / (1024 * 1024);
            final totalMB = total / (1024 * 1024);
            setState(() {
              _progress = percentage;
              _status = status == DownloadStatus.downloading
                  ? 'Downloading: ${downloadedMB.toStringAsFixed(2)} MB / ${totalMB.toStringAsFixed(2)} MB'
                  : 'Calculating checksum...';
            });
          }
        },
        cancelToken: _cancelToken,
        conflictStrategy: FileConflictStrategy.overwrite,
        checksumType: ChecksumType.sha256,
      );

      setState(() {
        _status = 'Download complete! File saved at: ${result.filePath}';
        if (result.checksum != null) {
          _status += '\nSHA256: ${result.checksum}';
        }
        _downloadedFilePath = result.filePath;
        _isDownloading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isDownloading = false;
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    setState(() {
      _status = 'Download cancelled';
      _isDownloading = false;
    });
  }

  Future<void> _deleteFile() async {
    if (_downloadedFilePath != null) {
      try {
        final file = File(_downloadedFilePath!);
        if (await file.exists()) {
          await file.delete();
          setState(() {
            _status = 'File deleted';
            _downloadedFilePath = null;
            _progress = 0.0;
          });
        }
      } catch (e) {
        setState(() {
          _status = 'Error deleting file: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Range Request Download Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sample File Download',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'URL: $_sampleUrl',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _progress / 100,
                      minHeight: 10,
                    ),
                    const SizedBox(height: 8),
                    Text('${_progress.toStringAsFixed(1)}%'),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _startDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
                ElevatedButton.icon(
                  onPressed: _isDownloading ? _cancelDownload : null,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _downloadedFilePath != null && !_isDownloading
                      ? _deleteFile
                      : null,
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Features:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• Parallel chunk downloads (4 concurrent)'),
                    Text('• 2MB chunk size'),
                    Text('• Automatic retry on failure'),
                    Text('• Progress tracking'),
                    Text('• Cancellation support'),
                    Text('• File conflict handling'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}