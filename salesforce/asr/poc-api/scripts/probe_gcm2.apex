Blob key = Crypto.generateAesKey(256);
Blob plaintext = Blob.valueOf('hello world test');
Blob emptyBlob = Blob.valueOf('');
Blob twelveBytes = Blob.valueOf('123456789012');

// Try with empty Blob as IV (might bypass null check)
try {
    Blob result = Crypto.encrypt('AES256_GCM', key, emptyBlob, plaintext);
    System.debug('SUCCESS: empty-IV AES256_GCM result size: ' + result.size());
} catch (Exception e) {
    System.debug('empty-IV AES256_GCM: ' + e.getMessage());
}

// Try with a 12-byte Blob as IV
try {
    Blob result = Crypto.encrypt('AES256_GCM', key, twelveBytes, plaintext);
    System.debug('SUCCESS: 12byte-IV AES256_GCM result size: ' + result.size());
} catch (Exception e) {
    System.debug('12byte-IV AES256_GCM: ' + e.getMessage());
}

// Try encryptWithManagedIV style (if such method exists)
try {
    Blob result = Crypto.encryptWithManagedIV('AES256_GCM', key, plaintext);
    System.debug('SUCCESS: encryptWithManagedIV AES256_GCM result size: ' + result.size());
} catch (Exception e) {
    System.debug('encryptWithManagedIV AES256_GCM: ' + e.getTypeName() + ': ' + e.getMessage());
}

// Try encryptWithManagedIV with AES256 (should work)
try {
    Blob result = Crypto.encryptWithManagedIV('AES256', key, plaintext);
    System.debug('SUCCESS: encryptWithManagedIV AES256 result size: ' + result.size());
} catch (Exception e) {
    System.debug('encryptWithManagedIV AES256: ' + e.getTypeName() + ': ' + e.getMessage());
}
