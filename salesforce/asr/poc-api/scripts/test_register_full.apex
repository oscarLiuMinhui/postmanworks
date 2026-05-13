// ── Test 3: register — FULL registration ─────────────────────────────────────
// FULL: new account with all fields. Does NOT return memberId.
// Auto-activates only when referralCode starts with 'GS20'.
AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
req.registrationType   = 'FULL';
req.salutation         = 'Mr';
req.firstName          = 'Oscar';
req.lastName           = 'LIU';
req.email              = 'test.userfull.' + String.valueOf(DateTime.now().getTime()) + '@mailinator.com';
req.password           = 'Test1234!';
Long ts = DateTime.now().getTime();
req.mobileNumber       = '+65|9' + String.valueOf(ts).right(7);
req.countryOfResidence = 'SG';
req.offers             = new List<String>{ 'M' };
// req.referralCode    = 'GS20XXXX';  // uncomment to trigger auto-activation

try {
    AscottApiResponse r = AscottApiService.register(req);
    System.debug('=== register FULL ===');
    System.debug('registrationStatus : ' + r.registrationStatus);
    System.debug('autoActivated      : ' + r.autoActivated);
    System.debug('memberId           : ' + r.memberId);   // null for FULL without referral
} catch (AscottApiException e) {
    System.debug('ERROR [' + e.category + '] code=' + e.errorCode + ' msg=' + e.getMessage());
}
