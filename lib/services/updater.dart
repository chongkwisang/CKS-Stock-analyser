import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// In-app updater backed by GitHub Releases. Every CI build publishes a
/// release tagged `v<version>` with the APK attached; the app compares that
/// with its own version and, if newer, downloads and launches the installer.
class Updater {
  static const owner = 'chongkwisang';
  static const repo = 'CKS-Stock-analyser';
  static const latestApi = 'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const releasesPage = 'https://github.com/$owner/$repo/releases/latest';

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Returns release info when a newer version exists, otherwise null.
  static Future<UpdateInfo?> check() async {
    final res = await http
        .get(Uri.parse(latestApi), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Update server returned ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] ?? '').toString();
    final assets = (json['assets'] as List? ?? const []).cast<Map>();
    final apk = assets.firstWhere((a) => a['name'].toString().toLowerCase().endsWith('.apk'), orElse: () => const {});
    if (apk.isEmpty) return null;
    final remote = tag.replaceFirst(RegExp(r'^v'), '');
    final local = await currentVersion();
    if (compareVersions(remote, local) <= 0) return null;
    return UpdateInfo(
      version: remote,
      notes: (json['body'] ?? '').toString(),
      apkUrl: apk['browser_download_url'].toString(),
      sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
    );
  }

  static int compareVersions(String a, String b) {
    List<int> parse(String s) => s.split(RegExp(r'[.+\-]')).map((e) => int.tryParse(e) ?? 0).toList();
    final pa = parse(a), pb = parse(b);
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Full UI flow: check, prompt, download with progress, install.
  static Future<void> checkAndPrompt(BuildContext context, {bool silent = false}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    UpdateInfo? info;
    try {
      info = await check();
    } catch (e) {
      if (!silent) messenger?.showSnackBar(SnackBar(content: Text('Update check failed: $e')));
      return;
    }
    if (info == null) {
      if (!silent) messenger?.showSnackBar(const SnackBar(content: Text('You are on the latest version')));
      return;
    }
    if (!context.mounted) return;
    final current = await currentVersion();
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: const Text('Update available'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Version ${info!.version} is available (you have $current).'),
              if (info.sizeBytes > 0) Text('Size: ${(info.sizeBytes / 1048576).toStringAsFixed(1)} MB'),
              if (info.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(info.notes.trim(), style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update now')),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(url: info!.apkUrl),
    );
  }
}

class UpdateInfo {
  final String version, notes, apkUrl;
  final int sizeBytes;
  UpdateInfo({required this.version, required this.notes, required this.apkUrl, required this.sizeBytes});
}

class _DownloadDialog extends StatefulWidget {
  final String url;
  const _DownloadDialog({required this.url});
  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double? _progress;
  String _status = 'Starting download…';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    try {
      OtaUpdate()
          .execute(widget.url, destinationFilename: 'cks-stock-analyser-update.apk')
          .listen(
            (event) {
              if (!mounted) return;
              setState(() {
                switch (event.status) {
                  case OtaStatus.DOWNLOADING:
                    _progress = (double.tryParse(event.value ?? '') ?? 0) / 100;
                    _status = 'Downloading… ${event.value ?? 0}%';
                  case OtaStatus.INSTALLING:
                    _progress = 1;
                    _status = 'Opening installer…';
                    _done = true;
                  case OtaStatus.ALREADY_RUNNING_ERROR:
                    _status = 'A download is already running';
                    _done = true;
                  case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                    _status = 'Please allow "Install unknown apps" for this app and try again';
                    _done = true;
                  default:
                    _status = 'Update failed (${event.status.name}) ${event.value ?? ''}';
                    _done = true;
                }
              });
            },
            onError: (e) {
              if (mounted) {
                setState(() {
                  _status = 'Update failed: $e';
                  _done = true;
                });
              }
            },
          );
    } catch (e) {
      _status = 'Update failed: $e';
      _done = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Updating'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 16),
          Text(_status),
        ],
      ),
      actions: [if (_done) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
