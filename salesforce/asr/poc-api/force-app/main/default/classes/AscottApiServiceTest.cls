@IsTest
private class AscottApiServiceTest {

    // ══════════════════════════════════════════════════════════════════════
    // Mock infrastructure
    // ══════════════════════════════════════════════════════════════════════

    private class StaticMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String  body;
        private final String  correlationId;

        StaticMock(Integer statusCode, String body) {
            this(statusCode, body, null);
        }

        StaticMock(Integer statusCode, String body, String correlationId) {
            this.statusCode    = statusCode;
            this.body          = body;
            this.correlationId = correlationId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            if (correlationId != null) {
                res.setHeader('X-Correlation-Id', correlationId);
            }
            return res;
        }
    }

    private class CapturingMock implements HttpCalloutMock {
        public HttpRequest lastRequest;
        private final StaticMock delegate;

        CapturingMock(Integer statusCode, String body) {
            this.delegate = new StaticMock(statusCode, body, 'captured-corr-id');
        }

        public HttpResponse respond(HttpRequest req) {
            lastRequest = req;
            return delegate.respond(req);
        }
    }

    private class NetworkErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network error');
        }
    }

    // ── Dummy EncryptResult used by all HTTP-layer tests ──────────────────
    private static AscottCrypto.EncryptResult dummyEnc() {
        return new AscottCrypto.EncryptResult('DUMMY_T_PARAM', 'asr_api_v2_1');
    }

    // ══════════════════════════════════════════════════════════════════════
    // generateCorrelationId
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void generateCorrelationId_produces32HexChars() {
        String id = AscottApiService.generateCorrelationId();
        System.assertEquals(32, id.length(), 'Correlation ID must be 32 chars');
        System.assert(
            Pattern.compile('^[0-9a-f]{32}$').matcher(id).matches(),
            'Correlation ID must be lowercase hex: ' + id
        );
    }

    @IsTest
    static void generateCorrelationId_calledTwice_sameFormat() {
        String id1 = AscottApiService.generateCorrelationId();
        String id2 = AscottApiService.generateCorrelationId();
        System.assertEquals(32, id1.length());
        System.assertEquals(32, id2.length());
    }

    // ══════════════════════════════════════════════════════════════════════
    // callAscott — outbound request structure
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void callAscott_requestIsGet_withQueryParams() {
        CapturingMock mock = new CapturingMock(200,
            '{"exist":"true","activated":"true","memberId":"1","tierCode":"1","accountType":"member"}'
        );
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assert(mock.lastRequest != null);
        System.assertEquals('GET', mock.lastRequest.getMethod());
        System.assert(mock.lastRequest.getEndpoint().contains('xs_app='), 'Endpoint must contain xs_app param');
        System.assert(mock.lastRequest.getEndpoint().contains('&t='),     'Endpoint must contain t param');
        System.assertEquals('',   mock.lastRequest.getBody(), 'GET must have no body');
        System.assertEquals('application/json', mock.lastRequest.getHeader('Accept'));
        System.assert(mock.lastRequest.getHeader('X-Correlation-Id') != null, 'Correlation header must be set');
        System.assertEquals(32, mock.lastRequest.getHeader('X-Correlation-Id').length());
    }

    // ══════════════════════════════════════════════════════════════════════
    // callAscott — checkUserExist responses
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void checkUserExistByEmail_userFoundAndActivated_member() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"exist":"true","activated":"true","memberId":"12345678","tierCode":"1","accountType":"member"}',
            'corr-001'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assert(r.success);
        System.assert(r.userExists);
        System.assert(r.userActivated);
        System.assertEquals('12345678', r.memberIdFound);
        System.assertEquals('1',        r.tierCode);
        System.assertEquals('member',   r.accountType);
        System.assertEquals('corr-001', r.correlationId);
    }

    @IsTest
    static void checkUserExistByEmail_userFoundAndActivated_representative() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"exist":"true","activated":"true","memberId":"99001","tierCode":"2","accountType":"representative"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assertEquals('representative', r.accountType);
        System.assertEquals('2', r.tierCode);
    }

    @IsTest
    static void checkUserExistByEmail_existsButNotActivated() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"exist":"true","activated":"false","memberId":"55555","tierCode":"1","accountType":"member"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assert(r.userExists);
        System.assert(!r.userActivated);
    }

    @IsTest
    static void checkUserExistByEmail_userNotFound() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"exist":"false","activated":"false","memberId":null,"tierCode":null,"accountType":null}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assert(!r.userExists);
        System.assert(!r.userActivated);
    }

    // ══════════════════════════════════════════════════════════════════════
    // callAscott — register responses
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void register_full_success_noMemberId_notAutoActivated() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"status":"success","auto-activated":"No"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assert(r.success);
        System.assertEquals('success', r.registrationStatus);
        System.assertEquals('No', r.autoActivated);
        System.assert(r.memberId == null);
    }

    @IsTest
    static void register_full_gs20ReferralCode_autoActivated() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"status":"success","auto-activated":"Yes"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assertEquals('Yes', r.autoActivated);
        System.assert(r.memberId == null);
    }

    @IsTest
    static void register_partial_returnsMemberId() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"status":"success","memberId":"9876543210","auto-activated":"No"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assertEquals('9876543210', r.memberId);
        System.assertEquals('No', r.autoActivated);
    }

    @IsTest
    static void register_byReferral_returnsMemberId() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"status":"success","memberId":"1111111111","auto-activated":"No"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assertEquals('1111111111', r.memberId);
    }

    @IsTest
    static void register_joinAndBook_autoActivatedAndReturnsMemberId() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(200,
            '{"status":"success","memberId":"2222222222","auto-activated":"Yes"}'
        ));
        Test.startTest();
        AscottApiResponse r = AscottApiService.callAscott(dummyEnc());
        Test.stopTest();

        System.assertEquals('Yes', r.autoActivated);
        System.assertEquals('2222222222', r.memberId);
    }

    // ══════════════════════════════════════════════════════════════════════
    // callAscott — HTTP error responses
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void callAscott_400_throwsValidationError() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(400,
            '{"errorCode":"1005","message":["Email is required."]}'
        ));
        AscottApiException caught;
        Test.startTest();
        try {
            AscottApiService.callAscott(dummyEnc());
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assertEquals('1005', caught.errorCode);
    }

    @IsTest
    static void callAscott_401_throwsAuthFailure() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(401,
            '{"errorCode":"1502","message":"Token is invalid."}'
        ));
        AscottApiException caught;
        Test.startTest();
        try {
            AscottApiService.callAscott(dummyEnc());
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.AUTH_FAILURE, caught.category);
        System.assertEquals('1502', caught.errorCode);
    }

    @IsTest
    static void callAscott_500_throwsServerError() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(500,
            '{"errorCode":"1800","message":"Something went wrong. Please try again."}'
        ));
        AscottApiException caught;
        Test.startTest();
        try {
            AscottApiService.callAscott(dummyEnc());
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.SERVER_ERROR, caught.category);
        System.assertEquals('1800', caught.errorCode);
    }

    @IsTest
    static void callAscott_400_referralCodeInvalid_throwsCode1006() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(400,
            '{"errorCode":"1006","message":["Referral Code consists of invalid character(s)"]}'
        ));
        AscottApiException caught;
        Test.startTest();
        try {
            AscottApiService.callAscott(dummyEnc());
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals('1006', caught.errorCode);
    }

    @IsTest
    static void callAscott_networkError_throwsNetworkError() {
        Test.setMock(HttpCalloutMock.class, new NetworkErrorMock());
        AscottApiException caught;
        Test.startTest();
        try {
            AscottApiService.callAscott(dummyEnc());
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.NETWORK_ERROR, caught.category);
        System.assert(caught.getMessage().containsIgnoreCase('network error'));
    }

    // ══════════════════════════════════════════════════════════════════════
    // Crypto failure (no CMT record in test context → CRYPTO_ERROR before callout)
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void callAscott_cryptoFailure_throwsCryptoError() {
        // No Ascott_Credential__mdt record in test context → encryptPayload() throws
        // CRYPTO_ERROR before any HTTP callout. No HttpCalloutMock needed.
        AscottApiException caught;
        Test.startTest();
        try {
            AscottApiService.checkUserExistByEmail('valid@example.com');
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.CRYPTO_ERROR, caught.category);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Input validation — throws inside AscottPayloadBuilder before crypto
    // ══════════════════════════════════════════════════════════════════════

    @IsTest
    static void checkUserExistByEmail_invalidEmailFormat_throwsValidationError() {
        AscottApiException caught;
        try {
            AscottApiService.checkUserExistByEmail('not-an-email');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void checkUserExistByMobile_invalidFormat_throwsValidationError() {
        AscottApiException caught;
        try {
            AscottApiService.checkUserExistByMobile('6586122031');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void register_invalidPassword_throwsBeforeCallout() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.password = 'weak';
        AscottApiException caught;
        try {
            AscottApiService.register(req);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void register_invalidSalutation_throwsBeforeCallout() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.salutation = 'Lord';
        AscottApiException caught;
        try {
            AscottApiService.register(req);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Helper
    // ══════════════════════════════════════════════════════════════════════

    private static AscottPayloadBuilder.RegisterRequest buildPartialRequest(String regType) {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType   = regType;
        req.firstName          = 'Test';
        req.lastName           = 'User';
        req.email              = 'testuser@example.com';
        req.password           = 'Test1234!';
        req.mobileNumber       = '+65|91234567';
        req.salutation         = 'Mr';
        req.countryOfResidence = 'SG';
        req.offers             = new List<String>{ 'M', 'C' };
        return req;
    }
}
