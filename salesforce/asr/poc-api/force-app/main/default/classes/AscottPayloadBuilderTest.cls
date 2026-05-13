@IsTest
private class AscottPayloadBuilderTest {

    // ── checkUserExist ───────────────────────────────────────────────────

    @IsTest
    static void checkUserExist_byEmail_setsActionAndEmail() {
        Map<String, Object> p = AscottPayloadBuilder.checkUserExist(null, 'user@example.com', null);

        System.assertEquals('checkUserExist', p.get('action'));
        System.assertEquals('user@example.com', p.get('email'));
        System.assert(!p.containsKey('mobileNumber'), 'mobileNumber should be absent');
        System.assert(!p.containsKey('sysToken'), 'sysToken should be absent when null');
    }

    @IsTest
    static void checkUserExist_byMobile_setsActionAndMobile() {
        Map<String, Object> p = AscottPayloadBuilder.checkUserExist(null, null, '+65|86122031');

        System.assertEquals('checkUserExist', p.get('action'));
        System.assertEquals('+65|86122031', p.get('mobileNumber'));
        System.assert(!p.containsKey('email'), 'email should be absent');
    }

    @IsTest
    static void checkUserExist_withSysToken_includesToken() {
        Map<String, Object> p = AscottPayloadBuilder.checkUserExist('myToken', 'user@example.com', null);
        System.assertEquals('myToken', p.get('sysToken'));
    }

    @IsTest
    static void checkUserExist_bothBlank_throwsValidationError() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.checkUserExist(null, null, null);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void checkUserExist_whitespaceOnly_throwsValidationError() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.checkUserExist(null, '   ', '   ');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    // ── validateEmail ────────────────────────────────────────────────────

    @IsTest
    static void validateEmail_standardAddress_returnsAsIs() {
        System.assertEquals('user@example.com', AscottPayloadBuilder.validateEmail('user@example.com'));
    }

    @IsTest
    static void validateEmail_withSubdomainAndSpecialChars_valid() {
        String email = 'user.name+tag@sub.example.co';
        System.assertEquals(email, AscottPayloadBuilder.validateEmail(email));
    }

    @IsTest
    static void validateEmail_nullInput_returnsNull() {
        System.assert(AscottPayloadBuilder.validateEmail(null) == null);
    }

    @IsTest
    static void validateEmail_emptyString_returnsEmpty() {
        System.assertEquals('', AscottPayloadBuilder.validateEmail(''));
    }

    @IsTest
    static void validateEmail_localPartExactly64Chars_valid() {
        String local = 'a'.repeat(64);
        String email = local + '@example.com';
        System.assertEquals(email, AscottPayloadBuilder.validateEmail(email));
    }

    @IsTest
    static void validateEmail_localPartExceeds64Chars_throws() {
        String email = 'a'.repeat(65) + '@example.com';
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateEmail(email);
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assert(caught.getMessage().contains('64'), 'Error should mention 64 char limit');
    }

    @IsTest
    static void validateEmail_noAtSign_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateEmail('invalidemail.com');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void validateEmail_noTLD_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateEmail('user@nodot');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void validateEmail_missingDomain_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateEmail('user@');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    // ── validatePassword ─────────────────────────────────────────────────

    @IsTest
    static void validatePassword_validMinLength_returns() {
        System.assertEquals('Secret1!', AscottPayloadBuilder.validatePassword('Secret1!'));
    }

    @IsTest
    static void validatePassword_validMaxLength_returns() {
        String pw = 'Secret123456!@#$'; // 16 chars
        System.assertEquals(pw, AscottPayloadBuilder.validatePassword(pw));
    }

    @IsTest
    static void validatePassword_tooShort_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('Ab1!');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assert(caught.getMessage().contains('8'), 'Error should mention 8 char minimum');
    }

    @IsTest
    static void validatePassword_tooLong_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('Abcdefg1234567890'); // 17 chars
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assert(caught.getMessage().contains('16'), 'Error should mention 16 char maximum');
    }

    @IsTest
    static void validatePassword_noUppercase_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('secret1!abcd');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assert(caught.getMessage().containsIgnoreCase('uppercase'));
    }

    @IsTest
    static void validatePassword_noLowercase_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('SECRET1!ABCD');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assert(caught.getMessage().containsIgnoreCase('lowercase'));
    }

    @IsTest
    static void validatePassword_noDigit_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('SecretPass!');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assert(caught.getMessage().containsIgnoreCase('digit'));
    }

    @IsTest
    static void validatePassword_invalidCharSpace_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('Secret1 !'); // space is not allowed
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void validatePassword_invalidCharPipe_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validatePassword('Secret1!|ab');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    // ── validateReferralCode ─────────────────────────────────────────────

    @IsTest
    static void validateReferralCode_alphanumeric_valid() {
        System.assertEquals('GS20ABCDEF', AscottPayloadBuilder.validateReferralCode('GS20ABCDEF'));
    }

    @IsTest
    static void validateReferralCode_allAllowedSymbols_valid() {
        String code = 'REF!@#$%^*()_+.-';
        System.assertEquals(code, AscottPayloadBuilder.validateReferralCode(code));
    }

    @IsTest
    static void validateReferralCode_exactly100Chars_valid() {
        String code = 'A'.repeat(100);
        System.assertEquals(code, AscottPayloadBuilder.validateReferralCode(code));
    }

    @IsTest
    static void validateReferralCode_exceeds100Chars_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateReferralCode('A'.repeat(101));
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assert(caught.getMessage().contains('100'));
    }

    @IsTest
    static void validateReferralCode_containsSpace_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateReferralCode('REF CODE');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void validateReferralCode_containsBackslash_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateReferralCode('REF\\CODE');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    // ── validateMobileNumber ─────────────────────────────────────────────

    @IsTest
    static void validateMobileNumber_sgFormat_valid() {
        System.assertEquals('+65|86122031', AscottPayloadBuilder.validateMobileNumber('+65|86122031'));
    }

    @IsTest
    static void validateMobileNumber_cnFormat_valid() {
        System.assertEquals('+86|13800138000', AscottPayloadBuilder.validateMobileNumber('+86|13800138000'));
    }

    @IsTest
    static void validateMobileNumber_missingPlus_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateMobileNumber('65|86122031');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void validateMobileNumber_missingPipe_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateMobileNumber('+6586122031');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void validateMobileNumber_nonNumericAfterPipe_throws() {
        AscottApiException caught;
        try {
            AscottPayloadBuilder.validateMobileNumber('+65|8612ABC');
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    // ── RegisterRequest.validate() ───────────────────────────────────────

    @IsTest
    static void register_missingRegistrationType_throws() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        AscottApiException caught;
        try {
            req.validate();
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
        System.assert(caught.getMessage().containsIgnoreCase('registrationType'));
    }

    @IsTest
    static void register_invalidRegistrationType_throws() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'UNKNOWN_TYPE';
        AscottApiException caught;
        try {
            req.validate();
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void register_allValidRegistrationTypes_noThrow() {
        for (String rType : new List<String>{ 'FULL', 'PARTIAL', 'BY_REFERRAL', 'JOINANDBOOK' }) {
            AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
            req.registrationType = rType;
            req.validate();
            System.assert(true, 'No exception for registration type: ' + rType);
        }
    }

    @IsTest
    static void register_registrationTypeCaseInsensitive_normalizedToUpper() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'full'; // lowercase
        Map<String, Object> p = AscottPayloadBuilder.register(null, req);
        System.assertEquals('FULL', p.get('registrationType'), 'registrationType must be uppercased');
    }

    @IsTest
    static void register_invalidSalutation_throws() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.salutation = 'Sir'; // not in allowed list
        AscottApiException caught;
        try {
            req.validate();
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assert(caught.getMessage().containsIgnoreCase('salutation'));
    }

    @IsTest
    static void register_allValidSalutations_noThrow() {
        for (String sal : new List<String>{ 'Dr', 'Mr', 'Mrs', 'Ms', 'Mx' }) {
            AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
            req.registrationType = 'FULL';
            req.salutation = sal;
            req.validate();
            System.assert(true, 'No exception for salutation: ' + sal);
        }
    }

    @IsTest
    static void register_invalidGender_throws() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.gender = 'X';
        AscottApiException caught;
        try {
            req.validate();
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assert(caught.getMessage().contains('"M" or "F"'));
    }

    @IsTest
    static void register_validGenders_M_and_F_noThrow() {
        for (String g : new List<String>{ 'M', 'F' }) {
            AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
            req.registrationType = 'FULL';
            req.gender = g;
            req.validate();
            System.assert(true, 'No exception for gender: ' + g);
        }
    }

    @IsTest
    static void register_invalidEuResident_throws() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.euResident = 'maybe';
        AscottApiException caught;
        try {
            req.validate();
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.VALIDATION_ERROR, caught.category);
    }

    @IsTest
    static void register_euResidentNormalizedToLowercase() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.euResident = 'Yes'; // mixed case
        Map<String, Object> p = AscottPayloadBuilder.register(null, req);
        System.assertEquals('yes', p.get('euResident'), 'euResident must be lowercased');
    }

    @IsTest
    static void register_invalidOfferCode_throws() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.offers = new List<String>{ 'M', 'X' }; // X is invalid
        AscottApiException caught;
        try {
            req.validate();
        } catch (AscottApiException e) {
            caught = e;
        }
        System.assert(caught != null);
        System.assert(caught.getMessage().contains('X'), 'Error message should identify the bad offer code');
    }

    @IsTest
    static void register_validOffersBothMC_noThrow() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'FULL';
        req.offers = new List<String>{ 'M', 'C' };
        req.validate();
        System.assert(true);
    }

    // ── register() payload construction ──────────────────────────────────

    @IsTest
    static void register_fullPayload_allFieldsMapped() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType    = 'FULL';
        req.salutation          = 'Mr';
        req.firstName           = 'John';
        req.lastName            = 'Doe';
        req.displayName         = 'Johnny';
        req.email               = 'john.doe@example.com';
        req.mobileNumber        = '+65|91234567';
        req.contactNumber       = '+65|63001234';
        req.gender              = 'M';
        req.dob                 = '1990-01-15T00:00:00Z';
        req.password            = 'Secret1!ab';
        req.companyName         = 'Acme Corp';
        req.companyEmail        = 'corp@acme.com';
        req.countryOfResidence  = 'SG';
        req.offers              = new List<String>{ 'M', 'C' };
        req.referralCode        = 'GS20SPECIAL';
        req.euResident          = 'no';
        req.geoLocation         = 'SG';

        Map<String, Object> p = AscottPayloadBuilder.register('tok123', req);

        System.assertEquals('register',              p.get('action'));
        System.assertEquals('FULL',                  p.get('registrationType'));
        System.assertEquals('tok123',                p.get('sysToken'));
        System.assertEquals('Mr',                    p.get('salutation'));
        System.assertEquals('John',                  p.get('firstName'));
        System.assertEquals('Doe',                   p.get('lastName'));
        System.assertEquals('Johnny',                p.get('displayName'));
        System.assertEquals('john.doe@example.com',  p.get('email'));
        System.assertEquals('+65|91234567',          p.get('mobileNumber'));
        System.assertEquals('+65|63001234',          p.get('contactNumber'));
        System.assertEquals('M',                     p.get('gender'));
        System.assertEquals('1990-01-15T00:00:00Z',  p.get('dob'));
        System.assertEquals('Secret1!ab',            p.get('password'));
        System.assertEquals('Acme Corp',             p.get('companyName'));
        // Spec key is 'companyEmailAddress', not 'companyEmail'
        System.assertEquals('corp@acme.com',         p.get('companyEmailAddress'));
        System.assert(!p.containsKey('companyEmail'), 'Raw field name must not appear in payload');
        System.assertEquals('SG',                    p.get('countryOfResidence'));
        System.assertEquals('GS20SPECIAL',           p.get('referralCode'));
        System.assertEquals('no',                    p.get('euResident'));
        System.assertEquals('SG',                    p.get('geoLocation'));
    }

    @IsTest
    static void register_optionalFieldsOmitted_notInPayload() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'JOINANDBOOK';
        Map<String, Object> p = AscottPayloadBuilder.register(null, req);

        System.assertEquals('register',    p.get('action'));
        System.assertEquals('JOINANDBOOK', p.get('registrationType'));
        System.assert(!p.containsKey('sysToken'),           'sysToken absent when null');
        System.assert(!p.containsKey('salutation'),          'salutation absent when null');
        System.assert(!p.containsKey('firstName'),           'firstName absent when null');
        System.assert(!p.containsKey('email'),               'email absent when null');
        System.assert(!p.containsKey('offers'),              'offers absent when null');
        System.assert(!p.containsKey('referralCode'),        'referralCode absent when null');
        System.assert(!p.containsKey('companyEmailAddress'), 'companyEmailAddress absent when null');
    }

    @IsTest
    static void register_partialType_allRequiredFieldsIncluded() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType    = 'PARTIAL';
        req.firstName           = 'Jane';
        req.lastName            = 'Smith';
        req.password            = 'Pass1234!';
        req.mobileNumber        = '+44|7700900123';
        req.email               = 'jane@example.com';
        req.salutation          = 'Ms';
        req.countryOfResidence  = 'GB';
        req.offers              = new List<String>{ 'M', 'C' };

        Map<String, Object> p = AscottPayloadBuilder.register(null, req);
        System.assertEquals('PARTIAL', p.get('registrationType'));
        System.assertEquals('Jane',    p.get('firstName'));
        System.assertEquals('Smith',   p.get('lastName'));
    }

    @IsTest
    static void register_byReferral_withGS20Code_noValidationError() {
        AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
        req.registrationType = 'BY_REFERRAL';
        req.referralCode = 'GS20XYZABC';
        Map<String, Object> p = AscottPayloadBuilder.register(null, req);
        System.assertEquals('GS20XYZABC', p.get('referralCode'));
    }
}
