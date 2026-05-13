@IsTest
private class AscottCryptoTest {

    // ── Test credential ───────────────────────────────────────────────────

    private static Ascott_Credential__mdt testCred() {
        Ascott_Credential__mdt c = new Ascott_Credential__mdt();
        c.Iv__c             = 'PcGK5n4y72XL';
        c.Salt__c           = 'sG3YrEDKPaj2nUXF';
        c.Xs_App__c         = 'asr_api_v2_1';
        c.Sys_Token__c      = 'test-sys-token';
        // Random but cryptographically valid 256-bit key — no pre-computed value needed.
        // Tests verify structure and behaviour, not specific ciphertext bytes.
        c.Aes_Key_Base64__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        return c;
    }

    private static Map<String, Object> checkUserExistPayload() {
        return new Map<String, Object>{
            'action' => 'checkUserExist',
            'email'  => 'test@example.com'
        };
    }

    // ── Output format ─────────────────────────────────────────────────────

    @IsTest
    static void encrypt_outputIsValidBase64UrlEncoded() {
        AscottCrypto.EncryptResult r = AscottCrypto.encryptWithCredential(
            checkUserExistPayload(), testCred()
        );
        String b64 = EncodingUtil.urlDecode(r.encryptedT, 'UTF-8');
        // Throws if not valid Base64 — that is the assertion.
        Blob decoded = EncodingUtil.base64Decode(b64);
        System.assert(decoded.size() > 0, 'Decoded output must be non-empty');
    }

    @IsTest
    static void encrypt_outputBytesAt12to27_matchSalt() {
        AscottCrypto.EncryptResult r = AscottCrypto.encryptWithCredential(
            checkUserExistPayload(), testCred()
        );
        String hex = EncodingUtil.convertToHex(
            EncodingUtil.base64Decode(EncodingUtil.urlDecode(r.encryptedT, 'UTF-8'))
        );

        // Bytes 12-27 (hex chars 24-55) must equal Salt.
        // IV (bytes 0-11) is Salesforce-generated and not asserted on.
        System.assertEquals(
            EncodingUtil.convertToHex(Blob.valueOf('sG3YrEDKPaj2nUXF')),
            hex.substring(24, 56),
            'Bytes 12-27 must be Salt'
        );
    }

    @IsTest
    static void encrypt_xsAppFromCredential() {
        AscottCrypto.EncryptResult r = AscottCrypto.encryptWithCredential(
            checkUserExistPayload(), testCred()
        );
        System.assertEquals('asr_api_v2_1', r.xsApp);
    }

    // ── Non-determinism (random IV means same input produces different output) ───

    @IsTest
    static void encrypt_randomIv_sameInputProducesDifferentOutput() {
        Ascott_Credential__mdt cred = testCred();
        Map<String, Object> payload = checkUserExistPayload();

        AscottCrypto.EncryptResult r1 = AscottCrypto.encryptWithCredential(payload, cred);
        AscottCrypto.EncryptResult r2 = AscottCrypto.encryptWithCredential(payload, cred);

        System.assertNotEquals(r1.encryptedT, r2.encryptedT, 'Random IV: same input must produce different ciphertext each call');
    }

    @IsTest
    static void encrypt_differentPayloads_differentOutput() {
        Ascott_Credential__mdt cred = testCred();

        AscottCrypto.EncryptResult r1 = AscottCrypto.encryptWithCredential(
            new Map<String, Object>{ 'action' => 'checkUserExist', 'email' => 'a@example.com' },
            cred
        );
        AscottCrypto.EncryptResult r2 = AscottCrypto.encryptWithCredential(
            new Map<String, Object>{ 'action' => 'register', 'email' => 'b@example.com' },
            cred
        );

        System.assertNotEquals(r1.encryptedT, r2.encryptedT, 'Different payloads must produce different output');
    }

    // ── sysToken isolation ────────────────────────────────────────────────

    @IsTest
    static void encrypt_sysTokenInjected_originalMapNotModified() {
        Map<String, Object> payload = checkUserExistPayload();
        AscottCrypto.encryptWithCredential(payload, testCred());

        System.assert(!payload.containsKey('sysToken'), 'Original payload map must not be modified');
    }

    // ── Error handling ────────────────────────────────────────────────────

    @IsTest
    static void encrypt_blankAesKey_throwsCryptoError() {
        Ascott_Credential__mdt cred = testCred();
        cred.Aes_Key_Base64__c = '';

        AscottApiException caught;
        try {
            AscottCrypto.encryptWithCredential(checkUserExistPayload(), cred);
        } catch (AscottApiException e) {
            caught = e;
        }

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.CRYPTO_ERROR, caught.category);
    }

    @IsTest
    static void encryptPayload_noCredentialRecord_throwsCryptoError() {
        // No CMT record in test context (or Protected fields are null if record exists)
        // — either way, encryptPayload() must throw CRYPTO_ERROR.
        AscottApiException caught;
        Test.startTest();
        try {
            AscottCrypto.encryptPayload(checkUserExistPayload());
        } catch (AscottApiException e) {
            caught = e;
        }
        Test.stopTest();

        System.assert(caught != null);
        System.assertEquals(AscottApiException.ErrorCategory.CRYPTO_ERROR, caught.category);
    }
}
