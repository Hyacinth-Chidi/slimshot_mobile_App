import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/ad_pacing.dart';
import 'package:slimshotai/core/services/work_ad.dart';

class _FakeAd implements InterstitialPresenter {
  @override
  bool ready = true;

  int shows = 0;
  Completer<void>? _open;

  @override
  Future<void> show() {
    shows++;
    _open = Completer<void>();
    return _open!.future;
  }

  Future<void> close() async {
    _open!.complete();
    await pumpEventQueue();
  }
}

/// An interstitial over a job already running — a compression, a strip:
/// the job's own progress shows first, the ad never holds the job up, and
/// what follows the job (the result, the report) waits for the ad to close.
void main() {
  late DateTime now;
  late Completer<void> work;
  late Completer<void> leadIn;
  late _FakeAd ad;
  late AdPacing pacing;
  late double progress;
  late bool wanted;
  late bool done;

  setUp(() {
    now = DateTime(2026, 10, 28, 12);
    work = Completer<void>();
    leadIn = Completer<void>();
    ad = _FakeAd();
    pacing = AdPacing(clock: () => now);
    progress = 0;
    wanted = true;
    done = false;
  });

  void start(AdPlacement placement, WorkAdRule rule) {
    adOverWork(
      placement: placement,
      rule: rule,
      work: work.future,
      progress: () => progress,
      wanted: () => wanted,
      pacing: pacing,
      presenter: ad,
      delay: (_) => leadIn.future,
      clock: () => now,
    ).then((_) => done = true);
  }

  Future<void> leadInEnds(Duration after) async {
    now = now.add(after);
    leadIn.complete();
    await pumpEventQueue();
  }

  Future<void> workEnds() async {
    work.complete();
    await pumpEventQueue();
  }

  group('video compression', () {
    test('a job still running after the lead-in, with time to go, gets its '
        'ad over it, and what follows waits for both', () async {
      start(AdPlacement.videoCompression, kVideoCompressionAdRule);
      progress = 0.1; // a tenth in 2 s: about 18 s to go
      await leadInEnds(const Duration(seconds: 2));
      expect(ad.shows, 1);
      expect(pacing.isDue(AdPlacement.videoCompression), isFalse);

      await workEnds();
      expect(done, isFalse, reason: 'the ad is still up');
      await ad.close();
      expect(done, isTrue);
    });

    test('an ad closed before the job ends leaves what follows to the job',
        () async {
      start(AdPlacement.videoCompression, kVideoCompressionAdRule);
      progress = 0.1;
      await leadInEnds(const Duration(seconds: 2));
      await ad.close();
      expect(done, isFalse, reason: 'still compressing');
      await workEnds();
      expect(done, isTrue);
    });

    test('a job nearly done after the lead-in gets no ad', () async {
      start(AdPlacement.videoCompression, kVideoCompressionAdRule);
      progress = 0.5; // half in 2 s: 2 s to go
      await leadInEnds(const Duration(seconds: 2));
      expect(ad.shows, 0);
      expect(pacing.isDue(AdPlacement.videoCompression), isTrue,
          reason: 'nothing showed');
      await workEnds();
      expect(done, isTrue);
    });

    test('a job done inside the lead-in gets no ad', () async {
      start(AdPlacement.videoCompression, kVideoCompressionAdRule);
      await workEnds();
      expect(ad.shows, 0);
      expect(done, isTrue);
    });

    test('a job with no progress yet by then counts as a long one', () async {
      start(AdPlacement.videoCompression, kVideoCompressionAdRule);
      await leadInEnds(const Duration(seconds: 2));
      expect(ad.shows, 1);
    });
  });

  group('Privacy Strip', () {
    test('a strip done inside the lead-in still gets its ad, before what '
        'follows', () async {
      start(AdPlacement.privacyStrip, kPrivacyStripAdRule);
      await workEnds();
      expect(ad.shows, 1);
      expect(done, isFalse, reason: 'the report waits for the ad');
      await ad.close();
      expect(done, isTrue);
    });

    test('a strip still running after the lead-in gets its ad over it, '
        'however near done', () async {
      start(AdPlacement.privacyStrip, kPrivacyStripAdRule);
      progress = 0.95;
      await leadInEnds(const Duration(seconds: 1));
      expect(ad.shows, 1);
    });
  });

  // Photos compress in a second or two: the video rule — only with about
  // ten seconds to go — would almost never show one.
  test('photo compression is timed as Privacy Strip is: every job, however '
      'fast', () {
    expect(kPhotoCompressionAdRule.evenIfQuick, isTrue);
    expect(kPhotoCompressionAdRule.minRemaining, isNull);
    expect(kPhotoCompressionAdRule.leadIn, kPrivacyStripAdRule.leadIn);
  });

  group('after a job', () {
    void finish(AdPlacement placement) {
      adAfterWork(
        placement: placement,
        pacing: pacing,
        presenter: ad,
        wanted: () => wanted,
      ).then((_) => done = true);
    }

    test('a finished job gets its ad, and what follows waits for it',
        () async {
      finish(AdPlacement.export);
      await pumpEventQueue();
      expect(ad.shows, 1);
      expect(pacing.isDue(AdPlacement.export), isFalse);
      expect(done, isFalse, reason: 'the result waits for the ad');
      await ad.close();
      expect(done, isTrue);
    });

    test('an ad not due, not loaded or no longer wanted: nothing, at once',
        () async {
      ad.ready = false;
      finish(AdPlacement.export);
      await pumpEventQueue();
      expect((ad.shows, done), (0, true));

      ad.ready = true;
      done = false;
      wanted = false;
      finish(AdPlacement.export);
      await pumpEventQueue();
      expect((ad.shows, done), (0, true));

      wanted = true;
      done = false;
      pacing.shown(AdPlacement.export);
      finish(AdPlacement.export);
      await pumpEventQueue();
      expect((ad.shows, done), (0, true));
    });
  });

  test('nothing shows before the lead-in ends', () async {
    start(AdPlacement.videoCompression, kVideoCompressionAdRule);
    progress = 0.1;
    await pumpEventQueue();
    expect(ad.shows, 0);
  });

  test('an ad not loaded is skipped, never waited for', () async {
    ad.ready = false;
    start(AdPlacement.privacyStrip, kPrivacyStripAdRule);
    await workEnds();
    expect(ad.shows, 0);
    expect(done, isTrue);
  });

  // Left with Back, cancelled, or failed by the time the ad would show: an
  // ad then lands somewhere the user never asked to wait — the unexpected
  // interstitial Google disallows.
  test('a job no longer wanted when its ad is due gets none', () async {
    start(AdPlacement.privacyStrip, kPrivacyStripAdRule);
    wanted = false;
    await workEnds();
    expect(ad.shows, 0);
    expect(done, isTrue);
  });

  test('a job left during its lead-in gets no ad over it', () async {
    start(AdPlacement.videoCompression, kVideoCompressionAdRule);
    progress = 0.1;
    wanted = false;
    await leadInEnds(const Duration(seconds: 2));
    expect(ad.shows, 0);
    expect(pacing.isDue(AdPlacement.videoCompression), isTrue);
  });

  test('a placement not due shows nothing', () async {
    pacing.shown(AdPlacement.privacyStrip);
    now = now.add(const Duration(minutes: 5));
    start(AdPlacement.privacyStrip, kPrivacyStripAdRule);
    await workEnds();
    expect(ad.shows, 0);
    expect(done, isTrue);
  });
}
