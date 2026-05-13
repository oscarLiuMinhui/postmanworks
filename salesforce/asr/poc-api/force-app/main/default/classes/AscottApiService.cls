public with sharing class AscottApiService {

    @TestVisible private static final String NC_ASCOTT_API = 'Ascott_API';

    private static final Integer TIMEOUT_MS = 10000;

    // ── Public API ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static AscottApiResponse checkUserExistByEmail(String email) {
        Map<String, Object> payload = AscottPayloadBuilder.checkUserExist(null, email, null);
        return callAscott(AscottCrypto.encryptPayload(payload));
    }

    @AuraEnabled(cacheable=false)
    public static AscottApiResponse checkUserExistByMobile(String mobileNumber) {
        Map<String, Object> payload = AscottPayloadBuilder.checkUserExist(null, null, mobileNumber);
        return callAscott(AscottCrypto.encryptPayload(payload));
    }

    @AuraEnabled(cacheable=false)
    public static AscottApiResponse register(AscottPayloadBuilder.RegisterRequest req) {
        Map<String, Object> payload = AscottPayloadBuilder.register(null, req);
        return callAscott(AscottCrypto.encryptPayload(payload));
    }

    // ── HTTP callout ──────────────────────────────────────────────────────

    // @TestVisible — accepts a pre-built EncryptResult so tests can exercise
    // the HTTP layer independently of crypto (Protected CMT fields are null
    // in test SOQL context, making encryptPayload() untestable end-to-end).
    @TestVisible
    static AscottApiResponse callAscott(AscottCrypto.EncryptResult enc) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:' + NC_ASCOTT_API
            + '/?xs_app=' + EncodingUtil.urlEncode(enc.xsApp, 'UTF-8')
            + '&t=' + enc.encryptedT
        );
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setHeader('X-Correlation-Id', generateCorrelationId());
        req.setTimeout(TIMEOUT_MS);

        try {
            HttpResponse res = new Http().send(req);
            return AscottApiResponse.fromHttpResponse(res);
        } catch (CalloutException e) {
            throw new AscottApiException(
                'Network error calling Ascott: ' + e.getMessage(),
                AscottApiException.ErrorCategory.NETWORK_ERROR
            );
        }
    }

    // ── Distributed tracing ───────────────────────────────────────────────

    @TestVisible
    static String generateCorrelationId() {
        Blob input = Blob.valueOf(UserInfo.getUserId() + String.valueOf(System.currentTimeMillis()));
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', input)).substring(0, 32);
    }
}
