import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/models/account_models.dart';

import '../../../support/fake_server.dart';

void main() {
  test("a profile without today's ads does not read as none left", () {
    // A profile cached by a build before rewarded ads carries no `ads`.
    final user = AccountUser.fromJson(userJson()..remove('ads'));
    expect(user.ads.known, isFalse);
    // Cached again, it stays unknown rather than becoming "0 left".
    expect(user.toJson().containsKey('ads'), isFalse);
    expect(AccountUser.fromJson(userJson()).ads.known, isTrue);
  });

  group('credit claims', () {
    test('claimable now', () {
      final status = CreditClaimStatus.fromJson({
        'enabled': true,
        'credits': 5,
        'intervalDays': 7,
        'nextClaimAt': null,
      });
      expect(status.enabled, isTrue);
      expect(status.credits, 5);
      expect(status.intervalDays, 7);
      expect(status.nextClaimAt, isNull);
    });

    test('claimed already: the time it comes back', () {
      final status = CreditClaimStatus.fromJson({
        'enabled': true,
        'credits': 5,
        'intervalDays': 1,
        'nextClaimAt': '2026-10-31T09:12:44.000Z',
      });
      expect(status.nextClaimAt, DateTime.utc(2026, 10, 31, 9, 12, 44));
    });

    // Anything the app cannot read hides the button rather than offering
    // a claim that may not exist.
    test('an answer without enabled reads as off', () {
      expect(CreditClaimStatus.fromJson({'credits': 5}).enabled, isFalse);
      expect(
        CreditClaimStatus.fromJson({'enabled': true, 'credits': 0}).enabled,
        isFalse,
      );
    });

    test('a claim answers the credits, the balance and the next time', () {
      final result = CreditClaimResult.fromJson({
        'credits': 5,
        'balance': 115,
        'nextClaimAt': '2026-10-31T09:12:44.000Z',
      });
      expect(result.credits, 5);
      expect(result.balance, 115);
      expect(result.nextClaimAt, DateTime.utc(2026, 10, 31, 9, 12, 44));
    });
  });
}
