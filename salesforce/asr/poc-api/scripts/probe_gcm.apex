Blob key = Crypto.generateAesKey(256);
Blob plaintext = Blob.valueOf('hello world test payload');

// Try 3-argument version (no IV)
try {
    Blob result = Crypto.encrypt('AES256_GCM', key, plaintext);
    System.debug('3-arg AES256_GCM result size: ' + result.size());
} catch (Exception e) {
    System.debug('3-arg AES256_GCM failed: ' + e.getTypeName() + ': ' + e.getMessage());
}

// Try null IV in 4-arg
try {
    Blob result = Crypto.encrypt('AES256_GCM', key, null, plaintext);
    System.debug('4-arg null-IV AES256_GCM result size: ' + result.size());
} catch (Exception e) {
    System.debug('4-arg null-IV AES256_GCM failed: ' + e.getTypeName() + ': ' + e.getMessage());
}

// Try AES256 CBC with null IV (known to work)
try {
    Blob result = Crypto.encrypt('AES256', key, null, plaintext);
    System.debug('4-arg null-IV AES256 CBC result size: ' + result.size());
} catch (Exception e) {
    System.debug('4-arg null-IV AES256 CBC failed: ' + e.getTypeName() + ': ' + e.getMessage());
}

// Try different AES-GCM algorithm names
for (String algo : new List<String>{'AES256_GCM_NoPadding', 'AES/GCM/NoPadding', 'AES-256-GCM', 'AES256GCM'}) {
    try {
        Blob result = Crypto.encrypt(algo, key, plaintext);
        System.debug('3-arg ' + algo + ' result size: ' + result.size());
    } catch (Exception e) {
        System.debug('3-arg ' + algo + ' failed: ' + e.getMessage());
    }
}
