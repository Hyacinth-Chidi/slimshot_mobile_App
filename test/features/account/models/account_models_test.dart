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
}
