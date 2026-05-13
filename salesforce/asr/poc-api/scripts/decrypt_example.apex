// Decrypt the example URL's t parameter to reveal the sysToken
// Wire format decoded: IV(12) + SALT(16) + ciphertext(105) + tag(16) = 149 bytes

// The t parameter Base64 (URL-decoded)
String b64 = 'UGNHSzVuNHk3MlhMc0czWXJFREtQYWoyblVYRiPxhTSYD+M6eaxiT2vms7SUyBbM5mZ7TqFSb7u5lzr70VRJvInSuYQdcxb/CYLCSV51AX5r4cY5Sfeqw1Q+vSpx+0bkXaS4yJquY/futtwAswDYYJB3niSnHOGASh/Jd8seWUx/NYF08N8tQn9LcXjnezoN+SDsNIQ=';
Blob wire = EncodingUtil.base64Decode(b64);
String hex = EncodingUtil.convertToHex(wire);

// Extract IV (bytes 0-11), SALT (bytes 12-27), ciphertext+tag (bytes 28-148)
String ivHex   = hex.substring(0, 24);    // 12 bytes
String saltHex = hex.substring(24, 56);   // 16 bytes
String cipHex  = hex.substring(56);       // 121 bytes (105 ciphertext + 16 tag)

System.debug('IV   : ' + Blob.valueOf('PcGK5n4y72XL').equals(EncodingUtil.convertFromHex(ivHex)));
System.debug('SALT : ' + Blob.valueOf('sG3YrEDKPaj2nUXF').equals(EncodingUtil.convertFromHex(saltHex)));

// The AES key from CLAUDE.md UAT password (pre-computed PBKDF2)
// Paste your Aes_Key_Base64__c value here to test decryption:
String aesKeyBase64 = 'PASTE_YOUR_AES_KEY_HERE';

if (aesKeyBase64 == 'PASTE_YOUR_AES_KEY_HERE') {
    System.debug('>>> Run the Python PBKDF2 script first and paste the key above.');
} else {
    try {
        Blob key = EncodingUtil.base64Decode(aesKeyBase64);
        Blob iv  = EncodingUtil.convertFromHex(ivHex);
        // Reconstruct for decryptWithManagedIV: [0x0C][IV:12][ciptext+tag]
        String managedHex = '0c' + ivHex + cipHex;
        Blob managed = EncodingUtil.convertFromHex(managedHex);
        Blob plain = Crypto.decryptWithManagedIV('AES256-GCM', key, managed);
        System.debug('Decrypted payload: ' + plain.toString());
    } catch (Exception e) {
        System.debug('Decryption failed: ' + e.getMessage());
    }
}
