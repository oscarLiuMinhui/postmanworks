@IsTest
private class AscottApiResponseTest {

    // ── Helpers ─────────────────────────────────────────────────────────

    private static HttpResponse makeResponse(Integer status, String body) {
        return makeResponse(status, body, 'test-correlation-id');
    }

    private static HttpResponse makeResponse(Integer status, String body, String correlationId) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(status);
        res.setBody(body);
        if (correlationId != null) {
            res.setHeader('X-Correlation-Id', correlationId);
        }
        return res;
    }

    // ── Register — success responses (spec p.4) ──────────────────────────

    @IsTest
    static void fromHttpResponse_200_registerFull_noMemberId() {
        // FULL registration returns success + auto-activated flag only
        HttpResponse res = makeResponse(200, '{"status":"success","auto-activated":"No"}');
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.success, 'success should be true');
        System.assertEquals(200, result.httpStatus);
        System.assertEquals('success', result.registrationStatus);
        System.assertEquals('No', result.autoActivated);
        System.assert(result.memberId == null, 'FULL registration should not return memberId');
        System.assertEquals('test-correlation-id', result.correlationId);
    }

    @IsTest
    static void fromHttpResponse_200_registerFull_gs20Referral_autoActivated() {
        // Full + GS20 prefix referral code → auto-activated = Yes (server-set)
        HttpResponse res = makeResponse(200, '{"status":"success","auto-activated":"Yes"}');
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.success);
        System.assertEquals('Yes', result.autoActivated);
        System.assert(result.memberId == null);
    }

    @IsTest
    static void fromHttpResponse_200_registerPartial_returnsMemberId() {
        // PARTIAL / BY_REFERRAL / JOINANDBOOK return memberId (spec p.4)
        HttpResponse res = makeResponse(200,
            '{"status":"success","memberId":"1234567890","auto-activated":"No"}'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.success);
        System.assertEquals('1234567890', result.memberId);
        System.assertEquals('No', result.autoActivated);
    }

    @IsTest
    static void fromHttpResponse_200_registerJoinAndBook_autoActivatedYes() {
        // JOINANDBOOK always auto-activates (spec p.4)
        HttpResponse res = makeResponse(200,
            '{"status":"success","memberId":"9876543210","auto-activated":"Yes"}'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.success);
        System.assertEquals('Yes', result.autoActivated);
        System.assertEquals('9876543210', result.memberId);
    }

    // ── checkUserExist — success responses (spec p.6) ───────────────────

    @IsTest
    static void fromHttpResponse_200_checkUserExist_userFoundAndActivated() {
        HttpResponse res = makeResponse(200,
            '{"exist":"true","activated":"true","memberId":"12345678","tierCode":"1","accountType":"member"}'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.success);
        System.assert(result.userExists, 'userExists should be true');
        System.assert(result.userActivated, 'userActivated should be true');
        System.assertEquals('12345678', result.memberIdFound);
        System.assertEquals('1', result.tierCode);
        System.assertEquals('member', result.accountType);
    }

    @IsTest
    static void fromHttpResponse_200_checkUserExist_representative() {
        HttpResponse res = makeResponse(200,
            '{"exist":"true","activated":"true","memberId":"99001","tierCode":"2","accountType":"representative"}'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.userExists);
        System.assertEquals('representative', result.accountType);
        System.assertEquals('2', result.tierCode);
    }

    @IsTest
    static void fromHttpResponse_200_checkUserExist_userNotFound() {
        HttpResponse res = makeResponse(200,
            '{"exist":"false","activated":"false","memberId":null,"tierCode":null,"accountType":null}'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.success, 'API call succeeded even though user does not exist');
        System.assert(!result.userExists, 'userExists should be false');
        System.assert(!result.userActivated, 'userActivated should be false');
    }

    @IsTest
    static void fromHttpResponse_200_checkUserExist_existsButNotActivated() {
        HttpResponse res = makeResponse(200,
            '{"exist":"true","activated":"false","memberId":"55555","tierCode":"1","accountType":"member"}'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);

        System.assert(result.userExists);
        System.assert(!result.userActivated, 'userActivated should be false');
        System.assertEquals('55555', result.memberIdFound);
    }

    @IsTest
    static void fromHttpResponse_200_correlationIdEchoedFromHeader() {
        HttpResponse res = makeResponse(200,
            '{"exist":"true","activated":"true","memberId":"1","tierCode":"1","accountType":"member"}',
            'X-CORR-ABC-123'
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);
        System.assertEquals('X-CORR-ABC-123', result.correlationId);
    }

    @IsTest
    static void fromHttpResponse_200_noCorrelationHeader_isNull() {
        HttpResponse res = makeResponse(200,
            '{"exist":"true","activated":"true","memberId":"1","tierCode":"1","accountType":"member"}',
            null
        );
        AscottApiResponse result = AscottApiResponse.fromHttpResponse(res);
        System.assert(result.correlationId == null);
    }

    // ── Error responses ──────────────────────────────────────────────────

    @IsTest
    static void fromHttpResponse_400_emailRequired_throwsValidationError() {
        HttpResponse res = makeResponse(400,
            '{"errorCode":"1005","message":["Email is required.", "Invalid email."]}'
        );
        AscottApiException caught;
        try {
            AscottApiResponse.fromHttpResponse(res);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null, 'Expected AscottApiException');
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assertEquals('1005', caught.errorCode);
        System.assertEquals(400, caught.httpStatus);
    }

    @IsTest
    static void fromHttpResponse_400_referralCodeInvalid_throwsCode1006() {
        HttpResponse res = makeResponse(400,
            '{"errorCode":"1006","message":["Referral Code consists of invalid character(s)"]}'
        );
        AscottApiException caught;
        try {
            AscottApiResponse.fromHttpResponse(res);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals('1006', caught.errorCode);
    }

    @IsTest
    static void fromHttpResponse_400_mobileRequired_throwsCode1003() {
        HttpResponse res = makeResponse(400,
            '{"errorCode":"1003","message":"Email or mobile number is required"}'
        );
        AscottApiException caught;
        try {
            AscottApiResponse.fromHttpResponse(res);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals('1003', caught.errorCode);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void fromHttpResponse_401_invalidToken_throwsAuthFailure() {
        HttpResponse res = makeResponse(401,
            '{"errorCode":"1502","message":"Token is invalid."}'
        );
        AscottApiException caught;
        try {
            AscottApiResponse.fromHttpResponse(res);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.AUTH_FAILURE, caught.category);
        System.assertEquals('1502', caught.errorCode);
    }

    @IsTest
    static void fromHttpResponse_500_serverError_throwsCode1800() {
        HttpResponse res = makeResponse(500,
            '{"errorCode":"1800","message":"Something went wrong. Please try again."}'
        );
        AscottApiException caught;
        try {
            AscottApiResponse.fromHttpResponse(res);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.SERVER_ERROR, caught.category);
        System.assertEquals('1800', caught.errorCode);
    }

    @IsTest
    static void fromHttpResponse_200_malformedJson_throwsUnknown() {
        HttpResponse res = makeResponse(200, 'not-valid-json-body');
        AscottApiException caught;
        try {
            AscottApiResponse.fromHttpResponse(res);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null, 'Expected AscottApiException for unparseable body');
        System.assertEquals(AscottApiException.ErrorCategory.UNKNOWN, caught.category);
    }
}
