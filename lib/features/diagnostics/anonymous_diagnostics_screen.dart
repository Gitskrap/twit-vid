import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'privacy_diagnostics.dart';

const _shareChannel = MethodChannel('fr.twittervideo.client/diagnostics');

/// Recording continues across the app after this screen is closed.
class AnonymousDiagnosticsScreen extends StatefulWidget {
  const AnonymousDiagnosticsScreen({super.key});

  @override
  State<AnonymousDiagnosticsScreen> createState() =>
      _AnonymousDiagnosticsScreenState();
}

class _AnonymousDiagnosticsScreenState
    extends State<AnonymousDiagnosticsScreen> {
  final PrivacyDiagnostics _diagnostics = PrivacyDiagnostics.instance;
  bool _sharing = false;
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

  void _start() {
    _diagnostics.start();
    // Old exported report must not be kept once a fresh session begins.
    _shareChannel.invokeMethod<void>('deleteReport').catchError(
        (Object _) {});
  }

  void _erase() {
    _diagnostics.erase();
    _shareChannel.invokeMethod<void>('deleteReport').catchError(
        (Object _) {});
  }

  Future<void> _share() async {
    final report = _diagnostics.finishedReport;
    if (report == null || _sharing) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      await _shareChannel.invokeMethod<void>(
          'shareReport', {'json': report});
    } catch (error) {
      if (mounted) setState(() => _error = 'Partage impossible : $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _diagnostics.isRecording;
    final report = _diagnostics.finishedReport;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostic anonyme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Icon(
            recording ? Icons.fiber_manual_record : Icons.privacy_tip_outlined,
            color: recording ? Colors.redAccent : const Color(0xFF70F0CE),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            recording
                ? 'Enregistrement en cours'
                : report == null
                    ? 'Diagnostic désactivé'
                    : 'Enregistrement terminé',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'L’enregistrement est désactivé par défaut. '
            'Pendant quelques minutes, utilise normalement les vidéos, '
            'la recherche, les hashtags et le Cast. Reviens ici pour '
            'arrêter puis examiner le rapport avant de le partager.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'CONFIDENTIALITÉ\n'
                '✓ Aucun identifiant de vidéo ou de publication\n'
                '✓ Aucun nom de compte ni abonnement\n'
                '✓ Aucun hashtag ni mot-clé recherché\n'
                '✓ Aucun lien, contenu de vidéo ou texte de publication\n'
                '✓ Aucune erreur brute, cookie ou donnée de connexion\n'
                '✓ Aucun horodatage absolu ni identifiant de téléphone\n\n'
                'Uniquement des types d’actions prédéfinis, leurs délais '
                'relatifs et des quantités arrondies. '
                'Aucun envoi automatique.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (recording) ...[
            Text(
              'Événements techniques enregistrés : ' +
                  _diagnostics.eventCount.toString(),
              textAlign: TextAlign.center,
            ),
            if (_diagnostics.droppedEvents > 0)
              const Text('Limite du rapport atteinte. '
                  'Les événements supplémentaires ne sont pas enregistrés.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _diagnostics.stop(),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Arrêter l’enregistrement'),
            ),
          ] else if (report == null) ...[
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Démarrer le diagnostic'),
            ),
          ] else ...[
            const Text(
              'Rapport prêt : consulte-le avant de choisir avec '
              'quelle application le partager.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: Text(_sharing ? 'Ouverture du partage…'
                  : 'Partager le rapport anonymisé'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Recommencer un diagnostic'),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Afficher le rapport complet'),
              subtitle: const Text('Vérifie exactement ce qui sera envoyé'),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      report,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _erase,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Effacer les données du diagnostic'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Le diagnostic reste en mémoire uniquement durant cette '
            'session. Le fichier n’est créé dans le cache privé '
            'qu’au moment du partage. Le redémarrage efface '
            'l’enregistrement non exporté.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
