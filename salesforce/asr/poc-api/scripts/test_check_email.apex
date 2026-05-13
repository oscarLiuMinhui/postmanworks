// ── Test 1: checkUserExistByEmail ─────────────────────────────────────────────
// Change the email below to test different scenarios.
String email = 'zaldyantonio@gmail.com';

try {
    AscottApiResponse r = AscottApiService.checkUserExistByEmail(email);
    System.debug('=== checkUserExistByEmail: ' + email + ' ===');
    System.debug('userExists    : ' + r.userExists);
    System.debug('userActivated : ' + r.userActivated);
    System.debug('memberId      : ' + r.memberIdFound);
    System.debug('tierCode      : ' + r.tierCode);
    System.debug('accountType   : ' + r.accountType);
    System.debug('correlationId : ' + r.correlationId);
} catch (AscottApiException e) {
    System.debug('ERROR [' + e.category + '] code=' + e.errorCode + ' msg=' + e.getMessage());
}
