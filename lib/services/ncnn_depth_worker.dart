import 'dart:async';
import 'dart:isolate';

import 'ncnn_depth_bridge.dart';
import 'ncnn_depth_processor.dart';
import 'ncnn_depth_worker_types.dart';

export 'ncnn_depth_worker_types.dart';

NcnnDepthBackend _nativeBackend() {
  final bridge = NcnnDepthBridge.tryCreate();
  if (bridge == null) throw StateError('NCNN native library unavailable');
  return bridge;
}

void _runDepthWorker(
  (SendPort, NcnnDepthWorkerConfig, NcnnDepthBackendFactory) args,
) {
  final (owner, config, factory) = args;
  final requests = ReceivePort();
  owner.send(['port', requests.sendPort]);
  NcnnDepthBackend? backend;
  try {
    backend = factory();
    if (!backend.init(config)) throw StateError('NCNN initialization failed');
    final processor = NcnnDepthProcessor(backend);
    owner.send(['ready', backend.isVulkan]);
    requests.listen((dynamic message) {
      final values = message as List;
      if (values[0] == 'close') {
        // This event runs only after the synchronous inference has returned.
        backend!.dispose();
        owner.send(['closed']);
        requests.close();
        Isolate.exit();
      }
      final id = values[1] as int;
      NcnnDepthReply reply;
      try {
        final input = (values[2] as NcnnDepthTransfer).materialize();
        reply = processor.process(input);
      } catch (_) {
        reply = NcnnDepthReply.unavailable('worker_exception');
      }
      owner.send(['result', id, reply]);
    });
  } catch (error) {
    owner.send(['startup_failed', error.toString()]);
    backend?.dispose();
    owner.send(['closed']);
    requests.close();
  }
}

class _DepthRequest {
  final int id;
  final NcnnDepthTransfer input;
  final Completer<NcnnDepthReply> completion = Completer<NcnnDepthReply>();
  Timer? deadline;
  final Stopwatch age = Stopwatch()..start();

  _DepthRequest(this.id, this.input);

  void finish(NcnnDepthReply reply) {
    deadline?.cancel();
    if (!completion.isCompleted) completion.complete(reply);
  }
}

/// One long-lived inference owner, one active input and one newest pending.
/// A deadline completes the caller as unavailable; it never frees/kills an
/// in-flight native context. Shutdown acknowledges native disposal explicitly.
class NcnnDepthWorker {
  static bool _nativeClaimed = false;

  final Duration replyTimeout;
  final bool _ownsNativeClaim;
  final ReceivePort _messages = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final ReceivePort _exits = ReceivePort();
  final Completer<bool> _ready = Completer<bool>();
  final Completer<bool> _closed = Completer<bool>();
  Isolate? _isolate;
  SendPort? _requests;
  _DepthRequest? _active;
  _DepthRequest? _pending;
  int _nextId = 0;
  bool _closing = false;
  bool _disposedAcknowledged = false;
  bool isVulkan = false;
  int supersededCount = 0;
  int timeoutCount = 0;
  int lateReplyCount = 0;

  NcnnDepthWorker._(this.replyTimeout, this._ownsNativeClaim) {
    _messages.listen(_receive);
    _errors.listen((_) => _fail('worker_failed'));
    _exits.listen((_) => Timer.run(() => _fail('worker_exited')));
  }

  static Future<NcnnDepthWorker> start(
    NcnnDepthWorkerConfig config, {
    Duration startupTimeout = const Duration(seconds: 30),
    Duration replyTimeout = const Duration(seconds: 2),
    NcnnDepthBackendFactory? backendFactory,
  }) async {
    if (replyTimeout <= Duration.zero || startupTimeout <= Duration.zero) {
      throw ArgumentError('worker timeouts must be positive');
    }
    final ownsNative = backendFactory == null;
    if (ownsNative && _nativeClaimed) {
      throw StateError('previous native owner has not acknowledged disposal');
    }
    if (ownsNative) _nativeClaimed = true;
    final worker = NcnnDepthWorker._(replyTimeout, ownsNative);
    try {
      worker._isolate = await Isolate.spawn(
        _runDepthWorker,
        (worker._messages.sendPort, config, backendFactory ?? _nativeBackend),
        onError: worker._errors.sendPort,
        onExit: worker._exits.sendPort,
        errorsAreFatal: true,
        debugName: 'bagdar-ncnn-depth',
      );
      if (!await worker._ready.future.timeout(startupTimeout)) {
        throw StateError('NCNN worker startup failed');
      }
      return worker;
    } catch (_) {
      if (worker._isolate == null) {
        worker._disposedAcknowledged = true;
        if (ownsNative) _nativeClaimed = false;
        worker._fail('spawn_failed');
      }
      // Do not kill a possibly running native initializer. Its eventual
      // control-port message queues close, preserving exclusive ownership.
      unawaited(worker.close());
      rethrow;
    }
  }

  int get queuedInputs =>
      (_active == null ? 0 : 1) + (_pending == null ? 0 : 1);

  Future<NcnnDepthReply> analyze(NcnnDepthTransfer input) {
    if (_closing || _requests == null) {
      return Future.value(NcnnDepthReply.unavailable('worker_closed'));
    }
    final request = _DepthRequest(++_nextId, input);
    if (_active == null) {
      _dispatch(request);
    } else {
      if (_pending != null) {
        supersededCount++;
        _pending!.finish(NcnnDepthReply.unavailable('worker_superseded'));
      }
      _pending = request;
      request.deadline = Timer(replyTimeout, () => _expire(request));
    }
    return request.completion.future;
  }

  void _dispatch(_DepthRequest request) {
    if (request.age.elapsed >= replyTimeout) {
      timeoutCount++;
      request.finish(NcnnDepthReply.unavailable('worker_timeout'));
      return;
    }
    _active = request;
    // A queued request keeps its original deadline, including time waiting.
    request.deadline ??= Timer(replyTimeout, () => _expire(request));
    _requests!.send(['infer', request.id, request.input]);
  }

  void _expire(_DepthRequest request) {
    if (identical(_active, request) || identical(_pending, request)) {
      if (identical(_pending, request)) _pending = null;
      timeoutCount++;
      request.finish(NcnnDepthReply.unavailable('worker_timeout'));
    }
  }

  void _receive(dynamic message) {
    final values = message as List;
    switch (values[0]) {
      case 'port':
        _requests = values[1] as SendPort;
        if (_closing) _requests!.send(['close']);
      case 'ready':
        isVulkan = values[1] as bool;
        if (!_ready.isCompleted) _ready.complete(!_closing);
      case 'startup_failed':
        if (!_ready.isCompleted) _ready.complete(false);
      case 'closed':
        _disposedAcknowledged = true;
        if (_ownsNativeClaim) _nativeClaimed = false;
        _fail('worker_closed');
      case 'result':
        final request = _active;
        if (request == null || request.id != values[1]) return;
        if (request.age.elapsed >= replyTimeout) {
          if (!request.completion.isCompleted) timeoutCount++;
          lateReplyCount++;
          request.finish(NcnnDepthReply.unavailable('worker_timeout'));
        } else {
          request.finish(values[2] as NcnnDepthReply);
        }
        _active = null;
        if (!_closing) {
          final next = _pending;
          _pending = null;
          if (next != null) _dispatch(next);
        }
    }
  }

  void _fail(String reason) {
    _closing = true;
    _active?.finish(NcnnDepthReply.unavailable(reason));
    _pending?.finish(NcnnDepthReply.unavailable(reason));
    _active = null;
    _pending = null;
    if (!_ready.isCompleted) _ready.complete(false);
    if (!_closed.isCompleted) _closed.complete(_disposedAcknowledged);
    _messages.close();
    _errors.close();
    _exits.close();
  }

  Future<bool> close() {
    if (!_closing) {
      _closing = true;
      _active?.finish(NcnnDepthReply.unavailable('worker_closed'));
      _pending?.finish(NcnnDepthReply.unavailable('worker_closed'));
      _pending = null;
      _requests?.send(['close']);
    }
    return _closed.future;
  }
}
