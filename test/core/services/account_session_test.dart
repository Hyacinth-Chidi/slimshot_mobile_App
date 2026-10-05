import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/account_session.dart';

import '../../support/account_fakes.dart';

void main() {
  late MemoryTokenVault vault;
  late AccountSession session;
  const first = SessionTokens(accessToken: 'a1', refreshToken: 'r1');
  const second = SessionTokens(accessToken: 'a2', refreshToken: 'r2');

  setUp(() {
    vault = MemoryTokenVault();
    session = AccountSession(vault: vault);
  });

  test('saves, reads and ends a session, the profile with it', () async {
    expect(await session.read(), isNull);
    await session.save(first);
    await session.saveProfile('{"id":"u1"}');
    final read = await session.read();
    expect((read!.accessToken, read.refreshToken), ('a1', 'r1'));
    expect(await session.readProfile(), '{"id":"u1"}');

    final ended = expectLater(session.ended, emits(null));
    await session.end();
    await ended;
    expect(await session.read(), isNull);
    expect(vault.values, isEmpty);
  });

  test('two refusals at once share one refresh', () async {
    await session.save(first);
    var refreshes = 0;
    final gate = Completer<void>();
    Future<SessionTokens?> refresh(String token) async {
      refreshes++;
      expect(token, 'r1');
      await gate.future;
      return second;
    }

    final a = session.refreshAfter('a1', refresh);
    final b = session.refreshAfter('a1', refresh);
    gate.complete();
    final results = await Future.wait([a, b]);

    expect(refreshes, 1);
    expect(results.map((t) => t!.accessToken), ['a2', 'a2']);
    expect((await session.read())!.refreshToken, 'r2');
  });

  test('a refusal with a token already replaced takes the new one', () async {
    await session.save(second);
    var refreshes = 0;
    final result = await session.refreshAfter('a1', (_) async {
      refreshes++;
      return null;
    });
    expect(result!.accessToken, 'a2');
    expect(refreshes, 0);
  });

  test('a refused refresh ends the session', () async {
    await session.save(first);
    final ended = expectLater(session.ended, emits(null));
    expect(await session.refreshAfter('a1', (_) async => null), isNull);
    await ended;
    expect(await session.read(), isNull);
  });

  test('a refresh that cannot reach the server keeps the session', () async {
    await session.save(first);
    await expectLater(
      session.refreshAfter(
        'a1',
        (_) async => throw const SocketException('offline'),
      ),
      throwsA(isA<SocketException>()),
    );
    expect((await session.read())!.accessToken, 'a1');

    // The next refusal may try again.
    final again = await session.refreshAfter('a1', (_) async => second);
    expect(again!.accessToken, 'a2');
  });

  test('a refresh that lands after the session ended is not saved', () async {
    await session.save(first);
    final gate = Completer<void>();
    final turn = session.refreshAfter('a1', (_) async {
      await gate.future;
      return second;
    });
    await pumpEventQueue();
    await session.end(); // the user signed out while the exchange was out
    gate.complete();

    expect(await turn, isNull);
    expect(await session.read(), isNull);
  });

  test('a refresh that lands after a new sign-in leaves the new one alone',
      () async {
    const third = SessionTokens(accessToken: 'a3', refreshToken: 'r3');
    await session.save(first);
    final gate = Completer<void>();
    final turn = session.refreshAfter('a1', (_) async {
      await gate.future;
      return null; // even a refusal of the old token must not end the new
    });
    await pumpEventQueue();
    await session.end();
    await session.save(third);
    gate.complete();

    expect(await turn, isNull);
    expect((await session.read())!.accessToken, 'a3');
  });

  test('ending only a session that is still current', () async {
    const third = SessionTokens(accessToken: 'a3', refreshToken: 'r3');
    await session.save(third);
    await session.endIfCurrent('a1');
    expect((await session.read())!.accessToken, 'a3');
    await session.endIfCurrent('a3');
    expect(await session.read(), isNull);
  });

  test('with no session there is nothing to refresh', () async {
    var refreshes = 0;
    final result = await session.refreshAfter('a1', (_) async {
      refreshes++;
      return second;
    });
    expect(result, isNull);
    expect(refreshes, 0);
  });
}
