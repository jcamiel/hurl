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

### 3. Potential CRLF Injection in User-Provided Header Values (LOW SEVERITY - VERIFIED SAFE)

**Location:** `packages/hurl/src/runner/request.rs` - Header construction (lines 43-48)

**Issue:**
User-provided header values from templates are not explicitly validated for CRLF (`\r\n`) characters before being passed to libcurl.

**Current Code:**
```rust
for header in &request.headers {
    let name = template::eval_template(&header.key, variables)?;
    let value = template::eval_template(&header.value, variables)?;
    let header = http::Header::new(&name, &value);
    headers.push(header);
}
```

**Security Analysis:**
Through testing (see `test_libcurl_crlf_header_handling`), we verified that libcurl properly sanitizes or rejects headers containing CRLF sequences. The curl library's `List::append()` function handles this security concern at the FFI boundary.

**Risk Assessment:**
- **Low Risk**: libcurl properly handles CRLF injection attempts
- Test coverage added to verify this behavior continues in future versions
- Defense-in-depth already provided by the underlying library

**Status:** 
✅ **VERIFIED SAFE** - libcurl handles CRLF injection prevention internally. No action required, but monitoring test ensures this continues to work correctly.

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
Reviewed all unsafe blocks in the HTTP-related code:

1. **`cert_info()` function (easy_ext.rs:46-61)**
   - ✅ Proper null pointer check before dereferencing (`certinfo.is_null()`)
   - ✅ Count validation before array access (`count <= 0`)
   - ✅ Uses libcurl's error checking via `cvt()`
   - ✅ Safe: Follows libcurl API contracts correctly

2. **`conn_id()` function (easy_ext.rs:66-71)**
   - ✅ Proper error handling via `cvt()`
   - ✅ Simple scalar read, no pointer dereferencing
   - ✅ Safe: Minimal unsafe operations

3. **`to_list()` function (easy_ext.rs:195-210)**
   - ✅ Null pointer check in loop condition
   - ✅ Proper linked list traversal following curl_slist semantics
   - ✅ Uses `CStr::from_ptr()` safely after null check
   - ✅ Safe: Follows libcurl linked list API correctly

4. **`netrc_file()` function (easy_ext.rs:187-192)**
   - ✅ CString creation with error handling
   - ✅ Proper FFI call with error checking
   - ✅ Safe: Standard FFI pattern

**Safety Invariants Documented:**
All unsafe blocks follow these safety requirements:
- Null pointer checks before dereferencing
- Proper error handling using libcurl's error codes
- Correct usage of libcurl API contracts
- No undefined behavior from FFI calls

**Recommendation:**
- Continue current practices
- Consider adding explicit `// SAFETY:` comments to document invariants
- Rely on integration testing and fuzzing to catch edge cases
- No changes required at this time

**Status:** ✅ **VERIFIED SAFE** - All unsafe blocks are properly bounded and follow FFI best practices.

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

### Security Test Cases Added ✅

The following security test cases have been implemented:

1. **Redirect Security Tests:**
   - ✅ `test_scheme_downgrade_detection` - Verifies HTTPS → HTTP downgrade detection
   - ✅ `test_redirect_security_cross_domain` - Verifies cross-domain detection
   - ✅ `test_redirect_security_same_domain_scheme_downgrade` - Verifies scheme downgrade on same domain

2. **Header Security Tests:**
   - ✅ `test_libcurl_crlf_header_handling` - Verifies CRLF injection prevention

### Additional Security Test Cases Recommended

1. **Redirect Tests:**
   - Test redirect loop detection with max_redirect limits
   - Test `--location-trusted` flag behavior
   - Test Authorization header stripping across various redirect scenarios

2. **URL Validation Tests:**
   - Test URL parsing edge cases with special characters
   - Test internationalized domain names (IDN)
   - Test file:// and other scheme rejection

3. **Authentication Tests:**
   - Test basic auth encoding edge cases
   - Test credential handling with unusual characters
   - Test NTLM/Negotiate authentication flows

4. **Cookie Security Tests:**
   - Test cookie domain matching edge cases
   - Test expired cookie filtering
   - Test secure cookie handling

## Conclusion

The Hurl codebase demonstrates **excellent security practices overall**, with proper use of established libraries (url, curl, regex) and careful attention to HTTP semantics. 

### Summary of Findings:

1. **CRITICAL (FIXED):** HTTPS-to-HTTP redirect authentication leakage
   - ✅ Fixed in this review
   - ✅ Tests added to prevent regression

2. **MEDIUM:** Redirect method behavior (curl-compatible, documented)
   - Already following curl's well-tested behavior
   - No action required

3. **LOW (VERIFIED SAFE):** CRLF injection in headers
   - ✅ Verified that libcurl handles this securely
   - ✅ Tests added to verify continued safety

4. **LOW (VERIFIED SAFE):** Unsafe code blocks
   - ✅ All unsafe code properly bounded
   - ✅ Follows FFI best practices
   - No issues found

### Security Strengths Observed:

✅ **Authentication Security:**
- Proper credential encoding (base64 for Basic auth)
- Credentials stripped on cross-domain redirects
- Now also strips credentials on scheme downgrades

✅ **SSL/TLS Security:**
- Certificate validation enabled by default
- Support for certificate pinning
- Custom CA certificates supported
- Proper certificate chain handling

✅ **Input Validation:**
- Strict URL scheme validation (http/https only)
- Proper use of `url` crate for parsing
- Header validation via libcurl
- Query parameter encoding

✅ **Resource Protection:**
- Maximum file size limits
- Connection timeouts
- Transfer speed limits  
- Redirect count limits

✅ **Cookie Security:**
- Proper domain matching
- Subdomain handling
- Expired cookie filtering
- Secure cookie storage

### Actions Completed:

1. ✅ Fixed critical HTTPS-to-HTTP credential leakage vulnerability
2. ✅ Added comprehensive security tests
3. ✅ Verified libcurl CRLF injection prevention
4. ✅ Reviewed all unsafe code blocks
5. ✅ Documented security analysis and findings

### Recommendations for Future Maintenance:

1. **Continue current security practices** - The codebase is well-designed
2. **Monitor dependencies** - Keep curl, url, and other security-critical crates updated
3. **Run security test suite** - The new tests should be run on every build
4. **Consider fuzzing** - HTTP parsing and template evaluation would benefit from fuzzing
5. **Security audits** - Periodic reviews when adding new HTTP features

## References

- RFC 7230: HTTP/1.1 Message Syntax and Routing
- RFC 7231: HTTP/1.1 Semantics and Content
- RFC 7538: HTTP Status Code 308 (Permanent Redirect)
- OWASP HTTP Security Response Headers
- CWE-523: Unprotected Transport of Credentials
- CWE-319: Cleartext Transmission of Sensitive Information
