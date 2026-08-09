// Injects pointer events into the running app through the Dart VM service.
//
// Driven by bin/dev_input.sh - see that script for usage and for why this
// exists. Kept in Dart rather than folded into the shell script because the VM
// service will not compile expressions over its HTTP GET endpoint (see below),
// and dart:io is the only websocket client on this box that needs no packages.
//
// Usage: dart dev_input.dart <ws-uri> <command> [args...]
//
// Deliberately depends on nothing outside dart:*, so it runs with a bare
// `dart dev_input.dart` from a directory with no pubspec.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The library whose scope expressions are evaluated in.
///
/// Not the app's own root library: `main.dart` imports material.dart, which
/// re-exports enough for `PointerDownEvent` but *not* `PointerScrollEvent` or
/// `PointerDeviceKind`, so a scroll fails to compile there with a confusing
/// "Couldn't find constructor". The gestures binding library has every pointer
/// type in scope plus `GestureBinding.instance` itself.
const _scopeLibrary = 'package:flutter/src/gestures/binding.dart';

/// Printed by an injected event that throws, and grepped for by dev_input.sh.
const _errorMarker = '[DEV_INPUT] ERROR';

/// The pointer id every event in this invocation carries.
///
/// Never 0, and never the same twice. `handlePointerEvent` asserts that a
/// pointer going down has no hit-test result recorded for it, and an
/// interrupted sequence - a drag whose up never arrived - leaves one behind
/// forever. Sharing the default id 0 means one failed drag makes every later
/// tap assert, which reads as a broken script rather than as leftover state.
/// A fresh id per run sidesteps it; a hot restart clears the strays.
final int _pointerId = DateTime.now().millisecondsSinceEpoch % 1000000 + 1;

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: dart dev_input.dart <ws-uri> <command> [args...]');
    exit(2);
  }
  final client = await _VmClient.connect(args[0]);
  try {
    await client.run(args[1], args.sublist(2));
  } on _InputError catch (e) {
    stderr.writeln('ERROR: ${e.message}');
    exit(1);
  } finally {
    await client.close();
  }
}

class _InputError implements Exception {
  _InputError(this.message);
  final String message;
}

class _VmClient {
  _VmClient(this._ws, this._isolateId, this._scopeId, this._call);

  final WebSocket _ws;
  final String _isolateId;
  final String _scopeId;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
      _call;

  /// Physical pixels per logical pixel.
  ///
  /// Coordinates on the command line are *screenshot* pixels, because a
  /// screenshot is the only way to find a target. `bin/dev_screenshot.sh`
  /// returns the rasterized frame, which is physical pixels, while
  /// [GestureBinding.handlePointerEvent] wants logical ones - so everything
  /// gets divided by this on the way in. It is 1.0 on the Crostini desktop,
  /// which is exactly why getting it wrong here would go unnoticed.
  late final double _dpr;

  static Future<_VmClient> connect(String wsUri) async {
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(wsUri);
    } on Exception catch (e) {
      stderr.writeln('ERROR: cannot open $wsUri');
      stderr.writeln('       $e');
      stderr.writeln('       If the app is running, this is the agent sandbox '
          'blocking localhost -');
      stderr.writeln('       re-run with the sandbox disabled.');
      exit(1);
    }

    var nextId = 0;
    final pending = <int, Completer<Map<String, dynamic>>>{};
    ws.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        // Streamed events carry no id; only replies resolve a call.
        if (msg['id'] == null) return;
        pending.remove(int.parse('${msg['id']}'))?.complete(msg);
      },
      onDone: () {
        for (final c in pending.values) {
          c.completeError(_InputError('the VM service closed the connection'));
        }
        pending.clear();
      },
    );

    Future<Map<String, dynamic>> call(
        String method, Map<String, dynamic> params) {
      final id = ++nextId;
      final c = Completer<Map<String, dynamic>>();
      pending[id] = c;
      ws.add(jsonEncode(
          {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
      return c.future;
    }

    final vm = await call('getVM', const {});
    final isolates = vm['result']?['isolates'] as List?;
    if (isolates == null || isolates.isEmpty) {
      throw _InputError('the VM service reports no isolates');
    }
    final isolateId = isolates.first['id'] as String;

    final iso = await call('getIsolate', {'isolateId': isolateId});
    final libraries = iso['result']?['libraries'] as List? ?? const [];
    final scope = libraries.cast<Map<String, dynamic>>().where(
        (l) => l['uri'] == _scopeLibrary);
    if (scope.isEmpty) {
      throw _InputError(
          'no $_scopeLibrary in the running isolate - is this a Flutter app?');
    }

    final client =
        _VmClient(ws, isolateId, scope.first['id'] as String, call);

    client._dpr = double.parse(await client._evaluateRaw(
        'GestureBinding.instance.platformDispatcher.views.first'
        '.devicePixelRatio.toString()'));

    // Resampling batches pointer events against the frame clock instead of
    // dispatching them, so injected events would be silently swallowed or
    // reordered. It is off by default; say so loudly rather than let a tap
    // vanish into the resampler and read as a broken hit test.
    final resampling =
        await client._evaluateRaw('GestureBinding.instance.resamplingEnabled');
    if (resampling == 'true') {
      stderr.writeln('WARNING: pointer resampling is enabled; injected events '
          'may be delayed or dropped.');
    }

    return client;
  }

  /// Evaluates [expression] and returns its `valueAsString`.
  Future<String> _evaluateRaw(String expression) async {
    final reply = await _call('evaluate', {
      'isolateId': _isolateId,
      'targetId': _scopeId,
      'expression': expression,
    });

    final error = reply['error'];
    if (error != null) {
      final details = error['data']?['details'] ?? error['message'];
      throw _InputError('the VM service rejected the expression:\n$details');
    }

    final result = reply['result'] as Map<String, dynamic>;
    // An expression that throws comes back as @Error with a real result field,
    // so a bare "did we get a result" check would call a crash a success.
    if (result['type'] == '@Error' || result['kind'] == 'Error') {
      throw _InputError('the expression threw: ${result['message']}');
    }
    if (result['type'] == 'Sentinel') {
      throw _InputError('the isolate went away mid-evaluation '
          '(${result['valueAsString']})');
    }
    return result['valueAsString'] as String? ?? '';
  }

  /// Queues [body] onto the app's event loop and waits for it to be accepted.
  ///
  /// `evaluate` takes an expression, not statements, so the statements go in a
  /// closure literal that is called on the spot.
  ///
  /// The `Timer.run` is the load-bearing part. The VM runs an evaluation at the
  /// next safepoint, which can be *inside* whatever the isolate is doing -
  /// including halfway through `drawFrame`. Dispatching a pointer event from
  /// there reenters the framework during a build, and the scroll handler throws
  /// `setState() called during build`. It only shows up once something is
  /// animating, so a tap on an idle app looks perfectly fine and a drag blows
  /// up on its second move. Handing the event to the event loop instead means
  /// it is always delivered on a clean turn.
  ///
  /// Timers fire in the order they were created, so a down/move/up sequence
  /// sent as separate calls still arrives in order.
  ///
  /// The cost of queueing is that a throw no longer comes back in the reply -
  /// `evaluate` has already returned "ok" by then. Worse, the framework's own
  /// error reporter cannot render it: an evaluated closure appears in the stack
  /// as a bare `Eval ()` frame with no file or line, which fails an assertion
  /// inside `StackFrame.fromStackTraceLine`, so the real exception is buried
  /// under a regex-match assertion. Hence the try/catch and the marker - it is
  /// the only legible report, and bin/dev_input.sh greps the log for it so a
  /// failed injection cannot exit 0.
  Future<void> _dispatch(String body) async {
    final value = await _evaluateRaw('(() { Timer.run(() {'
        ' try { $body } catch (e) { debugPrint("$_errorMarker \$e"); }'
        ' }); return "ok"; })()');
    if (value != 'ok') throw _InputError('unexpected reply: $value');
  }

  /// Converts screenshot pixels to the logical pixels the framework expects.
  String _offset(double x, double y) =>
      'Offset(${x / _dpr}, ${y / _dpr})';

  Future<void> run(String command, List<String> args) async {
    switch (command) {
      case 'tap':
        _expectArgs(command, args, 2, 'X Y');
        await _tap(_num(args[0], 'X'), _num(args[1], 'Y'));
      case 'scroll':
        _expectArgs(command, args, 3, 'X Y DY');
        await _scroll(
            _num(args[0], 'X'), _num(args[1], 'Y'), _num(args[2], 'DY'));
      case 'drag':
        if (args.length < 4 || args.length > 5) {
          throw _InputError('drag takes X1 Y1 X2 Y2 [MS], got ${args.length} '
              'argument(s)');
        }
        await _drag(
          _num(args[0], 'X1'),
          _num(args[1], 'Y1'),
          _num(args[2], 'X2'),
          _num(args[3], 'Y2'),
          args.length == 5 ? _num(args[4], 'MS').round() : 300,
        );
      default:
        throw _InputError("unknown command '$command' "
            '(expected tap, scroll or drag)');
    }
  }

  void _expectArgs(String command, List<String> args, int n, String shape) {
    if (args.length != n) {
      throw _InputError(
          '$command takes $shape, got ${args.length} argument(s)');
    }
  }

  double _num(String raw, String name) =>
      double.tryParse(raw) ??
      (throw _InputError("$name must be a number, got '$raw'"));

  Future<void> _tap(double x, double y) async {
    final p = _offset(x, y);
    // Down and up in one evaluation, so they land in a single event-loop turn:
    // a tap recognizer wants both inside its deadline, and a second round trip
    // can exceed it on a slow connection.
    await _dispatch('final b = GestureBinding.instance;'
        'b.handlePointerEvent(const PointerDownEvent(position: $p, '
        'pointer: $_pointerId));'
        'b.handlePointerEvent(const PointerUpEvent(position: $p, '
        'pointer: $_pointerId));');
  }

  Future<void> _scroll(double x, double y, double dy) async {
    // A wheel signal, not a drag: Scrollable hit-tests PointerScrollEvent
    // directly and applies the delta at once, so it needs no slop, no
    // intermediate frames, and produces no fling. Positive dy scrolls down.
    await _dispatch('GestureBinding.instance.handlePointerEvent('
        'const PointerScrollEvent(position: ${_offset(x, y)}, '
        'kind: PointerDeviceKind.mouse, '
        'scrollDelta: ${_offset(0, dy)}));');
  }

  Future<void> _drag(
      double x1, double y1, double x2, double y2, int ms) async {
    const steps = 10;
    final clock = Stopwatch()..start();

    Future<void> send(String event) =>
        _dispatch('GestureBinding.instance.handlePointerEvent($event);');

    // Timestamps are real elapsed time, not the requested duration. The
    // velocity tracker reads them, so claiming a 300ms drag that actually took
    // 2s over the wire would synthesise a fling that never happened.
    String stamp() => 'timeStamp: Duration(microseconds: '
        '${clock.elapsedMicroseconds})';

    await send('PointerDownEvent(position: ${_offset(x1, y1)}, '
        'pointer: $_pointerId, ${stamp()})');

    var prevX = x1;
    var prevY = y1;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final x = x1 + (x2 - x1) * t;
      final y = y1 + (y2 - y1) * t;
      // delta matters as much as position: DragGestureRecognizer accumulates
      // event.delta, so moves with a correct position and a zero delta scroll
      // nothing at all.
      await send('PointerMoveEvent(position: ${_offset(x, y)}, '
          'delta: ${_offset(x - prevX, y - prevY)}, '
          'pointer: $_pointerId, ${stamp()})');
      prevX = x;
      prevY = y;
      final target = Duration(milliseconds: (ms * t).round());
      final remaining = target - clock.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    }

    await send('PointerUpEvent(position: ${_offset(x2, y2)}, '
        'pointer: $_pointerId, ${stamp()})');
  }

  Future<void> close() => _ws.close();
}
