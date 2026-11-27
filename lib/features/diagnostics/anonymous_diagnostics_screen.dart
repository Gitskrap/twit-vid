import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'privacy_diagnostics.dart';

const _shareChannel = MethodChannel('fr.twittervideo.client/diagnostics');

class AnonymousDiagnosticsScreen extends StatefulWidget {
  const AnonymousDiagnosticsScreen({super.key});

  @override
  State<AnonymousDiagnosticsScreen> createState() =>
      _AnonymousDiagnosticsScreenState();
}

class _AnonymousDiagnosticsScreenState extends State<AnonymousDiagnosticsScreen> {
  final _diagnostics = PrivacyDiagnostics.instance;
  bool _sharing = false;
  String? _preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _diagnostics.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _diagnostics.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _erase() async {
    await _diagnostics.erase();
    if (!mounted) return;
    setState(() => _preview = null);
    try {
      await _shareChannel.invokeMethod<void>('deleteReport');
    } catch (_) {}
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      final location = await _diagnostics.downloadAndClear((report) async {
        final saved = await _shareChannel.invokeMethod<String>('downloadReport', {'json': report});
        if (saved == null || saved.isEmpty) throw StateError('Download not confirmed');
        return saved;
      });
      if (mounted) {
        setState(() => _preview = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Enregistré : $location. Journal exporté effacé.'),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Téléchargement impossible. Journal conservé.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostic anonyme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const Icon(Icons.fiber_manual_record, color: Color(0xFF70F0CE), size: 48),
          const SizedBox(height: 16),
          const Text('Diagnostic automatique actif',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            'Les événements techniques sont enregistrés automatiquement. '
            'Chaque export contient les cinq dernières minutes, '
            'puis efface les événements sauvegardés. Les nouveaux événements '
            'continuent d’être enregistrés automatiquement.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text('Événements récents : ${_diagnostics.eventCount}',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: const Icon(Icons.download),
            label: Text(_sharing ? 'Téléchargement…' :
                'Télécharger les 5 dernières minutes'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _sharing ? null : () => setState(() => _preview = _diagnostics.snapshot()),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Afficher le rapport actuel'),
          ),
          if (_preview != null)
            ExpansionTile(
              initiallyExpanded: true,
              title: const Text('Aperçu du rapport'),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: SingleChildScrollView(
                    child: SelectableText(_preview!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'CONFIDENTIALITÉ\n'
              'Aucun identifiant de vidéo, compte, abonnement, hashtag, '
              'mot-clé, URL, contenu, erreur brute, cookie ou donnée de connexion.\n\n'
              'Le rapport ne contient que des événements techniques, '
              'des délais relatifs et des quantités regroupées. '
              'Aucun envoi automatique. Les événements récents sont conservés '
              'localement, y compris après un redémarrage.',
            ),
          )),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _sharing ? null : _erase,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Effacer le journal'),
          ),
          const Text('L’enregistrement reprend automatiquement après effacement.',
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
