// ── Test 4: register — PARTIAL registration ───────────────────────────────────
// PARTIAL: email + password only. Returns memberId immediately.
AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
req.registrationType = 'PARTIAL';
req.email            = 'test.partial.' + String.valueOf(DateTime.now().getTime()) + '@mailinator.com';
req.password         = 'Test1234!';

try {
    AscottApiResponse r = AscottApiService.register(req);
    System.debug('=== register PARTIAL ===');
    System.debug('registrationStatus : ' + r.registrationStatus);
    System.debug('autoActivated      : ' + r.autoActivated);
    System.debug('memberId           : ' + r.memberId);   // returned for PARTIAL
} catch (AscottApiException e) {
    System.debug('ERROR [' + e.category + '] code=' + e.errorCode + ' msg=' + e.getMessage());
}
