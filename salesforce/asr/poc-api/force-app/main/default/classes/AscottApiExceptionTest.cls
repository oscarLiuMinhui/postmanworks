@IsTest
private class AscottApiExceptionTest {

    @IsTest
    static void constructor_twoArgs_setsCategoryAndMessage() {
        AscottApiException ex = new AscottApiException(
            'Network timeout',
            AscottApiException.ErrorCategory.NETWORK_ERROR
        );
        System.assertEquals('Network timeout', ex.getMessage(), 'Message mismatch');
        System.assertEquals(AscottApiException.ErrorCategory.NETWORK_ERROR, ex.category);
        System.assert(ex.errorCode == null, 'errorCode should be null');
        System.assert(ex.httpStatus == null, 'httpStatus should be null');
    }

    @IsTest
    static void constructor_fourArgs_setsAllFields() {
        AscottApiException ex = new AscottApiException(
            'Token invalid',
            AscottApiException.ErrorCategory.AUTH_FAILURE,
            '1502',
            401
        );
        System.assertEquals(AscottApiException.ErrorCategory.AUTH_FAILURE, ex.category);
        System.assertEquals('1502', ex.errorCode);
        System.assertEquals(401, ex.httpStatus);
    }

    @IsTest
    static void fromResponse_401_returnsAuthFailure() {
        AscottApiException ex = AscottApiException.fromResponse(
            401,
            '{"errorCode":"1502","message":"Token is invalid."}'
        );
        System.assertEquals(AscottApiException.ErrorCategory.AUTH_FAILURE, ex.category);
        System.assertEquals('1502', ex.errorCode);
        System.assertEquals(401, ex.httpStatus);
        System.assert(ex.getMessage().contains('Token is invalid.'), 'Message should contain API error text');
    }

    @IsTest
    static void fromResponse_400_validationError_code1005() {
        AscottApiException ex = AscottApiException.fromResponse(
            400,
            '{"errorCode":"1005","message":["Email is required.", "Invalid email."]}'
        );
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, ex.category);
        System.assertEquals('1005', ex.errorCode);
        System.assertEquals(400, ex.httpStatus);
    }

    @IsTest
    static void fromResponse_400_validationError_code1006_referralCode() {
        AscottApiException ex = AscottApiException.fromResponse(
            400,
            '{"errorCode":"1006","message":["Referral Code consists of invalid character(s) or exceeded max char"]}'
        );
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, ex.category);
        System.assertEquals('1006', ex.errorCode);
    }

    @IsTest
    static void fromResponse_500_returnsServerError() {
        AscottApiException ex = AscottApiException.fromResponse(
            500,
            '{"errorCode":"1800","message":"Something went wrong. Please try again."}'
        );
        System.assertEquals(AscottApiException.ErrorCategory.SERVER_ERROR, ex.category);
        System.assertEquals('1800', ex.errorCode);
        System.assertEquals(500, ex.httpStatus);
        System.assert(ex.getMessage().contains('Something went wrong'), 'Message should reflect API text');
    }

    @IsTest
    static void fromResponse_unparsableBody_defaultsToUnknown() {
        AscottApiException ex = AscottApiException.fromResponse(503, 'not-valid-json');
        System.assertEquals(AscottApiException.ErrorCategory.UNKNOWN, ex.category);
        System.assertEquals('UNKNOWN', ex.errorCode);
        System.assertEquals(503, ex.httpStatus);
    }

    @IsTest
    static void fromResponse_emptyJsonBody_usesDefaultMessage() {
        AscottApiException ex = AscottApiException.fromResponse(500, '{}');
        System.assertEquals(AscottApiException.ErrorCategory.SERVER_ERROR, ex.category);
        System.assert(ex.getMessage().contains('HTTP 500'), 'Default message should include HTTP status');
    }

    @IsTest
    static void fromResponse_emptyBody_doesNotThrow() {
        AscottApiException ex = AscottApiException.fromResponse(400, '');
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, ex.category);
        System.assert(ex.getMessage() != null, 'Message should not be null');
    }

    @IsTest
    static void errorCategory_allValuesExist() {
        // Smoke-test enum completeness — guards against accidental removal
        Set<String> expectedCategories = new Set<String>{
            'AUTH_FAILURE', 'VALIDATION_ERROR', 'SERVER_ERROR',
            'NETWORK_ERROR', 'CRYPTO_ERROR', 'UNKNOWN'
        };
        for (AscottApiException.ErrorCategory cat : AscottApiException.ErrorCategory.values()) {
            System.assert(
                expectedCategories.contains(cat.name()),
                'Unexpected category: ' + cat.name()
            );
        }
    }
}
