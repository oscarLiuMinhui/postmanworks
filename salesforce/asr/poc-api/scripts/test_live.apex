// Live integration test — requires Named Credential 'Ascott_API' and CMT record 'UAT' to be configured.
// Uses the same email as the verified example URL.
try {
    AscottApiResponse r = AscottApiService.checkUserExistByEmail('zaldyantonio@gmail.com');
    System.debug('success       : ' + r.success);
    System.debug('userExists    : ' + r.userExists);
    System.debug('userActivated : ' + r.userActivated);
    System.debug('memberId      : ' + r.memberIdFound);
    System.debug('tierCode      : ' + r.tierCode);
    System.debug('accountType   : ' + r.accountType);
    System.debug('correlationId : ' + r.correlationId);
} catch (AscottApiException e) {
    System.debug('ERROR category : ' + e.category);
    System.debug('ERROR code     : ' + e.errorCode);
    System.debug('ERROR message  : ' + e.getMessage());
}
