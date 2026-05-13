Blob key = Crypto.generateAesKey(256);
// Use exactly 10-char plaintext to make counting easy
Blob pt10 = Blob.valueOf('0123456789');  // 10 bytes
Blob pt20 = Blob.valueOf('01234567890123456789'); // 20 bytes

// Encrypt both
Blob r10 = Crypto.encryptWithManagedIV('AES256-GCM', key, pt10);
Blob r20 = Crypto.encryptWithManagedIV('AES256-GCM', key, pt20);

System.debug('10-byte plaintext -> result size: ' + r10.size());
System.debug('20-byte plaintext -> result size: ' + r20.size());
System.debug('Difference: ' + (r20.size() - r10.size())); // should be 10 for CTR mode

// Log the hex of first few bytes to understand structure
String hex10 = EncodingUtil.convertToHex(r10);
System.debug('r10 full hex: ' + hex10);
System.debug('r10 size: ' + r10.size());

// Encrypt a known plaintext twice and compare IVs (first N bytes)
Blob rA = Crypto.encryptWithManagedIV('AES256-GCM', key, pt10);
Blob rB = Crypto.encryptWithManagedIV('AES256-GCM', key, pt10);
String hexA = EncodingUtil.convertToHex(rA);
String hexB = EncodingUtil.convertToHex(rB);
System.debug('Two encryptions first 24 chars (IV?): ' + hexA.left(24) + ' vs ' + hexB.left(24));
System.debug('Same first 24? ' + (hexA.left(24) == hexB.left(24)));

// Try to decrypt to verify correctness
try {
    Blob decrypted = Crypto.decryptWithManagedIV('AES256-GCM', key, r10);
    System.debug('decryptWithManagedIV AES256-GCM result: ' + decrypted.toString());
} catch (Exception e) {
    System.debug('decryptWithManagedIV AES256-GCM failed: ' + e.getMessage());
}
