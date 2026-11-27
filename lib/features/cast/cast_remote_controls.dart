import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import '../diagnostics/privacy_diagnostics.dart';
import '../player/widgets/video_seek_bar.dart';

class CastRemoteControls extends StatefulWidget {
  const CastRemoteControls({super.key, this.fallbackDurationMs});
  final int? fallbackDurationMs;

  @override
  State<CastRemoteControls> createState() => _CastRemoteControlsState();
}

class _CastRemoteControlsState extends State<CastRemoteControls> {
  final _client = GoogleCastRemoteMediaClient.instance;
  Timer? _timer;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _command(Future<void> Function() action, DiagnosticEvent event) async {
    try {
      await action();
      PrivacyDiagnostics.instance.record(event);
    } catch (_) {
      PrivacyDiagnostics.instance.record(DiagnosticEvent.castControlFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _client.mediaStatus;
    final duration = status?.mediaInformation?.duration ??
        Duration(milliseconds: widget.fallbackDurationMs ?? 0);
    final max = duration.inMilliseconds.toDouble();
    final pos = (_drag ?? _client.playerPosition.inMilliseconds.toDouble())
        .clamp(0.0, max > 0 ? max : 0.0).toDouble();
    final playing = status?.playerState == CastMediaPlayerState.playing;
    return Material(
      color: const Color(0xE6191B20),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Lecture sur Chromecast', style: TextStyle(color: Color(0xFF70F0CE))),
          Row(children: [
            IconButton(
              tooltip: playing ? 'Pause TV' : 'Lecture TV',
              onPressed: status == null ? null : () => _command(
                () async { if (playing) { await _client.pause(); } else { await _client.play(); } },
                DiagnosticEvent.castPlayPauseCommand),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
            Text(formatVideoTime(Duration(milliseconds: pos.round()))),
            Expanded(child: Slider(
              min: 0, max: max > 0 ? max : 1, value: pos,
              onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: max <= 0 ? null : (v) async {
                await _command(() => _client.seek(GoogleCastMediaSeekOption(
                  position: Duration(milliseconds: v.round()),
                )), DiagnosticEvent.castSeekCommand);
                if (mounted) setState(() => _drag = null);
              },
            )),
            Text(formatVideoTime(duration)),
          ]),
        ]),
      ),
    );
  }
}
