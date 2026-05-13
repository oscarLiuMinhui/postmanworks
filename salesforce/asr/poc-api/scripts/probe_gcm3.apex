Blob key = Crypto.generateAesKey(256);
Blob plaintext = Blob.valueOf('hello world test payload for gcm');

// Test various algorithm names with encryptWithManagedIV
List<String> algos = new List<String>{
    'AES256GCM', 'AES-256-GCM', 'AES_256_GCM', 'AES256-GCM',
    'AES256_GCM_NO_PADDING', 'GCM_AES256', 'AES256_GCM_NOPADDING',
    'AES/GCM/NoPadding', 'AES/GCM', 'AES256_GCM_128TAG'
};
for (String algo : algos) {
    try {
        Blob result = Crypto.encryptWithManagedIV(algo, key, plaintext);
        System.debug('encryptWithManagedIV(' + algo + ') SUCCESS size: ' + result.size());
    } catch (System.InvalidParameterValueException e) {
        System.debug('encryptWithManagedIV(' + algo + ') InvalidParam: ' + e.getMessage().left(80));
    } catch (Exception e) {
        System.debug('encryptWithManagedIV(' + algo + ') other: ' + e.getMessage().left(80));
    }
}

// Try Crypto.sign with P1363 to understand the full feature
try {
    Blob hash = Crypto.generateDigest('SHA-256', plaintext);
    // Just checking if there's a signWithAlgorithm or similar method
    System.debug('SHA-256 digest size: ' + hash.size());
} catch (Exception e) {
    System.debug('Digest: ' + e.getMessage());
}

// What does AES256_GCM actually return when decrypt is attempted?
// First try an encrypt that gives "not expecting IV" to see if there's another approach
try {
    // Try with the plaintext as IV (hacky but let's see the error)
    Blob fakeResult = Crypto.encrypt('AES256_GCM', key, Blob.valueOf('a'), plaintext);
} catch (Exception e) {
    System.debug('AES256_GCM with 1-byte IV: ' + e.getMessage());
}

// Check if there's an EncryptedData result type in Crypto
// by checking what happens with decryptWithManagedIV for AES256_GCM
try {
    Blob dummyCipher = Blob.valueOf('dummy cipher dummy cipher dummy cipher dummy cipher');
    Blob result = Crypto.decryptWithManagedIV('AES256_GCM', key, dummyCipher);
    System.debug('decryptWithManagedIV AES256_GCM: ' + result.size());
} catch (Exception e) {
    System.debug('decryptWithManagedIV AES256_GCM: ' + e.getMessage().left(100));
}
