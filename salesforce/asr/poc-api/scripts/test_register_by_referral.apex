// ── Test 5: register — BY_REFERRAL registration ──────────────────────────────
// BY_REFERRAL: minimal fields + referralCode. Returns memberId immediately.
// referralCode does NOT need 'GS20' prefix for BY_REFERRAL type.
AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
req.registrationType = 'BY_REFERRAL';
req.email            = 'test.referral.' + String.valueOf(DateTime.now().getTime()) + '@mailinator.com';
req.password         = 'Test1234!';
req.referralCode     = 'TESTREF01';   // replace with a valid referral code from CPRV

try {
    AscottApiResponse r = AscottApiService.register(req);
    System.debug('=== register BY_REFERRAL ===');
    System.debug('registrationStatus : ' + r.registrationStatus);
    System.debug('autoActivated      : ' + r.autoActivated);
    System.debug('memberId           : ' + r.memberId);   // returned for BY_REFERRAL
} catch (AscottApiException e) {
    System.debug('ERROR [' + e.category + '] code=' + e.errorCode + ' msg=' + e.getMessage());
}
