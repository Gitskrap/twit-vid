import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_update_service.dart';

/// Manual updater, also used after the automatic startup offer.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, this.initialRelease});
  final AppRelease? initialRelease;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final _service = AppUpdateService();
  InstalledAppVersion? _installed;
  AppRelease? _release;
  File? _verifiedApk;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _release = widget.initialRelease;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  Future<void> _check() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final installed = await _service.getInstalledVersion();
      final remote = widget.initialRelease ??
          await _service.getLatestRelease();
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _release = remote;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Vérification impossible : $error');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  bool get _newer {
    if (_installed == null || _release == null) return false;
    return compareAppVersions(_release!.version, _installed!.name) > 0;
  }

  Future<void> _beginInstallation() async {
    final release = _release;
    if (release == null || !_newer || _downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
      _status = null;
      _progress = _verifiedApk == null ? 0 : 1;
    });
    try {
      final apk = _verifiedApk ??
          await _service.downloadVerifiedApk(
            release,
            onProgress: (fraction) {
              if (mounted) setState(() => _progress = fraction);
            },
          );
      _verifiedApk = apk;
      if (!mounted) return;

      if (!await _service.canInstallPackages()) {
        if (!mounted) return;
        final granted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Autoriser les mises à jour'),
            content: const Text(
              'Pour installer le nouvel APK, Android doit autoriser '
              'Twitter vidéo à installer des applications. '
              'Active cette autorisation, puis reviens ici et appuie '
              'à nouveau sur Installer. Tes données sont conservées.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Plus tard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ouvrir les réglages Android'),
              ),
            ],
          ),
        );
        if (granted == true) {
          await _service.openInstallPermissionSettings();
        }
        return;
      }

      await _service.installVerifiedApk(apk);
      if (mounted) {
        setState(() {
          _status = 'APK vérifié. Confirme l’installation dans Android. '
              'La mise à jour conserve les données de Twitter vidéo.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Mise à jour interrompue : $error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    final installed = _installed;
    return Scaffold(
      appBar: AppBar(title: const Text('Mises à jour')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.system_update_alt,
              size: 58, color: Color(0xFF70F0CE)),
          const SizedBox(height: 16),
          const Text(
            'Twit Vid · Twitter vidéo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.smartphone_outlined),
            title: const Text('Version installée'),
            subtitle: Text(installed == null
                ? 'Lecture…'
                : '${installed.name} (build ${installed.code})'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Dernière version GitHub'),
            subtitle: Text(release == null
                ? 'Vérification…'
                : release.version),
            trailing: _checking
                ? const SizedBox.square(
                    dimension: 22, child: CircularProgressIndicator())
                : null,
          ),
          if (installed != null && release != null)
            ListTile(
              leading: Icon(
                _newer ? Icons.new_releases_outlined
                    : Icons.check_circle_outline,
                color: _newer ? const Color(0xFF70F0CE) : null,
              ),
              title: Text(_newer
                  ? 'Nouvelle version disponible'
                  : 'L’application est à jour'),
              subtitle: _newer
                  ? const Text('Téléchargement depuis GitHub Releases, '
                      'vérification SHA-256, puis installation Android.')
                  : null,
            ),
          if (release != null && _newer && release.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Nouveautés',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              release.notes.length > 1400
                  ? '${release.notes.substring(0, 1400)}…'
                  : release.notes,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress <= 0 ? null : _progress),
            const SizedBox(height: 8),
            Text('Téléchargement : ${(_progress * 100).toStringAsFixed(0)} %',
                textAlign: TextAlign.center),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!),
          ],
          const SizedBox(height: 20),
          if (_newer)
            FilledButton.icon(
              onPressed: _downloading || _checking
                  ? null : _beginInstallation,
              icon: const Icon(Icons.download),
              label: Text(_downloading
                  ? 'Téléchargement en cours…'
                  : _verifiedApk == null
                      ? 'Télécharger et installer'
                      : 'Installer la mise à jour'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _downloading || _checking
                ? null : () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UpdateScreen(),
                      ),
                    );
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Vérifier maintenant'),
          ),
          const SizedBox(height: 16),
          const Text(
            'La recherche des versions publiques ne nécessite pas de '
            'connexion X ni de jeton GitHub. Android demande ton accord '
            'avant l’installation. Les secrets de signature restent sur GitHub.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
