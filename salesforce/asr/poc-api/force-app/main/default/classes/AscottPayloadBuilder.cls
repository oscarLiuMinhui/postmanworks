/**
 * AscottPayloadBuilder
 *
 * Builds validated, spec-compliant JSON payload maps for each Ascott API method.
 * The maps are serialised to JSON by the service layer; they never include the
 * sysToken here — that is injected by the crypto/transport layer (MuleSoft or
 * the crypto sidecar) so it never appears in Apex debug logs.
 *
 * Spec ref: ASR_Loyalty_CRM_Interface_Specifications__SalesForce_BD v1.0.0
 *
 * Security standards applied:
 *   - Input validation at boundary (OWASP Input Validation Cheat Sheet)
 *   - No sensitive fields (sysToken, password) handled here — separation of concerns
 *   - Regex patterns taken verbatim from Ascott spec to avoid validation drift
 */
public with sharing class AscottPayloadBuilder {

    // ── Allowed enum values from spec ───────────────────────────────────
    private static final Set<String> VALID_SALUTATIONS =
        new Set<String>{ 'Dr', 'Mr', 'Mrs', 'Ms', 'Mx' };

    private static final Set<String> VALID_REGISTRATION_TYPES =
        new Set<String>{ 'FULL', 'PARTIAL', 'BY_REFERRAL', 'JOINANDBOOK' };

    private static final Set<String> VALID_OFFER_CODES =
        new Set<String>{ 'M', 'C' };

    private static final Set<String> VALID_GENDERS =
        new Set<String>{ 'M', 'F' };

    // Ascott email regex (spec p.3)
    private static final Pattern EMAIL_PATTERN = Pattern.compile(
        '([a-zA-Z0-9_.\\-&\'*^~+=?{}])+@(([a-zA-Z0-9_\\-])+\\.)+([a-zA-Z0-9_]{2,4})+'
    );

    // ── checkUserExist ──────────────────────────────────────────────────

    /**
     * Builds payload for the checkUserExist action.
     * Either email or mobileNumber is required (not both, not neither).
     *
     * @param sysToken      Client token — pass null here; injected by transport layer
     * @param email         Optional — validated per Ascott email spec
     * @param mobileNumber  Optional — format: +<countrycode>|<number>
     */
    public static Map<String, Object> checkUserExist(
        String sysToken,
        String email,
        String mobileNumber
    ) {
        if (String.isBlank(email) && String.isBlank(mobileNumber)) {
            throw new AscottApiException(
                'checkUserExist requires either email or mobileNumber',
                AscottApiException.ErrorCategory.VALIDATION_ERROR
            );
        }

        Map<String, Object> payload = new Map<String, Object>{
            'action' => 'checkUserExist'
        };
        if (!String.isBlank(sysToken))      payload.put('sysToken',      sysToken);
        if (!String.isBlank(email))         payload.put('email',         validateEmail(email));
        if (!String.isBlank(mobileNumber))  payload.put('mobileNumber',  validateMobileNumber(mobileNumber));
        return payload;
    }

    // ── Register ────────────────────────────────────────────────────────

    public class RegisterRequest {
        public String       registrationType    { get; set; }  // Required
        public String       salutation          { get; set; }  // Optional
        public String       firstName           { get; set; }  // Optional (required for PARTIAL)
        public String       lastName            { get; set; }  // Optional (required for PARTIAL)
        public String       displayName         { get; set; }  // Optional
        public String       email               { get; set; }  // Optional* (required for CPIS)
        public String       mobileNumber        { get; set; }  // Optional (required for China)
        public String       contactNumber       { get; set; }  // Optional
        public String       gender              { get; set; }  // Optional: "M" or "F"
        public String       dob                 { get; set; }  // Optional: datetime format
        public String       password            { get; set; }  // Optional* (required for CPIS)
        public String       companyName         { get; set; }  // Optional
        public String       companyEmail        { get; set; }  // Optional
        public String       countryOfResidence  { get; set; }  // Optional: ISO Alpha-2
        public List<String> offers              { get; set; }  // Optional: ["M","C"]
        public String       referralCode        { get; set; }  // Optional: max 100 chars
        public String       euResident          { get; set; }  // Optional: "yes" or "no"
        public String       geoLocation         { get; set; }  // Optional: ISO Alpha-2

        public void validate() {
            if (String.isBlank(registrationType)) {
                throw new AscottApiException('registrationType is required',
                    AscottApiException.ErrorCategory.VALIDATION_ERROR);
            }
            if (!VALID_REGISTRATION_TYPES.contains(registrationType.toUpperCase())) {
                throw new AscottApiException(
                    'Invalid registrationType. Allowed: ' + String.join(new List<String>(VALID_REGISTRATION_TYPES), ', '),
                    AscottApiException.ErrorCategory.VALIDATION_ERROR);
            }
            if (!String.isBlank(salutation) && !VALID_SALUTATIONS.contains(salutation)) {
                throw new AscottApiException(
                    'Invalid salutation. Allowed: Dr, Mr, Mrs, Ms, Mx',
                    AscottApiException.ErrorCategory.VALIDATION_ERROR);
            }
            if (!String.isBlank(gender) && !VALID_GENDERS.contains(gender)) {
                throw new AscottApiException('gender must be "M" or "F"',
                    AscottApiException.ErrorCategory.VALIDATION_ERROR);
            }
            if (!String.isBlank(email)) validateEmail(email);
            if (!String.isBlank(password)) validatePassword(password);
            if (!String.isBlank(referralCode)) validateReferralCode(referralCode);
            if (!String.isBlank(euResident) && !new Set<String>{'yes','no'}.contains(euResident.toLowerCase())) {
                throw new AscottApiException('euResident must be "yes" or "no"',
                    AscottApiException.ErrorCategory.VALIDATION_ERROR);
            }
            if (offers != null) {
                for (String offer : offers) {
                    if (!VALID_OFFER_CODES.contains(offer)) {
                        throw new AscottApiException('Invalid offer code: ' + offer + '. Allowed: M, C',
                            AscottApiException.ErrorCategory.VALIDATION_ERROR);
                    }
                }
            }
        }
    }

    public static Map<String, Object> register(String sysToken, RegisterRequest req) {
        req.validate();
        Map<String, Object> payload = new Map<String, Object>{
            'action'           => 'register',
            'registrationType' => req.registrationType.toUpperCase()
        };
        if (!String.isBlank(sysToken))             payload.put('sysToken',            sysToken);
        if (!String.isBlank(req.salutation))        payload.put('salutation',          req.salutation);
        if (!String.isBlank(req.firstName))         payload.put('firstName',           req.firstName);
        if (!String.isBlank(req.lastName))          payload.put('lastName',            req.lastName);
        if (!String.isBlank(req.displayName))       payload.put('displayName',         req.displayName);
        if (!String.isBlank(req.email))             payload.put('email',               req.email);
        if (!String.isBlank(req.mobileNumber))      payload.put('mobileNumber',        req.mobileNumber);
        if (!String.isBlank(req.contactNumber))     payload.put('contactNumber',       req.contactNumber);
        if (!String.isBlank(req.gender))            payload.put('gender',              req.gender);
        if (!String.isBlank(req.dob))               payload.put('dob',                 req.dob);
        if (!String.isBlank(req.password))          payload.put('password',            req.password);
        if (!String.isBlank(req.companyName))       payload.put('companyName',         req.companyName);
        if (!String.isBlank(req.companyEmail))      payload.put('companyEmailAddress', req.companyEmail);
        if (!String.isBlank(req.countryOfResidence))payload.put('countryOfResidence',  req.countryOfResidence);
        if (req.offers != null && !req.offers.isEmpty()) payload.put('offers', req.offers);
        if (!String.isBlank(req.referralCode))      payload.put('referralCode',        req.referralCode);
        if (!String.isBlank(req.euResident))        payload.put('euResident',          req.euResident.toLowerCase());
        if (!String.isBlank(req.geoLocation))       payload.put('geoLocation',         req.geoLocation);
        return payload;
    }

    // ── Input validators ────────────────────────────────────────────────

    /** Email validation per Ascott spec p.3 */
    public static String validateEmail(String email) {
        if (String.isBlank(email)) return email;
        if (email.substringBefore('@').length() > 64) {
            throw new AscottApiException(
                'Email local part must not exceed 64 characters',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        if (!EMAIL_PATTERN.matcher(email).matches()) {
            throw new AscottApiException(
                'Invalid email format',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        return email;
    }

    /**
     * Password validation per Ascott spec p.3:
     *   8–16 chars, alphanumeric + !@#$%^&*()_+=-.
     *   Must contain upper + lower + alpha + numeric.
     */
    public static String validatePassword(String password) {
        if (password.length() < 8 || password.length() > 16) {
            throw new AscottApiException('Password must be 8–16 characters',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        if (!Pattern.compile('[A-Z]').matcher(password).find()) {
            throw new AscottApiException('Password must contain an uppercase letter',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        if (!Pattern.compile('[a-z]').matcher(password).find()) {
            throw new AscottApiException('Password must contain a lowercase letter',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        if (!Pattern.compile('[0-9]').matcher(password).find()) {
            throw new AscottApiException('Password must contain a digit',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        if (!Pattern.compile('^[a-zA-Z0-9!@#$%^&*()_+=\\-.]+$').matcher(password).matches()) {
            throw new AscottApiException('Password contains invalid character(s)',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        return password;
    }

    /**
     * Referral code validation per Ascott spec p.3:
     *   A-Z, a-z, 0-9, !@#$%^*()_+.- — max 100 chars
     */
    public static String validateReferralCode(String code) {
        if (code.length() > 100) {
            throw new AscottApiException('referralCode exceeds 100 characters',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        if (!Pattern.compile('^[a-zA-Z0-9!@#$%^*()_+.\\-]+$').matcher(code).matches()) {
            throw new AscottApiException('referralCode contains invalid character(s)',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        return code;
    }

    /** Mobile number format: +<countrycode>|<number> e.g. +65|86122031 */
    public static String validateMobileNumber(String mobile) {
        if (!Pattern.compile('^\\+[0-9]+\\|[0-9]+$').matcher(mobile).matches()) {
            throw new AscottApiException(
                'mobileNumber must be in format +<countrycode>|<number> e.g. +65|86122031',
                AscottApiException.ErrorCategory.VALIDATION_ERROR);
        }
        return mobile;
    }
}
