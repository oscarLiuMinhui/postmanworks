// ── Test 2: checkUserExistByMobile ───────────────────────────────────────────
// Format: +<countryCode>|<number>  e.g. +65|86122031 (Singapore)
String mobile = '+65|92234566';

try {
    AscottApiResponse r = AscottApiService.checkUserExistByMobile(mobile);
    System.debug('=== checkUserExistByMobile: ' + mobile + ' ===');
    System.debug('userExists    : ' + r.userExists);
    System.debug('userActivated : ' + r.userActivated);
    System.debug('memberId      : ' + r.memberIdFound);
    System.debug('tierCode      : ' + r.tierCode);
    System.debug('accountType   : ' + r.accountType);
} catch (AscottApiException e) {
    System.debug('ERROR [' + e.category + '] code=' + e.errorCode + ' msg=' + e.getMessage());
}
