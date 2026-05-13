# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## POC Background

Salesforce DX (API v66.0) proof-of-concept — Apex integration layer between Salesforce and the Ascott ASR Loyalty CRM API. Source lives under `force-app/main/default/`. API specification is at `docs/api.pdf`.

No middleware. No MuleSoft. Everything runs inside Salesforce Core.

Salesforce Spring 2026 added native AES-GCM support to the Apex `Crypto` class ("Enhance Security with AES-GCM Mode and P1363 Signing", release 256) [SF-GCM-2026]. This is the capability that makes the all-Apex approach possible.

## Commands

### Org operations (requires `sf` CLI and an authenticated org)

```bash
# Push source to scratch org
sf project deploy start --source-dir force-app

# Run all Apex tests
sf apex run test --result-format human --output-dir test-results --wait 10

# Run a single test class
sf apex run test --class-names AscottApiServiceTest --result-format human --wait 10

# Run a single test method
sf apex run test --tests AscottApiServiceTest.checkUserExistByEmail_userFoundAndActivated_member --wait 10

# Open scratch org in browser
sf org open
```

### Code quality

```bash
# Format all Apex, XML, JSON (Prettier with apex plugin)
npm run prettier

# Verify formatting without writing
npm run prettier:verify
```

> `npm run lint` only covers LWC/Aura JS — there is no Apex static analysis script configured.

---

## Architecture

### Integration flow

```
@AuraEnabled Apex method (AscottApiService)
    │
    ▼
AscottPayloadBuilder              — validates inputs, builds plain JSON payload map
    │                               sysToken intentionally excluded here
    ▼
AscottApiService.callAscott()     — single entry to the wire
    │
    ▼
AscottCrypto.encryptPayload()     — loads Ascott_Credential__mdt,
    │                               injects sysToken into payload map,
    │                               serialises to JSON,
    │                               runs AES/GCM/NoPadding (Spring 2026 Crypto),
    │                               returns EncryptResult { encryptedT, xsApp }
    ▼
AscottApiService.callAscott()     — GET callout:Ascott_API
    │                               ?xs_app=<xsApp>&t=<URL-encoded Base64>
    ▼
Ascott ASR API  (ascott-uat.crmxs.com)
    │
    ▼
AscottApiResponse.fromHttpResponse()
```

### PBKDF2

#### What PBKDF2 is

**PBKDF2** (Password-Based Key Derivation Function 2, RFC 2898 [RFC-2898]) is a _key-stretching_ algorithm. It turns a human-chosen password — which typically has low entropy — into a fixed-length cryptographic key suitable for symmetric encryption. It does this by running a pseudo-random function (here HMAC-SHA256) thousands of times over the password and a salt.

```
AES-256 key = PBKDF2(
    password   = "%+h9>GbrU~K$7WGJvD6~...",   // the shared secret from CPRV
    salt       = "sG3YrEDKPaj2nUXF",           // 16-byte constant (v2.1 spec)
    iterations = 65536,                         // work factor — slows brute-force
    keyLength  = 256 bits                       // output size matches AES-256
)
```

The iteration count (65536) is the deliberate cost — it makes each guess in a brute-force attack 65 536× more expensive than a single hash [NIST-132]. The _salt_ prevents pre-computation (rainbow table) attacks across different deployments.

#### Why Apex cannot do it at runtime

The Salesforce `Crypto` class (including Spring 2026) [SF-CRYPTO] provides AES encryption and digest functions but has **no PBKDF2 API**. There is no `Crypto.deriveKey()` or equivalent. Implementing 65 536 iterations of HMAC-SHA256 in Apex loops is technically possible but would consume CPU governor limits [SF-LIMITS] and take several seconds per request — both are unacceptable.

#### Why the pre-computed key is safe here

The Ascott v2.1 spec deliberately made SALT and IV **constants** (not per-request randoms). The spec changelog explicitly states this was done for performance — to avoid regenerating the secret key on every API call. This design decision has a direct implication:

> Because SALT is constant, `PBKDF2(PASSWORD, constant SALT)` always produces the same AES-256 key. The derived key is itself a constant.

Pre-computing that key offline and storing it is **mathematically identical** to runtime derivation. The spec authors already accepted this equivalence when they froze the SALT.

#### Reliability assessment

| Concern | Assessment |
|---|---|
| Correctness | Pre-computed key is bit-for-bit identical to what the Java reference implementation produces. Verified by running the same PBKDF2 offline and comparing encrypted outputs. |
| Key exposure risk | Protected Custom Metadata fields are encrypted at rest in Salesforce infrastructure and are not readable via Metadata API or SOQL — equivalent protection to storing a Named Credential secret. |
| Pre-computed key vs. password | Storing the derived key is marginally more sensitive than storing the password (an attacker with the key can decrypt directly, whereas with just the password they still need 65 536 PBKDF2 iterations). This is an acceptable trade-off because the key is in a Protected field, not in source code or logs. |
| Key rotation | When CPRV rotates the PASSWORD (and SALT), re-run the Python script and update `Aes_Key_Base64__c` in Setup. No code change needed. |
| Testing | Because the key is deterministic, integration tests can use the known UAT key to assert on decrypted output. |

#### Better alternatives (in order of preference)

**Option 1 — Runtime PBKDF2 if Salesforce adds it (preferred long-term)**

If a future Salesforce release adds `Crypto.generateDerivedKey()` or similar, migrate to runtime derivation. Store only PASSWORD and SALT in Protected CMT; never store the derived key. The `AscottCrypto` class is structured to make this a one-method swap.

```apex
// Hypothetical future API — verify exact signature in org when available
Blob key = Crypto.generateDerivedKey(
    'PBKDF2WithHmacSHA256',
    Blob.valueOf(cred.Password__c),
    Blob.valueOf(cred.Salt__c),
    65536,
    32   // bytes = 256 bits
);
```

**Option 2 — Current approach: pre-computed key in Protected CMT** _(implemented)_

Run the Python script once per environment, store Base64 key in `Aes_Key_Base64__c`. Acceptable for PoC and production given the Protected field guarantee.

**Option 3 — External KMS callout (over-engineered for this use case)**

Call AWS KMS or Azure Key Vault to retrieve the key at runtime. Adds a second HTTP callout per transaction and an external dependency. Not recommended unless the organisation already has a KMS in the integration layer.

### Credential storage strategy

#### Why Named Credentials alone are not enough

Named Credentials [SF-NC] are the correct Salesforce pattern for callout auth — they own the endpoint URL and can inject OAuth tokens or API keys as HTTP headers automatically. However, the Ascott `sysToken` must go **inside the AES-encrypted payload body**, not as an HTTP header. Named Credential values are injected by Salesforce's HTTP infrastructure and cannot be read back into Apex code. There is no `NamedCredential.getValue('sysToken')` API. So Named Credentials cannot serve as the source for sysToken injection into the encrypted JSON.

Named Credential `Ascott_API` still owns the endpoint URL and should be kept.

#### Salesforce-native options for secrets that Apex can read

| Option | Encrypted at rest | In source / deployable | Apex-readable at runtime | Protected field = null in test SOQL |
|---|---|---|---|---|
| **Protected Custom Metadata** | ✅ | Non-protected fields only | ✅ | ⚠️ Yes — see below |
| **Protected Custom Settings** | ✅ | No | ✅ | ⚠️ Yes |
| **Named Credentials** | ✅ | ✅ | ❌ value opaque to Apex | N/A |
| **Custom Labels** | ❌ plaintext | ✅ | ✅ | No |

Protected Custom Metadata [SF-CMT] is the recommended modern Salesforce pattern.

#### Critical testing limitation of Protected CMT fields

When Apex test code queries a Custom Metadata Type via SOQL, **Protected field values come back as null**. This is a Salesforce platform security constraint — test execution context cannot read Protected field values, even in a scratch org where you set them manually. This is the exact reason `AscottCrypto` exposes `@TestVisible encryptWithCredential(Map, Ascott_Credential__mdt cred)`: tests construct a credential object in memory and pass it directly, bypassing the SOQL query entirely. Any approach (Protected CMT or Protected Custom Settings) shares this same test-context limitation.

#### Field classification — what is actually sensitive

| Field | Sensitive? | Rationale | Storage |
|---|---|---|---|
| `Xs_App__c` (`asr_api_v2_1`) | No | Public URL parameter | Regular CMT field — in source |
| `Iv__c` (`PcGK5n4y72XL`) | No | Spec constant published in `docs/api.pdf` | Regular CMT field — in source |
| `Salt__c` (`sG3YrEDKPaj2nUXF`) | No | Spec constant published in `docs/api.pdf` | Regular CMT field — in source |
| `Aes_Key_Base64__c` | **Yes** | 256-bit derived encryption key | Protected CMT field — manual Setup only |
| `Sys_Token__c` | **Yes** | API authentication token from CPRV | Protected CMT field — manual Setup only |

IV and SALT are spec-defined constants already present in `docs/api.pdf` in this repo. Committing them to source is acceptable. The AES key and sysToken must never appear in source control, debug logs, or Metadata API exports.

#### POC vs Production guidance

**For POC (current scope)**

Protected Custom Metadata is sufficient:
1. Deploy the UAT record via `sf project deploy start` — this pushes only the non-protected fields (IV, SALT, xs_app).
2. After deploy, an admin opens **Setup → Custom Metadata Types → Ascott Credential → UAT** and manually enters `Aes_Key_Base64__c` and `Sys_Token__c`.
3. These values never appear in git, Metadata API exports, or debug logs.
4. Access is controlled by the "Customize Application" permission — effectively System Admin only.

**For Production**

The same mechanism works. Enforce these additional controls:

- **Separate PROD record**: create a `PROD` CMT record in the PROD org. Never copy UAT values across.
- **Restrict Setup access**: limit "Customize Application" permission in PROD to a dedicated integration admin role — not developers.
- **Rotation procedure**: when CPRV rotates sysToken or encryption credentials, the authorised admin updates only the Protected fields in Setup. No deployment and no code change needed.
- **Setup Audit Trail**: enable audit trail on the PROD org to log who changes Protected CMT records and when.

**For enterprise production (out of scope for this POC)**

If the organisation requires automated rotation, developer-prod separation, or cross-system secrets sharing, the right long-term answer is an external secrets manager (AWS Secrets Manager, Azure Key Vault). `AscottCrypto.encryptWithCredential()` accepts a plain `Ascott_Credential__mdt` object, so the credential loading can be swapped to a KMS callout without touching the encryption logic.

### AES-GCM wire format (spec v2.1)

```
key       = Base64.decode(cred.Aes_Key_Base64__c)           // 32 bytes
salt      = Blob.valueOf(cred.Salt__c)                       // 16 bytes  "sG3YrEDKPaj2nUXF"
plaintext = Blob.valueOf(JSON.serialize(payloadWithSysToken))

// Spring 2026: encryptWithManagedIV('AES256-GCM') generates a random 12-byte IV.
// Output format: [1-byte IV-length = 0x0C][IV:12][ciphertext:N][auth-tag:16]
encOut  = Crypto.encryptWithManagedIV('AES256-GCM', key, plaintext)
encHex  = EncodingUtil.convertToHex(encOut)
ivHex   = encHex.substring(2, 26)    // bytes 1-12 = IV (skip byte-0 length prefix)
cipHex  = encHex.substring(26)       // bytes 13+ = ciphertext + auth tag

// Wire format: [IV:12][SALT:16][ciphertext+auth-tag]
output  = EncodingUtil.base64Encode(EncodingUtil.convertFromHex(ivHex + saltHex + cipHex))
t_param = EncodingUtil.urlEncode(output, 'UTF-8')
```

**Confirmed in Spring 2026 org (API v66):**
- Algorithm string: `'AES256-GCM'` (hyphen, not underscore) — used with `encryptWithManagedIV` / `decryptWithManagedIV`
- `Crypto.encrypt('AES256_GCM', key, iv, plaintext)` does NOT work (rejects any IV value)
- IV is Salesforce-managed and random per call — the Ascott server reads IV from bytes 0-11 of the decoded wire payload
- AES-GCM is formally specified in NIST SP 800-38D [NIST-38D]

---

## Implementation plan

### Files to create

| File | Description |
|---|---|
| `force-app/main/default/classes/AscottCrypto.cls` | New — AES-GCM encryption class |
| `force-app/main/default/classes/AscottCrypto.cls-meta.xml` | Metadata for above |
| `force-app/main/default/classes/AscottCryptoTest.cls` | New — unit tests for AscottCrypto |
| `force-app/main/default/classes/AscottCryptoTest.cls-meta.xml` | Metadata for above |
| `force-app/main/default/objects/Ascott_Credential__mdt/` | New — CMT object definition + fields |
| `force-app/main/default/customMetadata/Ascott_Credential.UAT.md-meta.xml` | UAT record (non-protected fields only) |

### Files to modify

| File | Change summary |
|---|---|
| `force-app/main/default/classes/AscottApiService.cls` | Strip MuleSoft/sidecar paths; add `callAscott()` |
| `force-app/main/default/classes/AscottApiServiceTest.cls` | Remove two-path mocks; update to GET assertions |

`AscottPayloadBuilder`, `AscottApiResponse`, `AscottApiException` and their test classes are **unchanged**.

---

## `AscottCrypto` — full specification

### Public API

```apex
public with sharing class AscottCrypto {

    public class EncryptResult {
        public String encryptedT { get; }   // URL-encoded Base64(IV‖SALT‖cipherText)
        public String xsApp      { get; }   // value of ?xs_app= param from credential
    }

    // Main entry point. Loads credential, injects sysToken, encrypts.
    // Throws AscottApiException(CRYPTO_ERROR) on any failure.
    public static EncryptResult encryptPayload(Map<String, Object> payload) { ... }

    // @TestVisible variant — accepts a credential directly so tests bypass SOQL.
    @TestVisible
    static EncryptResult encryptWithCredential(
        Map<String, Object> payload,
        Ascott_Credential__mdt cred
    ) { ... }
}
```

### Internal logic of `encryptWithCredential`

1. Clone `payload` into a new map and put `sysToken` = `cred.Sys_Token__c`.
2. Serialise: `Blob plaintext = Blob.valueOf(JSON.serialize(payloadWithToken));`
3. Decode key: `Blob key = EncodingUtil.base64Decode(cred.Aes_Key_Base64__c);`
4. Build salt blob from `cred.Salt__c`. (`Iv__c` is stored in CMT for documentation but not passed to encrypt — Salesforce generates IV internally.)
5. Encrypt: `Blob encOut = Crypto.encryptWithManagedIV('AES256-GCM', key, plaintext);` — output is `[1-byte IV-length=0x0C][IV:12][ciphertext][auth-tag:16]`.
6. Extract IV and ciphertext+tag: skip byte 0 (length prefix), read bytes 1-12 as IV, bytes 13+ as cipHex.
7. Concatenate: `Blob combined = EncodingUtil.convertFromHex(ivHex + saltHex + cipHex);`
8. Encode: `String b64 = EncodingUtil.base64Encode(combined);`
9. URL-encode: `return new EncryptResult(EncodingUtil.urlEncode(b64, 'UTF-8'), cred.Xs_App__c);`

Wrap steps 3–9 in `try/catch(Exception e)` and rethrow as `AscottApiException(CRYPTO_ERROR)`.

### Blob concatenation in Apex

Apex has no `ByteBuffer`. Use this pattern:

```apex
String ivHex   = EncodingUtil.convertToHex(iv);
String saltHex = EncodingUtil.convertToHex(salt);
String cipHex  = EncodingUtil.convertToHex(cipher);
Blob combined  = EncodingUtil.convertFromHex(ivHex + saltHex + cipHex);
```

---

## `AscottApiService` — refactoring specification

### Remove entirely

- `NC_MULESOFT` constant and `NC_CRYPTO_SVC` constant
- `callViaMuleSoft(String path, Map<String,Object> payload)` method
- `callViaDirectWithCryptoSidecar(String xsApp, Map<String,Object> payload)` method
- `getEncryptedT(Map<String,Object> payload)` private method

### Keep unchanged

- `NC_ASCOTT_API` constant
- `generateCorrelationId()` static method
- All three `@AuraEnabled` public method signatures

### Add

```apex
// @TestVisible — tests inject a pre-built EncryptResult to bypass crypto entirely.
// Taking EncryptResult (not Map) is the key design decision: encryptPayload() runs
// SOQL that returns null Protected fields in test context, so the HTTP layer must
// be independently testable without going through crypto.
@TestVisible
static AscottApiResponse callAscott(AscottCrypto.EncryptResult enc) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(
        'callout:' + NC_ASCOTT_API
        + '/?xs_app=' + EncodingUtil.urlEncode(enc.xsApp, 'UTF-8')
        + '&t=' + enc.encryptedT
    );
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    req.setHeader('X-Correlation-Id', generateCorrelationId());
    req.setTimeout(TIMEOUT_MS);

    try {
        HttpResponse res = new Http().send(req);
        return AscottApiResponse.fromHttpResponse(res);
    } catch (CalloutException e) {
        throw new AscottApiException(
            'Network error calling Ascott: ' + e.getMessage(),
            AscottApiException.ErrorCategory.NETWORK_ERROR
        );
    }
}
```

### Update public methods

Replace `callViaMuleSoft(...)` with `encryptPayload` + `callAscott(enc)` in all three public methods:

```apex
public static AscottApiResponse checkUserExistByEmail(String email) {
    Map<String, Object> payload = AscottPayloadBuilder.checkUserExist(null, email, null);
    return callAscott(AscottCrypto.encryptPayload(payload));
}
// same pattern for checkUserExistByMobile and register
```

---

## `Ascott_Credential__mdt` — metadata specification

> For the rationale behind this design (why Protected CMT, why not Named Credentials, POC vs PROD guidance), see **Credential storage strategy** in the Architecture section above.

### Object definition
`force-app/main/default/objects/Ascott_Credential__mdt/Ascott_Credential__mdt.object-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Ascott ASR API credentials per environment. Aes_Key_Base64__c and Sys_Token__c are Protected — encrypted at rest, not exportable via Metadata API, must be set manually in Setup.</description>
    <label>Ascott Credential</label>
    <pluralLabel>Ascott Credentials</pluralLabel>
</CustomObject>
```

### Fields to create under `objects/Ascott_Credential__mdt/fields/`

| Field file | Label | Type | Protected | Set by |
|---|---|---|---|---|
| `Iv__c.field-meta.xml` | IV | Text(20) | No | Deployment |
| `Salt__c.field-meta.xml` | Salt | Text(20) | No | Deployment |
| `Xs_App__c.field-meta.xml` | xs_app Value | Text(50) | No | Deployment |
| `Aes_Key_Base64__c.field-meta.xml` | AES Key (Base64) | LongTextArea | **Yes** | Admin in Setup only |
| `Sys_Token__c.field-meta.xml` | Sys Token | LongTextArea | **Yes** | Admin in Setup only |

### UAT record — deploy only non-protected fields
`force-app/main/default/customMetadata/Ascott_Credential.UAT.md-meta.xml`

Only IV, SALT, and xs_app are included here. `Aes_Key_Base64__c` and `Sys_Token__c` are Protected and cannot be in source — set them manually in Setup after deploy.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>UAT</label>
    <protected>false</protected>
    <values>
        <field>Iv__c</field>
        <value xsi:type="xsd:string">PcGK5n4y72XL</value>
    </values>
    <values>
        <field>Salt__c</field>
        <value xsi:type="xsd:string">sG3YrEDKPaj2nUXF</value>
    </values>
    <values>
        <field>Xs_App__c</field>
        <value xsi:type="xsd:string">asr_api_v2_1</value>
    </values>
</CustomMetadata>
```

### Post-deploy Setup steps (every environment)

1. Go to **Setup → Custom Metadata Types → Ascott Credential → Manage Records**.
2. Open the record for this environment (`UAT` or `PROD`).
3. Enter `Aes_Key_Base64__c`: output of the Python key-derivation script (see *One-time setup* section).
4. Enter `Sys_Token__c`: the sysToken value provided by CPRV for this environment.
5. Save. These values are now encrypted at rest and will never appear in Metadata API exports or debug logs.

---

## `AscottCryptoTest` — test specification

Use `@TestVisible` `encryptWithCredential()` to inject a mock credential — bypasses Custom Metadata SOQL so tests run without org data.

### Helper: build test credential

```apex
private static Ascott_Credential__mdt testCred() {
    Ascott_Credential__mdt c = new Ascott_Credential__mdt();
    c.Iv__c             = 'PcGK5n4y72XL';        // 12 bytes
    c.Salt__c           = 'sG3YrEDKPaj2nUXF';     // 16 bytes
    c.Xs_App__c         = 'asr_api_v2_1';
    c.Sys_Token__c      = 'test-sys-token';
    // Generate a random but cryptographically valid 256-bit key at test time.
    // No pre-computed UAT key needed — tests verify structure, not specific ciphertext.
    c.Aes_Key_Base64__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    return c;
}
```

### Tests to write

| Test method | Asserts |
|---|---|
| `encrypt_outputIsValidBase64UrlEncoded` | `EncodingUtil.base64Decode(urlDecode(result.encryptedT))` does not throw |
| `encrypt_outputPrefixMatchesIvThenSalt` | Decode output; bytes 0–11 == `Blob.valueOf('PcGK5n4y72XL')`; bytes 12–27 == `Blob.valueOf('sG3YrEDKPaj2nUXF')` |
| `encrypt_deterministicWithConstantIv` | Same payload encrypted twice produces identical `encryptedT` |
| `encrypt_sysTokenInjected_notInInputMap` | Input map has no sysToken; output cipherText (once decrypted) contains sysToken field |
| `encrypt_differentPayloads_differentOutput` | `checkUserExist` payload ≠ `register` payload output |
| `encrypt_blankAesKey_throwsCryptoError` | `cred.Aes_Key_Base64__c = ''` → `AscottApiException(CRYPTO_ERROR)` |
| `encrypt_xsAppFromCredential` | `result.xsApp == 'asr_api_v2_1'` |
| `encryptPayload_noCredentialRecord_throwsCryptoError` | When no `Ascott_Credential__mdt` record exists, `encryptPayload()` throws `CRYPTO_ERROR` |

---

## `AscottApiServiceTest` — update specification

### Remove

- `RoutingMock` inner class
- `AscottNetworkFailMock` inner class
- `namedCredentialConstants_haveExpectedValues` test (NC_MULESOFT and NC_CRYPTO_SVC constants are deleted)
- `callViaDirectWithCryptoSidecar_*` test methods (5 tests)
- `callViaMuleSoft_requestBody_containsExpectedFields` (POST-specific assertion)

### Update — HTTP response tests call `callAscott(enc)` directly

`callAscott` now takes `AscottCrypto.EncryptResult`, not a Map. Tests that exercise HTTP responses (200/400/401/500, network error) must call `callAscott` directly with a dummy `EncryptResult` — calling through the public `@AuraEnabled` methods would hit `AscottCrypto.encryptPayload()` which queries CMT and finds no record in test context.

```apex
// Pattern for all HTTP response tests:
AscottCrypto.EncryptResult dummyEnc = new AscottCrypto.EncryptResult('DUMMY_T', 'asr_api_v2_1');
Test.setMock(HttpCalloutMock.class, new StaticMock(200, '{"exist":"true",...}'));
AscottApiResponse r = AscottApiService.callAscott(dummyEnc);
```

`callViaMuleSoft_requestHeaders_areCorrect` → rename to `callAscott_requestIsGet_withQueryParams`:

```apex
// Before (POST assertions):
System.assertEquals('POST', mock.lastRequest.getMethod());
System.assert(body.contains('checkUserExist'));

// After (GET assertions via callAscott directly):
AscottCrypto.EncryptResult enc = new AscottCrypto.EncryptResult('DUMMY_T', 'asr_api_v2_1');
AscottApiService.callAscott(enc);
System.assertEquals('GET', mock.lastRequest.getMethod());
System.assert(mock.lastRequest.getEndpoint().contains('xs_app='));
System.assert(mock.lastRequest.getEndpoint().contains('&t='));
System.assertEquals('', mock.lastRequest.getBody());
```

### Add

```apex
@IsTest
static void callAscott_cryptoFailure_throwsCryptoError() {
    // No CMT record exists in test context → encryptPayload() throws CRYPTO_ERROR
    // before any HTTP callout. No HttpCalloutMock needed.
    AscottApiException caught;
    Test.startTest();
    try {
        AscottApiService.checkUserExistByEmail('valid@example.com');
    } catch (AscottApiException e) {
        caught = e;
    }
    Test.stopTest();
    System.assertNotNull(caught);
    System.assertEquals(AscottApiException.ErrorCategory.CRYPTO_ERROR, caught.category);
}
```

Input validation tests (`checkUserExistByEmail_invalidEmailFormat_*`, `checkUserExistByMobile_*`, `register_invalid*`) are **unchanged** — they throw inside `AscottPayloadBuilder` before crypto is ever reached, so they still call through the public `@AuraEnabled` methods.

---

## Named Credential (manual setup in Salesforce Setup)

| Label | URL | Auth |
|---|---|---|
| `Ascott_API` | `https://ascott-uat.crmxs.com` (UAT) | None — auth is inside the encrypted `t` param |

---

## Class responsibilities (final state)

| Class | Status | Role |
|---|---|---|
| `AscottApiService` | **Refactor** | `@AuraEnabled` entry point. Calls `AscottPayloadBuilder` → `AscottCrypto` → single GET callout. |
| `AscottCrypto` | **New** | Loads `Ascott_Credential__mdt`, injects sysToken, AES/GCM/NoPadding encryption, returns `EncryptResult`. |
| `AscottPayloadBuilder` | No change | Input validation + payload map. sysToken excluded — `AscottCrypto` injects it. |
| `AscottApiResponse` | No change | Parses `HttpResponse` into typed fields. |
| `AscottApiException` | No change | Typed exception; `CRYPTO_ERROR` now covers Apex AES-GCM failures. |

---

## Key invariants

- **sysToken never in `AscottPayloadBuilder` or `AscottApiService` public interface.** Only touches memory inside `AscottCrypto.encryptWithCredential()`.
- **`@AuraEnabled` methods must be `cacheable=false`** — never cache API results.
- **`with sharing`** on service and builder.
- **One HTTP callout per transaction.**
- **Protected Custom Metadata fields** (`Aes_Key_Base64__c`, `Sys_Token__c`) must be set manually in Setup — they are not in source control and cannot be deployed via Metadata API.

---

## Ascott API spec facts [ASCOTT-SPEC]

- Endpoint: `GET /?xs_app=asr_api_v2_1&t=<encrypted>` — the entire payload travels inside the encrypted `t` parameter
- `registrationType` values: `FULL`, `PARTIAL`, `BY_REFERRAL`, `JOINANDBOOK`
- `offers`: `"M"` (Member offers), `"C"` (Corporate offers)
- Mobile number format: `+<countrycode>|<number>` e.g. `+65|86122031`
- Password: 8–16 chars, upper + lower + digit + `!@#$%^&*()_+=-.`
- Auto-activation (server-set): `FULL` + referral code prefixed `GS20`, or any `JOINANDBOOK`
- `PARTIAL`, `BY_REFERRAL`, `JOINANDBOOK` return `memberId` in response; `FULL` does not

---

## One-time setup: pre-compute the AES key

Before deploying to a new environment, run this once (Python):

```python
import hashlib, base64
password = b'%+h9>GbrU~K$7WGJvD6~wF$i;Z|{mru*IxXVRyg{)l*V#Xm^2x'  # UAT value
salt     = b'sG3YrEDKPaj2nUXF'
key      = hashlib.pbkdf2_hmac('sha256', password, salt, 65536, dklen=32)
print(base64.b64encode(key).decode())  # paste into Aes_Key_Base64__c in Setup
```

PROD PASSWORD/SALT/IV/sysToken are provided separately by CPRV and must be set the same way.

---

## References

### Standards

- **[RFC-2898]** Kaliski, B. "PKCS #5: Password-Based Cryptography Specification Version 2.0." RFC 2898. IETF, 2000. <https://www.rfc-editor.org/rfc/rfc2898>
- **[NIST-38D]** Dworkin, M. "Recommendation for Block Cipher Modes of Operation: Galois/Counter Mode (GCM) and GMAC." NIST SP 800-38D. November 2007. <https://doi.org/10.6028/NIST.SP.800-38D>
- **[NIST-132]** Turan, M.S. et al. "Recommendation for Password-Based Key Derivation." NIST SP 800-132. December 2010. <https://doi.org/10.6028/NIST.SP.800-132>

### OWASP

- **[OWASP-PS]** OWASP. "Password Storage Cheat Sheet." <https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html>
  Note: the 600,000-iteration recommendation applies to user password hashing, not to key derivation from a high-entropy machine secret (48-char mixed symbols). For key derivation, NIST SP 800-132 sets a minimum of 1,000 iterations — 65,536 is well above this floor.
- **[OWASP-CS]** OWASP. "Cryptographic Storage Cheat Sheet." <https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html>

### Salesforce

- **[SF-GCM-2026]** Salesforce. "Spring '26 Release Notes: Enhance Security with AES-GCM Mode and P1363 Signing." Release 256. Search "AES-GCM" in the Spring '26 Apex release notes at <https://help.salesforce.com/s/articleView?id=release-notes.rn_apex.htm&release=256>
- **[SF-CRYPTO]** Salesforce. "Crypto Class." Apex Reference Guide. <https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_classes_restful_crypto.htm>
- **[SF-LIMITS]** Salesforce. "Execution Governors and Limits." Apex Developer Guide. <https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm>
- **[SF-CMT]** Salesforce. "Custom Metadata Types Implementation Guide." <https://developer.salesforce.com/docs/atlas.en-us.custommetadatatypes.meta/custommetadatatypes/custommetadatatypes_about.htm>
- **[SF-NC]** Salesforce. "Named Credentials." Salesforce Help. <https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm>

### Project

- **[ASCOTT-SPEC]** Ascott. "ASR Loyalty CRM API Specification v2.1." [`docs/api.pdf`](docs/api.pdf)

---

# Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
