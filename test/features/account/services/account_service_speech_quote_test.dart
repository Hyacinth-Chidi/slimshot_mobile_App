import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/services/account_service.dart';

import '../../../support/account_fakes.dart';
import '../../../support/fake_server.dart';

void main() {
  test('a voice is priced by its characters, signed in', () async {
    final server = FakeServer()
      ..on(
        'POST',
        '/credits/quote',
        (_) => envelope({
          'credits': 4,
          'balance': 94,
          'enough': true,
          'pricingVersion': 2,
        }),
      );
    final service = AccountService(
      fakeApi(server, session: signedInSession(access: 'a1', refresh: 'r1')),
    );

    final quote = await service.quoteCharacters(342);

    expect(AccountService.textToSpeechFeature, 'text_to_speech');
    expect(server.lastBody('POST', '/credits/quote'), {
      'feature': 'text_to_speech',
      'characters': 342,
    });
    expect(
      server.to('POST', '/credits/quote').single.headers['Authorization'],
      'Bearer a1',
    );
    expect((quote.credits, quote.balance, quote.enough), (4, 94, true));
  });
}
