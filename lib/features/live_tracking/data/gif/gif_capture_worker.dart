import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Palette size handed to [img.NeuralQuantizer] — matches GIF's own 8-bit
/// color-index limit, so this is the max useful value, not a tunable knob.
const int _gifNumColors = 256;

/// Fraction of pixels sampled when *training* the palette (1-in-N) — only
/// affects [img.NeuralQuantizer] construction cost, not per-frame encode
/// cost, since the trained network is reused across frames (see
/// [gifWorkerEntryPoint]). The `image` package's own docs suggest 10 as a
/// quality/speed default; bumped to 20 here because on-device profiling
/// (with [_colorLut] already in place) showed *every* rebuild/refresh — not
/// just the very first one — costing 850ms-1.05s regardless, entirely from
/// this training step, and that's what was still visible as a periodic
/// stutter every [_paletteRefreshInterval]. Halving the sample count roughly
/// halves that cost; the palette itself is still trained from a quarter
/// million+ pixel frame even at a 1-in-20 sample, so accuracy loss is
/// negligible next to the 256-color quantization it's already doing.
const int _gifSamplingFactor = 20;

/// How often the palette is refreshed against a fresh frame, rather than
/// reused as-is. Building/updating [img.NeuralQuantizer] is the one
/// genuinely expensive step in this pipeline (see [gifWorkerEntryPoint]), so
/// this trades a small amount of color accuracy as the scene changes (e.g.
/// panning to a very differently-lit area) for keeping that cost off the hot
/// per-frame path. Bumped from 4s to 10s after on-device profiling showed
/// each refresh costing ~1s regardless of how cheap steady-state frames had
/// gotten — at 4s, a typical 10-15s recommended session hit 2-3 of these
/// stutters; at 10s, most sessions hit at most one.
const Duration _paletteRefreshInterval = Duration(seconds: 10);

/// Bits per channel kept when bucketing a pixel's RGB into [_colorLut] —
/// 5 bits/channel = 32 levels/channel = 32768 total buckets. Building the
/// LUT costs one nearest-color search per bucket (cheap: done only when the
/// palette is (re)built, not per pixel), and looking a pixel up in it at
/// encode time is then just a couple of shifts and an array read instead of
/// a search — see [gifWorkerEntryPoint] for why that distinction matters.
const int _lutBitsPerChannel = 5;
const int _lutChannelShift = 8 - _lutBitsPerChannel;
const int _lutSize = 1 << (_lutBitsPerChannel * 3);

/// Width (px) frames are downscaled to *if* wider than this. Deliberately
/// set above any real phone's logical width (`boundary.toImage(pixelRatio:
/// 1.0)` captures at the RepaintBoundary's *logical* pixel size, commonly
/// ~360-430px on a phone) so this is normally a no-op and the GIF keeps the
/// overlay's box/label text — drawn at a fixed 12px font, already small —
/// at full native sharpness instead of being softened further. A smaller
/// cap (320px) was tried first to bound encode cost, but that cost never
/// mattered: this whole pipeline runs on [gifWorkerEntryPoint]'s background
/// isolate, with ample slack given detections land every few seconds, not
/// every frame — only a genuinely oversized capture (a tablet, say) should
/// ever hit this cap.
const int _gifTargetWidth = 720;

/// UI isolate -> worker: add one frame to the in-progress GIF.
class _AddFrameMessage {
  const _AddFrameMessage({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;
  final TransferableTypedData pixels;
}

/// UI isolate -> worker: finalize the GIF and send back the encoded bytes.
class _FinishMessage {
  const _FinishMessage();
}

/// worker -> UI isolate: this frame is done encoding — the backpressure
/// signal callers use to know when it's safe to send another.
class _FrameAckMessage {
  const _FrameAckMessage({this.error});
  final String? error;
}

/// worker -> UI isolate: reply to a [_FinishMessage].
class _FinishResultMessage {
  const _FinishResultMessage({this.bytes, this.error});
  final Uint8List? bytes;
  final String? error;
}

/// Runs entirely on the worker isolate spawned by [GifCaptureWorker.start]
/// and kept alive for one live-tracking session. Owns the single
/// [img.GifEncoder] for that whole session — the reason this needs a
/// long-lived isolate rather than `compute()` (which spawns a fresh,
/// stateless isolate per call and can't carry the encoder's palette/LZW
/// state between calls; see `live_frame_preprocessor.dart` for the
/// `compute()` pattern used where per-call statelessness is fine).
void gifWorkerEntryPoint(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  // Wall-clock time the previous `_AddFrameMessage` was received, so each
  // frame's *own* GIF duration can reflect how long it actually took to
  // arrive rather than always being the nominal capture interval. Frames
  // get dropped whenever this isolate is still busy encoding the previous
  // one (see `GifCaptureWorker.isBusy` / `LiveCameraScreen._captureGifFrame`
  // — the same drop-if-busy backpressure the detection pipeline uses), and
  // encoding a real photographic frame with the neural quantizer can take
  // longer than the nominal capture interval. With a fixed per-frame
  // duration, those drops silently compress the timeline: a session that
  // ran for real seconds but only produced a handful of surviving frames
  // would play back in a fraction of a second — fast-forwarded, not normal
  // speed. Measuring the real gap and encoding it per-frame keeps playback
  // duration matching real elapsed time regardless of how many frames were
  // dropped in between.
  DateTime? lastFrameAt;

  final encoder = img.GifEncoder(
    // Centiseconds (1/100s), *not* milliseconds — 15 here is 150ms/frame.
    // Only used as the fallback for the very first frame, which has no
    // prior frame to measure a real gap from; every subsequent frame gets
    // its own measured duration (see `lastFrameAt` above) passed explicitly
    // to `encoder.addFrame`, which overrides this default per-frame.
    delay: 15,
    repeat: 0,
  );

  // The palette used to turn each captured RGBA frame into the indexed-color
  // image GIF requires. Built once from the first frame and periodically
  // refreshed (see [_paletteRefreshInterval]) rather than rebuilt on every
  // single frame, which is what `GifEncoder.addFrame` does *by default* when
  // handed a non-palette image: it constructs a brand-new `NeuralQuantizer`
  // — a ~100-cycle Kohonen network trained over a sample of the frame's
  // pixels — from scratch on every call. That per-frame rebuild, not
  // dithering or LZW, is what made frames take 3-4 real seconds to encode
  // on-device (dithering made it worse — a bug in the octree+dither
  // combination, and dithering's inherently harder-to-compress output, both
  // compounded on top of this).
  //
  // Reusing one trained network still wasn't enough on its own: a real
  // session recorded after that fix showed most frames still costing
  // 400-800ms, spiking to 1.5-2.6s on refresh frames. The remaining cost was
  // `Quantizer.getIndexImage()`'s per-pixel nearest-color *search*
  // (`NeuralQuantizer._inxSearch`) plus the `Color` object it allocates for
  // every one of a frame's ~250k+ pixels via the `Image` iterator — on this
  // device's Dart VM, that's the expensive part, not just palette training.
  // [_colorLut] replaces that search with an O(1) array lookup: quantize
  // each pixel's RGB down to [_lutBitsPerChannel] bits/channel and read the
  // pre-computed nearest palette index for that bucket, working directly on
  // the raw RGBA byte buffer instead of the boxed `Pixel`/`Color` iterator.
  // The (still relatively expensive) real nearest-color search only runs
  // [_lutSize] times, when the LUT itself is (re)built — not per pixel.
  img.NeuralQuantizer? quantizer;
  Uint8List? colorLut;
  DateTime? lastPaletteBuildAt;

  void rebuildColorLut(img.NeuralQuantizer q) {
    final lut = Uint8List(_lutSize);
    const half = 1 << (_lutChannelShift - 1);
    var i = 0;
    for (var r5 = 0; r5 < (1 << _lutBitsPerChannel); r5++) {
      final r = (r5 << _lutChannelShift) | half;
      for (var g5 = 0; g5 < (1 << _lutBitsPerChannel); g5++) {
        final g = (g5 << _lutChannelShift) | half;
        for (var b5 = 0; b5 < (1 << _lutBitsPerChannel); b5++) {
          final b = (b5 << _lutChannelShift) | half;
          lut[i++] = q.getColorIndexRgb(r, g, b);
        }
      }
    }
    colorLut = lut;
  }

  workerReceivePort.listen((dynamic message) {
    if (message is _AddFrameMessage) {
      String? error;
      try {
        final now = DateTime.now();
        int? durationCentiseconds;
        final previous = lastFrameAt;
        if (previous != null) {
          final elapsedMs = now.difference(previous).inMilliseconds;
          // GIF's duration field is an unsigned 16-bit centisecond count;
          // clamp away from 0 (some viewers treat a 0-duration frame as
          // "no delay", effectively skipping it) and away from overflow
          // (e.g. the app was backgrounded mid-session, leaving a huge gap
          // before the next frame).
          durationCentiseconds = (elapsedMs / 10).round().clamp(1, 65535);
        }
        lastFrameAt = now;

        final buffer = message.pixels.materialize();
        var frame = img.Image.fromBytes(
          width: message.width,
          height: message.height,
          bytes: buffer,
          order: img.ChannelOrder.rgba,
        );
        if (frame.width > _gifTargetWidth) {
          frame = img.copyResize(frame, width: _gifTargetWidth);
        }

        final currentQuantizer = quantizer;
        final needsPaletteBuild = currentQuantizer == null ||
            now.difference(lastPaletteBuildAt!) >= _paletteRefreshInterval;
        if (needsPaletteBuild) {
          final q = currentQuantizer == null
              ? (quantizer = img.NeuralQuantizer(
                  frame,
                  numberOfColors: _gifNumColors,
                  samplingFactor: _gifSamplingFactor,
                ))
              : (currentQuantizer..addImage(frame));
          rebuildColorLut(q);
          lastPaletteBuildAt = now;
        }

        // Raw RGBA bytes, not the `Image` pixel iterator — see the comment
        // above [colorLut] for why that distinction is the whole point.
        final rgba = frame.getBytes(order: img.ChannelOrder.rgba);
        final lut = colorLut!;
        final pixelCount = frame.width * frame.height;
        final indices = Uint8List(pixelCount);
        var si = 0;
        for (var i = 0; i < pixelCount; i++) {
          final r = rgba[si] >> _lutChannelShift;
          final g = rgba[si + 1] >> _lutChannelShift;
          final b = rgba[si + 2] >> _lutChannelShift;
          si += 4;
          indices[i] =
              lut[(r << (_lutBitsPerChannel * 2)) | (g << _lutBitsPerChannel) | b];
        }
        final indexedFrame = img.Image.fromBytes(
          width: frame.width,
          height: frame.height,
          bytes: indices.buffer,
          numChannels: 1,
          palette: quantizer!.palette,
        );
        encoder.addFrame(indexedFrame, duration: durationCentiseconds);
      } catch (e) {
        error = e.toString();
      }
      mainSendPort.send(_FrameAckMessage(error: error));
    } else if (message is _FinishMessage) {
      Uint8List? bytes;
      String? error;
      try {
        bytes = encoder.finish();
      } catch (e) {
        error = e.toString();
      }
      mainSendPort.send(_FinishResultMessage(bytes: bytes, error: error));
    }
  });
}

/// Owns a long-lived background isolate that encodes the live session's
/// GIF, so the expensive, synchronous, pure-Dart work `img.GifEncoder`
/// does on every `addFrame()`/`finish()` call (palette quantization,
/// dithering, LZW encoding — all full-frame passes) never blocks the UI
/// isolate that's also rendering the camera preview. One instance per
/// session: construct and [start] in the screen's `_start()`, [dispose] in
/// `_stop()`/session teardown.
class GifCaptureWorker {
  Isolate? _isolate;
  ReceivePort? _mainReceivePort;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _workerSendPort;
  bool _busy = false;
  bool _disposed = false;
  Completer<Uint8List?>? _finishCompleter;

  /// True while the worker is still encoding the last frame handed to it.
  /// Callers should skip sending another frame while this is true rather
  /// than queueing — mirrors `LiveTrackingNotifier`'s own busy-drop guard
  /// for the detection pipeline, so a session where GIF encoding can't
  /// keep up with detection cadence never builds an unbounded backlog.
  bool get isBusy => _busy;

  /// Spawns the worker isolate and waits for its ready handshake. Safe to
  /// call without awaiting — [addFrame] and [finish] are no-ops until the
  /// handshake completes, so callers don't need to gate session/camera
  /// startup on isolate spawn time. Swallows spawn failures (e.g. resource
  /// exhaustion) so a broken worker just means no GIF gets produced this
  /// session — live detection itself is unaffected either way.
  Future<void> start() async {
    final ready = Completer<SendPort>();
    final mainReceivePort = ReceivePort();
    _mainReceivePort = mainReceivePort;

    _subscription = mainReceivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is _FrameAckMessage) {
        _busy = false;
      } else if (message is _FinishResultMessage) {
        _finishCompleter?.complete(message.bytes);
        _finishCompleter = null;
      } else if (message is List) {
        // Isolate.spawn's `onError` delivers [errorString, stackString] on
        // this same port for an uncaught worker-isolate error. Treat the
        // worker as broken from here on rather than risk sending into a
        // possibly-corrupted or exited isolate.
        _failAndTearDown();
      }
    });

    try {
      _isolate = await Isolate.spawn(
        gifWorkerEntryPoint,
        mainReceivePort.sendPort,
        onError: mainReceivePort.sendPort,
        errorsAreFatal: false,
        debugName: 'gif-capture-worker',
      );
      _workerSendPort = await ready.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('gif worker did not start'),
      );
    } catch (_) {
      _workerSendPort = null;
    }
  }

  /// Hands one frame's raw RGBA pixels off to the worker for encoding.
  /// Fire-and-forget: returns `true` if the frame was actually sent,
  /// `false` if it was dropped (worker not ready, still busy with the
  /// previous frame, or already disposed) — callers use this to decide
  /// whether to reset their own capture-cadence throttle.
  bool addFrame({
    required int width,
    required int height,
    required ByteData pixels,
  }) {
    final sendPort = _workerSendPort;
    if (_disposed || sendPort == null || _busy) return false;
    _busy = true;
    sendPort.send(
      _AddFrameMessage(
        width: width,
        height: height,
        pixels: TransferableTypedData.fromList([pixels]),
      ),
    );
    return true;
  }

  /// Finalizes the GIF and returns its encoded bytes, or `null` if no
  /// frames were ever added, the worker never started, or it errored.
  /// Doesn't need to wait for [isBusy] to clear first: messages on one
  /// `SendPort`/`ReceivePort` pair are delivered and handled strictly in
  /// order, so the finish request simply queues up behind whatever frame
  /// is currently mid-encode.
  Future<Uint8List?> finish() {
    final sendPort = _workerSendPort;
    if (_disposed || sendPort == null) return Future.value(null);
    final completer = Completer<Uint8List?>();
    _finishCompleter = completer;
    sendPort.send(const _FinishMessage());
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  }

  /// Kills the worker isolate and releases its ports. Idempotent — safe to
  /// call more than once, or without ever calling [finish].
  void dispose() => _failAndTearDown();

  void _failAndTearDown() {
    if (_disposed) return;
    _disposed = true;
    _finishCompleter?.complete(null);
    _finishCompleter = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _subscription?.cancel();
    _subscription = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _workerSendPort = null;
  }
}
