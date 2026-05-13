$ErrorActionPreference = "Stop"

$outPath = "C:\Users\MinhuiLiu\Downloads\postman-ascott\postmanworks\salesforce\asr\poc-api\docs\Ascott_ASR_Integration_POC.docx"

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc  = $word.Documents.Add()
$sel  = $word.Selection

function H1($t) { $sel.Style = $doc.Styles["Heading 1"]; $sel.TypeText($t); $sel.TypeParagraph() }
function H2($t) { $sel.Style = $doc.Styles["Heading 2"]; $sel.TypeText($t); $sel.TypeParagraph() }
function H3($t) { $sel.Style = $doc.Styles["Heading 3"]; $sel.TypeText($t); $sel.TypeParagraph() }
function P($t)  { $sel.Style = $doc.Styles["Normal"];    $sel.TypeText($t); $sel.TypeParagraph() }
function B($t)  { $sel.Style = $doc.Styles["List Bullet"]; $sel.TypeText($t); $sel.TypeParagraph() }
function Sep()  { $sel.Style = $doc.Styles["Normal"]; $sel.TypeParagraph() }

function Code($t) {
    $sel.Style = $doc.Styles["Normal"]
    $sel.Font.Name = "Courier New"
    $sel.Font.Size = 9
    $sel.TypeText($t)
    $sel.TypeParagraph()
    $sel.Font.Name = "Calibri"
    $sel.Font.Size = 11
}

# Takes: headers (string[]), data as flat string[] row-major, numCols = headers.Count
function MakeTable([string[]] $headers, [string[]] $data) {
    $nc = $headers.Count
    $nr = [int]($data.Count / $nc)
    $sel.EndKey(6) | Out-Null
    $tbl = $doc.Tables.Add($sel.Range, 1 + $nr, $nc)
    try { $tbl.Style = $doc.Styles["Table Grid"] } catch {}
    $tbl.Rows[1].HeadingFormat = $true
    for ($c = 1; $c -le $nc; $c++) {
        $tbl.Cell(1, $c).Range.Font.Bold = $true
        $tbl.Cell(1, $c).Range.Text = $headers[$c - 1]
    }
    for ($r = 0; $r -lt $nr; $r++) {
        for ($c = 1; $c -le $nc; $c++) {
            $tbl.Cell($r + 2, $c).Range.Text = $data[$r * $nc + $c - 1]
        }
    }
    $sel.EndKey(6) | Out-Null
    $sel.TypeParagraph()
}

# ── Title ─────────────────────────────────────────────────────────────────────
$sel.Style = $doc.Styles["Title"]
$sel.TypeText("Ascott ASR Loyalty CRM API Integration")
$sel.TypeParagraph()
$sel.Style = $doc.Styles["Subtitle"]
$sel.TypeText("Salesforce Proof of Concept - Architecture and Design")
$sel.TypeParagraph()
Sep
$sel.Style = $doc.Styles["Normal"]
$sel.TypeText("May 2026  |  Salesforce API v66.0  |  Internal - Confidential")
$sel.TypeParagraph()
$doc.Words.Last.InsertBreak(7) | Out-Null

# ── 1. Overview ───────────────────────────────────────────────────────────────
H1("1. Overview")
P("This document describes the proof-of-concept architecture for integrating Salesforce with the Ascott ASR Loyalty CRM API. The integration is implemented entirely in Salesforce Apex - no middleware, no MuleSoft. All encryption, credential management, and API callout logic runs inside Salesforce Core.")
Sep
P("The approach became viable with the Salesforce Spring 2026 release, which added native AES-GCM support to the Apex Crypto class [SF-GCM-2026]. This is the capability that eliminates the need for an external encryption sidecar.")

# ── 2. Architecture ───────────────────────────────────────────────────────────
H1("2. Architecture")
H2("2.1 Integration Flow")
P("Each inbound call from a Lightning component travels through the following layers:")
Sep
B("@AuraEnabled Apex method (AscottApiService) - public entry point called by Lightning components.")
B("AscottPayloadBuilder - validates inputs and builds the plain JSON payload map. The sysToken is intentionally excluded at this stage.")
B("AscottCrypto.encryptPayload() - loads the Ascott_Credential__mdt custom metadata record, injects the sysToken, serialises to JSON, and runs AES/GCM/NoPadding encryption. Returns an EncryptResult with the encrypted t parameter and the xs_app identifier.")
B("AscottApiService.callAscott() - issues a single HTTP GET callout to callout:Ascott_API with query parameters xs_app and t.")
B("AscottApiResponse.fromHttpResponse() - parses the HTTP response into typed fields and throws a typed AscottApiException for non-2xx responses.")
Sep
P("One HTTP callout per transaction. No intermediate hops.")

H2("2.2 Class Responsibilities")
MakeTable `
    @("Class", "Status", "Responsibility") `
    @(
        "AscottApiService",     "Refactor",   "@AuraEnabled entry point. Delegates to AscottPayloadBuilder, then AscottCrypto, issues single GET callout.",
        "AscottCrypto",         "New",        "Loads Ascott_Credential__mdt, injects sysToken, AES/GCM/NoPadding encryption, returns EncryptResult.",
        "AscottPayloadBuilder", "No change",  "Input validation and payload map construction. sysToken excluded - AscottCrypto injects it.",
        "AscottApiResponse",    "No change",  "Parses HttpResponse into typed fields for register and checkUserExist response shapes.",
        "AscottApiException",   "No change",  "Typed exception. ErrorCategory.CRYPTO_ERROR covers Apex AES-GCM failures."
    )

# ── 3. Cryptography Design ────────────────────────────────────────────────────
H1("3. Cryptography Design")
H2("3.1 PBKDF2 Key Derivation")
H3("What PBKDF2 Is")
P("PBKDF2 (Password-Based Key Derivation Function 2, RFC 2898 [RFC-2898]) is a key-stretching algorithm. It derives a fixed-length cryptographic key from a password by running HMAC-SHA256 thousands of times over the password and a salt. The Ascott v2.1 spec uses 65,536 iterations and a 16-byte constant salt to produce a 256-bit AES key.")
Sep
P("The iteration count is the deliberate cost factor - it makes each brute-force guess 65,536 times more expensive than a single hash [NIST-132]. The salt prevents pre-computation (rainbow table) attacks.")

H3("Why PBKDF2 Cannot Run in Apex at Runtime")
P("The Salesforce Crypto class (including Spring 2026) [SF-CRYPTO] provides AES encryption and digest functions but has no PBKDF2 API. There is no Crypto.deriveKey() or equivalent. Implementing 65,536 iterations of HMAC-SHA256 in an Apex loop would exhaust CPU governor limits [SF-LIMITS] and take several seconds per request - both unacceptable for a synchronous Lightning call.")

H3("Why the Pre-computed Key Is Safe")
P("The Ascott v2.1 spec deliberately made the SALT and IV constants, not per-request randoms - an explicit design choice to avoid regenerating the key on every API call. Because the SALT is constant:")
Sep
P("    PBKDF2(PASSWORD, constant SALT) always produces the same AES-256 key.")
Sep
P("Pre-computing that key offline and storing it is mathematically identical to runtime derivation. The spec authors accepted this equivalence when they froze the SALT.")

H3("Reliability Assessment")
MakeTable `
    @("Concern", "Assessment") `
    @(
        "Correctness",                   "Pre-computed key is bit-for-bit identical to the Java reference implementation. Verified by comparing encrypted outputs.",
        "Key exposure risk",             "Protected Custom Metadata fields are encrypted at rest and are not readable via Metadata API or SOQL - equivalent protection to a Named Credential secret.",
        "Pre-computed key vs. password", "Storing the derived key is marginally more sensitive than storing the password. Acceptable because the key is in a Protected field, not in source code or logs.",
        "Key rotation",                  "When CPRV rotates PASSWORD (and SALT), re-run the Python derivation script and update Aes_Key_Base64__c in Setup. No code change needed.",
        "Testing",                       "Because the key is deterministic, test classes can use the known UAT key to verify encrypted output."
    )

H3("Better Alternatives (in Order of Preference)")
B("Option 1 - Runtime PBKDF2 (preferred long-term): If a future Salesforce release adds Crypto.generateDerivedKey() or equivalent, migrate to runtime derivation. Store only PASSWORD and SALT in Protected CMT. AscottCrypto is structured so this is a one-method swap.")
B("Option 2 - Pre-computed key in Protected CMT (current): Run the Python script once per environment, store the Base64 key in Aes_Key_Base64__c. Acceptable for PoC and production given the Protected field guarantee.")
B("Option 3 - External KMS callout (over-engineered): Call AWS KMS or Azure Key Vault at runtime. Adds a second HTTP callout per transaction and an external dependency. Not recommended unless the organisation already operates a KMS in the integration layer.")

H2("3.2 AES-GCM Wire Format")
P("The Ascott v2.1 spec uses AES-256 in GCM mode [NIST-38D]. The encrypted t query parameter is constructed as follows:")
Sep
Code("key        = Base64.decode(Aes_Key_Base64__c)              // 32 bytes")
Code("iv         = Blob.valueOf(Iv__c)                            // 12 bytes  PcGK5n4y72XL")
Code("salt       = Blob.valueOf(Salt__c)                          // 16 bytes  sG3YrEDKPaj2nUXF")
Code("plaintext  = JSON.serialize(payloadMapIncludingSysToken)")
Code("cipherText = Crypto.encrypt('AES256_GCM', key, iv, plaintext)  // appends 16-byte GCM auth tag")
Code("output     = Base64Encode( IV || SALT || cipherText )")
Code("t_param    = URL-encode(output, UTF-8)")
Sep
P("The exact algorithm name string must be confirmed against the live Spring 2026 org Apex reference before first deployment.")

# ── 4. Credential Storage Strategy ───────────────────────────────────────────
H1("4. Credential Storage Strategy")
H2("4.1 Why Named Credentials Alone Are Not Enough")
P("Named Credentials [SF-NC] are the correct Salesforce pattern for callout authentication - they own the endpoint URL and inject OAuth tokens or API keys as HTTP headers automatically. However, the Ascott sysToken must travel inside the AES-encrypted payload body, not as an HTTP header. Named Credential values are injected by Salesforce's HTTP infrastructure and are opaque to Apex code - there is no NamedCredential.getValue() API.")
Sep
P("Named Credential Ascott_API still owns the endpoint URL and is retained. Protected Custom Metadata is used for the secrets that Apex must read at runtime.")

H2("4.2 Salesforce-Native Options for Apex-Readable Secrets")
MakeTable `
    @("Option", "Encrypted at rest", "Deployable via Metadata API", "Apex-readable", "Protected field null in test SOQL") `
    @(
        "Protected Custom Metadata (chosen)", "Yes", "Non-protected fields only", "Yes", "Yes - see Section 4.4",
        "Protected Custom Settings",          "Yes", "No",                        "Yes", "Yes",
        "Named Credentials",                  "Yes", "Yes",                       "No - value opaque to Apex", "N/A",
        "Custom Labels",                      "No - plaintext", "Yes",            "Yes", "No"
    )

H2("4.3 Field Classification")
MakeTable `
    @("Field", "Value", "Sensitive?", "Storage") `
    @(
        "Xs_App__c",        "asr_api_v2_1",     "No - public URL parameter",          "Regular CMT field, in source control",
        "Iv__c",            "PcGK5n4y72XL",     "No - spec constant in docs/api.pdf", "Regular CMT field, in source control",
        "Salt__c",          "sG3YrEDKPaj2nUXF", "No - spec constant in docs/api.pdf", "Regular CMT field, in source control",
        "Aes_Key_Base64__c","(derived key)",     "Yes - 256-bit AES encryption key",   "Protected CMT field, manual Setup only",
        "Sys_Token__c",     "(from CPRV)",       "Yes - API authentication token",     "Protected CMT field, manual Setup only"
    )

H2("4.4 Critical Testing Limitation of Protected Fields")
P("When Apex test code queries a Custom Metadata Type via SOQL, Protected field values return null. This is a Salesforce platform security constraint - the test execution context cannot read Protected field values even in a scratch org where they have been set manually.")
Sep
P("For this reason, AscottCrypto exposes a @TestVisible encryptWithCredential(Map, Ascott_Credential__mdt cred) variant. Tests construct a credential object in memory and pass it directly, bypassing the SOQL query entirely. The same limitation applies to Protected Custom Settings.")

H2("4.5 Deployment Guidance")
H3("POC (Current Scope)")
B("Deploy via 'sf project deploy start' - pushes only non-protected fields (IV, SALT, xs_app).")
B("After deploy, open Setup > Custom Metadata Types > Ascott Credential > UAT and manually enter Aes_Key_Base64__c and Sys_Token__c.")
B("These values never appear in git, Metadata API exports, or debug logs.")
B("Access is controlled by the Customize Application permission - effectively System Admin only.")

H3("Production")
B("Create a separate PROD CMT record in the PROD org. Never copy UAT credential values across.")
B("Restrict the Customize Application permission to a dedicated integration admin role - not developers.")
B("When CPRV rotates credentials, the authorised admin updates the Protected fields in Setup. No deployment or code change required.")
B("Enable Setup Audit Trail in the PROD org to log who changes Protected CMT records and when.")

H3("Enterprise Production (Out of Scope for This PoC)")
P("If the organisation requires automated rotation, developer-prod separation, or cross-system secrets sharing, the right long-term answer is an external secrets manager (AWS Secrets Manager, Azure Key Vault). AscottCrypto.encryptWithCredential() accepts a plain Ascott_Credential__mdt object, so the credential loading can be swapped to a KMS callout without touching the encryption logic.")

# ── 5. Key Design Invariants ──────────────────────────────────────────────────
H1("5. Key Design Invariants")
B("sysToken never appears in AscottPayloadBuilder or the AscottApiService public interface. It only touches memory inside AscottCrypto.encryptWithCredential().")
B("@AuraEnabled methods must be cacheable=false - API results must never be cached.")
B("with sharing is enforced on service and builder classes.")
B("One HTTP callout per transaction.")
B("Protected Custom Metadata fields (Aes_Key_Base64__c, Sys_Token__c) must be set manually in Setup - they are not in source control and cannot be deployed via Metadata API.")

# ── 6. API Specification Summary ──────────────────────────────────────────────
H1("6. API Specification Summary [ASCOTT-SPEC]")
MakeTable `
    @("Attribute", "Detail") `
    @(
        "Endpoint",                "GET /?xs_app=asr_api_v2_1&t=<encrypted> - entire payload inside the encrypted t parameter",
        "registrationType values", "FULL, PARTIAL, BY_REFERRAL, JOINANDBOOK",
        "offers",                  "M = Member offers;  C = Corporate offers",
        "Mobile number format",    "+<countrycode>|<number>   e.g. +65|86122031",
        "Password rules",          "8-16 chars; must contain uppercase, lowercase, digit, and special character",
        "Auto-activation",         "FULL registration with GS20-prefixed referral code, or any JOINANDBOOK registration",
        "memberId in response",    "Returned for PARTIAL, BY_REFERRAL, JOINANDBOOK. Not returned for FULL."
    )

# ── 7. Setup and Deployment ───────────────────────────────────────────────────
H1("7. Setup and Deployment")
H2("7.1 Named Credential")
MakeTable `
    @("Label", "URL", "Authentication") `
    @("Ascott_API", "https://ascott-uat.crmxs.com  (UAT)", "None - auth is inside the encrypted t parameter")

H2("7.2 One-Time AES Key Pre-computation")
P("Before deploying to a new environment, run this Python script once to derive the AES-256 key from the CPRV-supplied PASSWORD and SALT:")
Sep
Code("import hashlib, base64")
Code("password = b'<PASSWORD from CPRV>'")
Code("salt     = b'<SALT from CPRV>'")
Code("key      = hashlib.pbkdf2_hmac('sha256', password, salt, 65536, dklen=32)")
Code("print(base64.b64encode(key).decode())   # paste into Aes_Key_Base64__c in Setup")
Sep
P("PROD PASSWORD, SALT, IV, and sysToken are provided separately by CPRV and must be entered the same way. Never commit these values to source control.")

H2("7.3 Post-Deploy Setup Steps (Every Environment)")
B("1.  Go to Setup > Custom Metadata Types > Ascott Credential > Manage Records.")
B("2.  Open the record for this environment (UAT or PROD).")
B("3.  Enter Aes_Key_Base64__c - paste the output of the Python derivation script.")
B("4.  Enter Sys_Token__c - the sysToken value provided by CPRV for this environment.")
B("5.  Save. Values are now encrypted at rest and will not appear in Metadata API exports or debug logs.")

# ── 8. References ─────────────────────────────────────────────────────────────
H1("8. References")
H2("Standards")
B("[RFC-2898]   Kaliski, B. PKCS #5: Password-Based Cryptography Specification v2.0. IETF RFC 2898, 2000.  https://www.rfc-editor.org/rfc/rfc2898")
B("[NIST-38D]   Dworkin, M. Recommendation for Block Cipher Modes of Operation: GCM and GMAC. NIST SP 800-38D, 2007.  https://doi.org/10.6028/NIST.SP.800-38D")
B("[NIST-132]   Turan, M.S. et al. Recommendation for Password-Based Key Derivation. NIST SP 800-132, 2010.  https://doi.org/10.6028/NIST.SP.800-132")

H2("OWASP")
B("[OWASP-PS]   OWASP. Password Storage Cheat Sheet.  https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html")
P("             Note: the 600,000-iteration recommendation targets user password hashing. For key derivation from a high-entropy machine secret, NIST SP 800-132 sets a minimum of 1,000 iterations; 65,536 is well above this floor.")
B("[OWASP-CS]   OWASP. Cryptographic Storage Cheat Sheet.  https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html")

H2("Salesforce")
B("[SF-GCM-2026]  Salesforce. Spring 26 Release Notes: Enhance Security with AES-GCM Mode and P1363 Signing. Release 256.  https://help.salesforce.com/s/articleView?id=release-notes.rn_apex.htm&release=256")
B("[SF-CRYPTO]    Salesforce. Crypto Class. Apex Reference Guide.  https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_classes_restful_crypto.htm")
B("[SF-LIMITS]    Salesforce. Execution Governors and Limits. Apex Developer Guide.  https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm")
B("[SF-CMT]       Salesforce. Custom Metadata Types Implementation Guide.  https://developer.salesforce.com/docs/atlas.en-us.custommetadatatypes.meta/custommetadatatypes/custommetadatatypes_about.htm")
B("[SF-NC]        Salesforce. Named Credentials. Salesforce Help.  https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm")

H2("Project")
B("[ASCOTT-SPEC]  Ascott. ASR Loyalty CRM API Specification v2.1.  docs/api.pdf")

# ── Save ──────────────────────────────────────────────────────────────────────
$doc.SaveAs2($outPath, 16)
$doc.Close($false)
$word.Quit()
Write-Output "Saved: $outPath"
