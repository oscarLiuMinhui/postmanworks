/**
 * AscottApiResponse
 *
 * Typed wrapper for all Ascott API responses.
 * Isolates JSON deserialization in one place so callers
 * work with typed fields rather than raw maps.
 *
 * Spec ref: ASR_Loyalty_CRM_Interface_Specifications__SalesForce_BD v1.0.0
 */
public class AscottApiResponse {

    // ── Common fields ──────────────────────────────────────────────────
    public Boolean success       { get; private set; }  // true when status = "success"
    public Integer httpStatus    { get; private set; }
    public String  correlationId { get; private set; }  // echoed from X-Correlation-Id

    // ── Register response fields (spec p.4) ────────────────────────────
    public String  registrationStatus { get; private set; } // "success"
    public String  autoActivated      { get; private set; } // "Yes" or "No"
    public String  memberId           { get; private set; } // present for PARTIAL/BY_REFERRAL/JOINANDBOOK

    // ── checkUserExist response fields (spec p.6) ──────────────────────
    public Boolean userExists    { get; private set; }
    public Boolean userActivated { get; private set; }
    public String  memberIdFound { get; private set; }
    public String  tierCode      { get; private set; }
    public String  accountType   { get; private set; } // "member" | "representative"

    // ── Error fields ───────────────────────────────────────────────────
    public String errorCode    { get; private set; }
    public String errorMessage { get; private set; }

    private AscottApiResponse() {}

    /**
     * Parses an HttpResponse from any Ascott API endpoint.
     * Throws AscottApiException for non-2xx responses.
     *
     * Security: never log or expose responseBody directly.
     */
    public static AscottApiResponse fromHttpResponse(HttpResponse res) {
        Integer status = res.getStatusCode();

        if (status != 200) {
            throw AscottApiException.fromResponse(status, res.getBody());
        }

        AscottApiResponse result = new AscottApiResponse();
        result.httpStatus    = status;
        result.correlationId = res.getHeader('X-Correlation-Id');

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            // Register response — API wraps fields under "profile" key
            Map<String, Object> reg = body.containsKey('profile')
                ? (Map<String, Object>) body.get('profile')
                : body;
            if (reg.containsKey('status')) {
                result.registrationStatus = (String) reg.get('status');
                result.success            = 'success'.equalsIgnoreCase(result.registrationStatus);
                result.autoActivated      = (String) reg.get('auto-activated');
                result.memberId           = (String) reg.get('memberId');
            }

            // checkUserExist response
            if (body.containsKey('exist')) {
                result.success       = true;
                result.userExists    = 'true'.equalsIgnoreCase(String.valueOf(body.get('exist')));
                result.userActivated = 'true'.equalsIgnoreCase(String.valueOf(body.get('activated')));
                result.memberIdFound = (String) body.get('memberId');
                Object tc = body.get('tierCode');
                result.tierCode      = tc == null ? null : String.valueOf(tc);
                result.accountType   = (String) body.get('accountType');
            }
        } catch (Exception e) {
            throw new AscottApiException(
                'Failed to parse Ascott response',
                AscottApiException.ErrorCategory.UNKNOWN
            );
        }

        return result;
    }
}
