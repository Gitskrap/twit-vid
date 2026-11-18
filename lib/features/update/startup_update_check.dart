import 'dart:async';

import 'package:flutter/material.dart';

import 'app_update_service.dart';
import 'update_screen.dart';

/// Only checks once per app process, after successful biometric unlock.
/// Network errors are silent at startup; manual Settings check shows errors.
class StartupUpdateCheck extends StatefulWidget {
  const StartupUpdateCheck({super.key, required this.child});
  final Widget child;

  @override
  State<StartupUpdateCheck> createState() => _StartupUpdateCheckState();
}

class _StartupUpdateCheckState extends State<StartupUpdateCheck> {
  static bool _didCheckThisProcess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_didCheckThisProcess && mounted) {
        _didCheckThisProcess = true;
        unawaited(_checkNewRelease());
      }
    });
  }

  Future<void> _checkNewRelease() async {
    try {
      final service = AppUpdateService();
      final installed = await service.getInstalledVersion();
      final latest = await service.getLatestRelease();
      if (!mounted ||
          compareAppVersions(latest.version, installed.name) <= 0) {
        return;
      }
      final openUpdater = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mise à jour disponible'),
          content: Text(
            'Twit Vid ${latest.version} est disponible sur GitHub.\n\n'
            'Version installée : ${installed.name}.\n\n'
            'Veux-tu télécharger et installer la nouvelle version ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Mettre à jour'),
            ),
          ],
        ),
      );
      if (!mounted || openUpdater != true) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UpdateScreen(initialRelease: latest),
        ),
      );
    } catch (error) {
      // The app must always start even if GitHub is offline or rate limited.
      debugPrint('Twit Vid update check skipped: $error');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
