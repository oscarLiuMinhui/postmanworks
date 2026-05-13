// ── Test 6: register — JOINANDBOOK registration ───────────────────────────────
// JOINANDBOOK: registers and auto-activates in one step. Returns memberId.
// Typically used when the customer books a stay during registration.
AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
req.registrationType   = 'JOINANDBOOK';
req.salutation         = 'Ms';
req.firstName          = 'Test';
req.lastName           = 'JoinBook';
req.email              = 'test.joinbook.' + String.valueOf(DateTime.now().getTime()) + '@mailinator.com';
req.password           = 'Test1234!';
req.mobileNumber       = '+65|92234566';
req.countryOfResidence = 'SG';
req.offers             = new List<String>{ 'M' };

try {
    AscottApiResponse r = AscottApiService.register(req);
    System.debug('=== register JOINANDBOOK ===');
    System.debug('registrationStatus : ' + r.registrationStatus);
    System.debug('autoActivated      : ' + r.autoActivated);  // always "Yes" for JOINANDBOOK
    System.debug('memberId           : ' + r.memberId);        // returned for JOINANDBOOK
} catch (AscottApiException e) {
    System.debug('ERROR [' + e.category + '] code=' + e.errorCode + ' msg=' + e.getMessage());
}
