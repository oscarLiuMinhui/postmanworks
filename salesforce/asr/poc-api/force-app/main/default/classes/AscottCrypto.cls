public with sharing class AscottCrypto {

    public class EncryptResult {
        public String encryptedT { get; private set; }
        public String xsApp      { get; private set; }

        public EncryptResult(String encryptedT, String xsApp) {
            this.encryptedT = encryptedT;
            this.xsApp      = xsApp;
        }
    }

    public static EncryptResult encryptPayload(Map<String, Object> payload) {
        List<Ascott_Credential__mdt> creds = [
            SELECT Iv__c, Salt__c, Xs_App__c, Aes_Key_Base64__c, Sys_Token__c
            FROM Ascott_Credential__mdt
            LIMIT 1
        ];
        if (creds.isEmpty()) {
            throw new AscottApiException(
                'Ascott_Credential__mdt record not found',
                AscottApiException.ErrorCategory.CRYPTO_ERROR
            );
        }
        return encryptWithCredential(payload, creds[0]);
    }

    @TestVisible
    static EncryptResult encryptWithCredential(
        Map<String, Object> payload,
        Ascott_Credential__mdt cred
    ) {
        try {
            Map<String, Object> payloadWithToken = new Map<String, Object>(payload);
            payloadWithToken.put('sysToken', cred.Sys_Token__c);

            Blob plaintext = Blob.valueOf(JSON.serialize(payloadWithToken));
            Blob key       = EncodingUtil.base64Decode(cred.Aes_Key_Base64__c);
            Blob salt      = Blob.valueOf(cred.Salt__c);

            // Spring 2026 AES-GCM: use encryptWithManagedIV with algorithm 'AES256-GCM'.
            // Output format: [1-byte IV-length=0x0C][IV:12][ciphertext][auth-tag:16].
            Blob encOut = Crypto.encryptWithManagedIV('AES256-GCM', key, plaintext);

            // Wire format required by Ascott spec: [IV:12][SALT:16][ciphertext+tag].
            // Skip byte 0 (IV-length prefix), extract IV from bytes 1-12, then append SALT.
            String encHex  = EncodingUtil.convertToHex(encOut);
            String ivHex   = encHex.substring(2, 26);   // bytes 1-12 = IV (skip length prefix)
            String cipHex  = encHex.substring(26);       // bytes 13+ = ciphertext + auth tag
            String saltHex = EncodingUtil.convertToHex(salt);

            Blob combined = EncodingUtil.convertFromHex(ivHex + saltHex + cipHex);

            String b64 = EncodingUtil.base64Encode(combined);
            String t   = EncodingUtil.urlEncode(b64, 'UTF-8');

            return new EncryptResult(t, cred.Xs_App__c);

        } catch (AscottApiException e) {
            throw e;
        } catch (Exception e) {
            throw new AscottApiException(
                'AES-GCM encryption failed: ' + e.getMessage(),
                AscottApiException.ErrorCategory.CRYPTO_ERROR
            );
        }
    }
}
