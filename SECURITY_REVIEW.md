# Security Review of Hurl Rust Packages

**Date:** 2025
**Packages Reviewed:** `packages/hurl`, `packages/hurlfmt`, `packages/hurl_core`
**Focus:** HTTP Protocol Logic Errors, Authentication Security, Input Validation

## Executive Summary

This document contains a comprehensive security review of the Hurl HTTP testing tool's core Rust packages. The review focused on potential security vulnerabilities, HTTP protocol logic errors, and secure coding practices.

## Critical Findings

### 1. HTTPS to HTTP Downgrade in Redirects - Authentication/Cookie Leakage (HIGH SEVERITY)

**Location:** `packages/hurl/src/http/client.rs` - `execute_with_redirect()` function (lines 122-134)

**Issue:** 
The current implementation only checks if the hostname changes during redirects when deciding whether to strip sensitive headers (Authorization, Set-Cookie) and user credentials. However, it does NOT check if the scheme changes from HTTPS to HTTP, which could lead to credential leakage over an unencrypted connection.

**Current Code:**
```rust
let host_changed = request_url.host() != redirect_url.host();
if host_changed && !options.follow_location_trusted {
    headers.retain(|h| !h.name_eq(AUTHORIZATION));
    headers.retain(|h| !h.name_eq(SET_COOKIE));
    options.user = None;
}
```

**Problem Scenario:**
1. User makes HTTPS request to `https://example.com` with Authorization header
2. Server responds with 301/302 redirect to `http://example.com/path` (same host, but HTTP)
3. Current code allows Authorization header to be sent over HTTP
4. Credentials are leaked in plaintext over the network

**Security Impact:**
- Credentials (username/password in Authorization header) sent in cleartext
- Session cookies exposed over unencrypted connection
- Man-in-the-middle attacks can intercept sensitive data
- Violates principle of least privilege and defense in depth

**Recommendation:**
Strip sensitive headers when either the hostname changes OR when downgrading from HTTPS to HTTP.

**Fixed Code:**
```rust
let host_changed = request_url.host() != redirect_url.host();
let scheme_downgraded = request_url.raw().starts_with("https://") 
    && redirect_url.raw().starts_with("http://");
if (host_changed || scheme_downgraded) && !options.follow_location_trusted {
    headers.retain(|h| !h.name_eq(AUTHORIZATION));
    headers.retain(|h| !h.name_eq(SET_COOKIE));
    options.user = None;
}
```

## Medium Severity Findings

### 2. Redirect Method Behavior Deviation from HTTP Spec (MEDIUM SEVERITY)

**Location:** `packages/hurl/src/http/client.rs` - `redirect_method()` function (lines 838-846)

**Issue:**
The redirect method implementation converts ALL 301-303 responses to GET, but this doesn't strictly follow RFC 7231/7538 specifications. According to the specs:
- 301/302: Should preserve the method for GET/HEAD, change to GET for others (per common practice)
- 303: Always change to GET
- 307/308: Always preserve the original method

**Current Code:**
```rust
fn redirect_method(response_status: u32, original_method: &Method) -> Method {
    match response_status {
        301..=303 => Method("GET".to_string()),
        _ => original_method.clone(),
    }
}
```

**Note:** The code comment states "This replicates curl's behavior" which is correct. However, this should be clearly documented as it differs slightly from strict RFC compliance.

**Recommendation:**
Add comprehensive documentation explaining the curl-compatible behavior and the rationale for deviation from strict RFC compliance.

## Low Severity Findings

### 3. Use of `unwrap()` in HTTP Code (LOW SEVERITY)

**Location:** Multiple locations in `packages/hurl/src/http/`

**Issue:**
Found 108 instances of `unwrap()` in HTTP-related code. While many are in test code or genuinely safe contexts, some could lead to panics in production if assumptions about data validity are violated.

**Examples:**
- `packages/hurl/src/http/client.rs`: Line 374, 764, 766, 781
- `packages/hurl/src/http/curl_cmd.rs`: Various locations

**Recommendation:**
Review each `unwrap()` usage to ensure:
1. It's in test code OR
2. The invariant being assumed is documented OR
3. Replace with proper error handling where appropriate

### 4. Unsafe Code Usage (LOW SEVERITY)

**Location:** 
- `packages/hurl/src/http/easy_ext.rs` - Multiple unsafe blocks for FFI with libcurl
- `packages/hurl/src/runner/xpath.rs` - FFI with libxml2
- `packages/hurl_core/src/parser/xml.rs` - FFI with libxml2

**Issue:**
The unsafe code is used for Foreign Function Interface (FFI) with C libraries (libcurl, libxml2). This is necessary but requires careful review.

**Analysis:**
- All unsafe blocks appear to be properly scoped and necessary for FFI
- Pointer validity checks are in place (null checks)
- Memory management follows libcurl/libxml2 conventions
- No obvious safety violations detected

**Recommendation:**
- Document safety invariants for each unsafe block
- Consider adding debug assertions for pointer validity
- Continue to rely on fuzzing and testing to catch edge cases

## Good Security Practices Observed

### 1. URL Validation
- Strict validation of URL schemes (only http:// and https:// allowed)
- Proper use of the `url` crate for parsing
- Clear error messages for invalid URLs

### 2. SSL/TLS Configuration
- Support for certificate validation (`ssl_verify_host`, `ssl_verify_peer`)
- Certificate pinning support (`pinned_pub_key`)
- Proper certificate chain caching
- Support for custom CA certificates

### 3. Authentication Security
- Basic authentication properly base64 encoded
- Support for NTLM and Negotiate authentication
- Credentials stripped on cross-domain redirects (with the scheme downgrade issue noted above)

### 4. Input Validation
- Header validation and parsing
- Cookie validation
- Query parameter encoding
- Form data encoding

### 5. Resource Limits
- Maximum file size enforcement
- Connection timeout settings
- Transfer speed limits
- Redirect count limits

### 6. Cookie Security
- Cookie domain matching
- Subdomain handling
- Expired cookie filtering
- Secure cookie storage

## Testing Recommendations

### Security Test Cases Needed

1. **Redirect Tests:**
   - Test HTTPS → HTTP redirect with Authorization header
   - Test HTTPS → HTTP redirect with cookies
   - Test cross-domain redirect behavior
   - Test redirect loop detection

2. **Header Injection Tests:**
   - Test CRLF injection in header values
   - Test null byte injection
   - Test oversized headers

3. **URL Validation Tests:**
   - Test URL parsing edge cases
   - Test special characters in URLs
   - Test internationalized domain names

4. **Authentication Tests:**
   - Test basic auth over HTTP vs HTTPS
   - Test credential stripping on redirects
   - Test malformed credentials

## Conclusion

The Hurl codebase demonstrates good security practices overall, with proper use of established libraries (url, curl, regex) and careful attention to HTTP semantics. The critical finding regarding HTTPS-to-HTTP redirect authentication leakage should be addressed immediately as it could lead to credential exposure in production environments.

The codebase would benefit from:
1. Fixing the scheme downgrade issue in redirects (HIGH priority)
2. Adding comprehensive security test suite
3. Documenting unsafe code blocks with safety invariants
4. Reducing reliance on `unwrap()` in production code paths

## References

- RFC 7230: HTTP/1.1 Message Syntax and Routing
- RFC 7231: HTTP/1.1 Semantics and Content
- RFC 7538: HTTP Status Code 308 (Permanent Redirect)
- OWASP HTTP Security Response Headers
- CWE-523: Unprotected Transport of Credentials
- CWE-319: Cleartext Transmission of Sensitive Information
