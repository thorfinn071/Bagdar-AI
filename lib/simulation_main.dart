import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'core/simulation_build.dart';
import 'main.dart' show BagdarApp;
import 'models/app_mode.dart';
import 'services/settings_service.dart';
import 'simulation/simulation_bundle.dart';
import 'simulation/simulation_session.dart';
import 'simulation/simulation_episode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  requireSimulationBuild();
  await Settings.instance.init();
  const path = String.fromEnvironment('BAGDAR_SIMULATION_MANIFEST');
  const selected = String.fromEnvironment('BAGDAR_SIMULATION_SEQUENCE');
  if (path.isEmpty) throw StateError('Set BAGDAR_SIMULATION_MANIFEST');
  final bundle = await SimulationBundle.load(path);
  final controlFile = File('${bundle.manifest.parent.path}/control.json');
  Map control = {};
  if (await controlFile.exists()) {
    if (await controlFile.length() > 4096) {
      throw const FormatException('Control file too large');
    }
    control = jsonDecode(await controlFile.readAsString()) as Map;
  }
  final runId =
      control['runId'] as String? ??
      DateTime.now().microsecondsSinceEpoch.toString();
  final frameworkErrors = <Map<String, Object?>>[];
  Future<void> errorWrite = Future.value();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    frameworkErrors.add({
      'exception': details.exceptionAsString(),
      'stack': details.stack.toString(),
    });
    errorWrite = errorWrite
        .then((_) async {
          final file = File(
            '${bundle.manifest.parent.path}/framework-errors.json',
          );
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(
            jsonEncode({
              'runId': runId,
              'manifestSha256': bundle.manifestHash,
              'promotionAllowed': false,
              'errors': frameworkErrors,
            }),
          );
          await temporary.rename(file.path);
        })
        .catchError((Object error) {
          debugPrint('Simulation error receipt failed: $error');
        });
  };
  runApp(
    BagdarApp(
      home: SimulationLauncher(
        bundle: bundle,
        selected: control['sequenceId'] as String? ?? selected,
        autoClose: control['autoClose'] == true,
        sequenceIds: (control['sequenceIds'] as List?)?.cast<String>(),
        runId: runId,
      ),
    ),
  );
}

class SimulationLauncher extends StatefulWidget {
  final SimulationBundle bundle;
  final String selected;
  final bool autoClose;
  final String runId;
  final List<String>? sequenceIds;
  const SimulationLauncher({
    super.key,
    required this.bundle,
    this.selected = '',
    this.autoClose = false,
    this.runId = '',
    this.sequenceIds,
  });
  @override
  State<SimulationLauncher> createState() => _SimulationLauncherState();
}

class _SimulationLauncherState extends State<SimulationLauncher> {
  String? _batchStatus;

  Future<void> _writeBatchState(
    Map<String, Object?> state, {
    bool terminal = false,
  }) async {
    final file = File(
      '${widget.bundle.manifest.parent.path}/${terminal ? 'batch-complete' : 'batch-progress'}.json',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'runId': widget.runId,
        'manifestSha256': widget.bundle.manifestHash,
        'promotionAllowed': false,
        ...state,
      }),
    );
    await temporary.rename(file.path);
    if (mounted) {
      setState(
        () => _batchStatus = '${state['phase']}: ${state['sequenceId'] ?? ''}',
      );
    }
  }

  Future<void> _runSelected() async {
    try {
      final requested = widget.sequenceIds;
      if (requested != null &&
          (requested.isEmpty || requested.toSet().length != requested.length)) {
        throw const FormatException(
          'Batch selection must contain distinct sequence IDs',
        );
      }
      final selected = widget.selected == 'all'
          ? widget.bundle.sequences
                .where((s) => requested == null || requested.contains(s.id))
                .toList()
          : [
              widget.bundle.sequences.singleWhere(
                (s) => s.id == widget.selected,
              ),
            ];
      if (requested != null && selected.length != requested.length) {
        throw const FormatException('Unknown batch sequence ID');
      }
      for (var index = 0; index < selected.length; index++) {
        if (!mounted) return;
        final sequence = selected[index];
        await _writeBatchState({
          'phase': 'running',
          'sequenceId': sequence.id,
          'completedEpisodes': index,
          'selectedEpisodes': selected.length,
        });
        await _open(sequence, autoClose: widget.autoClose);
        await _writeBatchState({
          'phase': 'disposed',
          'sequenceId': sequence.id,
          'completedEpisodes': index + 1,
          'selectedEpisodes': selected.length,
        });
      }
      if (widget.selected == 'all') {
        await _writeBatchState({
          'phase': 'completed',
          'completed': true,
          'sequences': selected.length,
        }, terminal: true);
      }
    } catch (error) {
      await _writeBatchState({
        'phase': 'failed',
        'completed': false,
        'error': error.toString(),
      }, terminal: true);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.selected.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSelected());
    }
  }

  Future<void> _open(
    SimulationSequence sequence, {
    bool autoClose = false,
  }) async {
    final session = SimulationSession(
      runId: widget.runId,
      bundle: widget.bundle,
      sequence: sequence,
      outputPath:
          '${widget.bundle.manifest.parent.path}/run-${sequence.id}.json',
    );
    var routeCompleted = false;
    try {
      await runSimulationEpisode(
        context: context,
        automatic: autoClose,
        builder: (_) => AiCameraScreen(
          initialMode: AppMode.street,
          simulation: session,
          simulationAutoClose: autoClose,
        ),
      );
      routeCompleted = true;
    } finally {
      if (!session.disposed) session.dispose();
      await session.writeDisposalReport(routeCompleted: routeCompleted);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bagdar · симуляция')),
    body: ListView(
      children: [
        if (_batchStatus != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_batchStatus!),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Синтетические кадры → штатные модели и обработка Bagdar. '
            'SMS и вызовы отключены. Результаты не подтверждают работу на телефоне.',
          ),
        ),
        for (final sequence in widget.bundle.sequences)
          ListTile(
            title: Text(sequence.id),
            subtitle: Text('${sequence.frames.length} кадров'),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => _open(sequence),
          ),
      ],
    ),
  );
}
