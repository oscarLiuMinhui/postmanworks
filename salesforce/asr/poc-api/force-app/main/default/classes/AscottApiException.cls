/**
 * AscottApiException
 *
 * Typed exception for all Ascott API integration failures.
 * Separates Ascott business errors from generic callout failures
 * so callers can react differently (e.g. retry vs. surface to user).
 *
 * Security: Never include raw HTTP response bodies or credentials
 * in exception messages — they propagate to debug logs and UI.
 */
public class AscottApiException extends Exception {

    public enum ErrorCategory {
        AUTH_FAILURE,       // sysToken invalid / AES key mismatch  (HTTP 401 / errorCode 1502)
        VALIDATION_ERROR,   // Bad request params                    (HTTP 400 / errorCode 100x)
        SERVER_ERROR,       // Ascott internal error                 (HTTP 500 / errorCode 1800)
        NETWORK_ERROR,      // Timeout, DNS failure, TLS error
        CRYPTO_ERROR,       // PBKDF2 or AES/GCM failure
        UNKNOWN
    }

    public ErrorCategory category   { get; private set; }
    public String        errorCode  { get; private set; }
    public Integer       httpStatus { get; private set; }

    public AscottApiException(String message, ErrorCategory category) {
        this(message);
        this.category = category;
    }

    public AscottApiException(String message, ErrorCategory category, String errorCode, Integer httpStatus) {
        this(message);
        this.category   = category;
        this.errorCode  = errorCode;
        this.httpStatus = httpStatus;
    }

    /** Factory: parse Ascott error response body into a typed exception. */
    public static AscottApiException fromResponse(Integer httpStatus, String responseBody) {
        String errorCode = 'UNKNOWN';
        String message   = 'Ascott API error (HTTP ' + httpStatus + ')';

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (body.containsKey('errorCode')) errorCode = String.valueOf(body.get('errorCode'));
            if (body.containsKey('message'))   message   = String.valueOf(body.get('message'));
        } catch (Exception e) {
            // Unparseable body — keep defaults, never expose raw body
        }

        ErrorCategory cat = categoryFromHttpStatus(httpStatus, errorCode);
        return new AscottApiException(message, cat, errorCode, httpStatus);
    }

    private static ErrorCategory categoryFromHttpStatus(Integer status, String code) {
        if (status == 401)        return ErrorCategory.AUTH_FAILURE;
        if (status == 400)        return ErrorCategory.VALIDATION_ERROR;
        if (status == 500)        return ErrorCategory.SERVER_ERROR;
        return ErrorCategory.UNKNOWN;
    }
}
