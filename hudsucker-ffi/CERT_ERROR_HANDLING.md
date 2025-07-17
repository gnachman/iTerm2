# Certificate Error Handling in hudsucker-ffi

This document explains how to implement custom certificate error pages using the hudsucker-ffi wrapper library.

## Overview

The `hudsucker-ffi` library now provides enhanced certificate error handling that allows you to:

1. **Intercept certificate validation errors** before they reach the browser
2. **Display custom-branded error pages** instead of generic browser warnings
3. **Provide an escape hatch** for users to bypass certificate errors (with limitations)

## How It Works

### Integration with hudsucker

The hudsucker library uses a trait-based architecture where you implement the `HttpHandler` trait:

```rust
pub trait HttpHandler {
    fn handle_request(&mut self, ctx: &HttpContext, req: Request<Body>) -> RequestOrResponse;
    fn handle_response(&mut self, ctx: &HttpContext, res: Response<Body>) -> Response<Body>;
    fn handle_error(&mut self, ctx: &HttpContext, err: hyper_util::client::legacy::Error) -> Response<Body>;
}
```

**Certificate errors reach us through the `handle_error` method**:

1. When a client requests `https://example.com`, hudsucker establishes a TLS connection to the upstream server
2. If the certificate is invalid (expired, self-signed, etc.), the rustls/native-tls library fails during the TLS handshake
3. This failure propagates through the hyper HTTP client as a connection error
4. Hudsucker calls our `handle_error` method with the error details
5. We parse the error to determine if it's certificate-related and generate a custom response

### Certificate Error Detection

The `CertErrorHandler` parses error messages to identify certificate-specific issues:

```rust
fn parse_cert_error(error: &hyper_util::client::legacy::Error) -> Option<(String, String)> {
    let error_string = error.to_string();
    
    // Native-tls error patterns
    if error_string.contains("certificate verify failed") {
        if error_string.contains("certificate has expired") {
            return Some(("Certificate has expired".to_string(), extract_host(&error_string)));
        }
        // ... more patterns
    }
    
    // Rustls error patterns
    if error_string.contains("InvalidCertificate") {
        if error_string.contains("Expired") {
            return Some(("Certificate has expired".to_string(), extract_host(&error_string)));
        }
        // ... more patterns
    }
    
    None
}
```

## Usage

### Basic Usage

Use the new `hudsucker_create_proxy_with_cert_errors` function instead of `hudsucker_create_proxy`:

```c
#include "hudsucker_ffi.h"

// Your existing ad blocker callback
bool ad_blocker_callback(const char* url, const char* method, void* user_data) {
    // Your ad blocking logic here
    return true;  // Allow or block the request
}

int main() {
    // Generate CA certificate
    char* ca_cert = NULL;
    char* ca_key = NULL;
    hudsucker_generate_ca_cert(&ca_cert, &ca_key);
    
    // Create proxy with certificate error handling
    HudsuckerProxy* proxy = NULL;
    HudsuckerError err = hudsucker_create_proxy_with_cert_errors(
        "127.0.0.1:8080",
        ca_cert,
        ca_key,
        ad_blocker_callback,
        NULL,
        &proxy
    );
    
    if (err != HudsuckerError_Success) {
        printf("Failed to create proxy: %d\n", err);
        return 1;
    }
    
    // Your proxy is now running with certificate error handling
    // ... rest of your program
}
```

### Custom Branding

The error page can be customized by modifying the `generate_cert_error_page` function in `src/cert_errors.rs`:

```rust
fn generate_cert_error_page(&self, host: &str, error_type: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html>
<head>
    <title>My Custom Certificate Error</title>
    <style>
        /* Your custom CSS here */
        .logo {{ 
            /* Your branding styles */
        }}
    </style>
</head>
<body>
    <div class="error-container">
        <div class="logo">Your Company Logo</div>
        <h1>Certificate Security Warning</h1>
        <div class="host">Site: {host}</div>
        <div class="error-type">Problem: {error_type}</div>
        
        <!-- Your custom content -->
        
        <div class="actions">
            <button onclick="window.history.back()">Go Back</button>
            <form method="POST" action="/__hudsucker_bypass_cert/{host}">
                <button type="submit">Continue Anyway</button>
            </form>
        </div>
    </div>
</body>
</html>"#,
        host = host,
        error_type = error_type
    )
}
```

## Certificate Error Types

The system recognizes these certificate error types:

- **Certificate has expired** - The certificate's validity period has ended
- **Certificate is not yet valid** - The certificate's validity period hasn't started
- **Self-signed certificate** - The certificate is self-signed and not trusted
- **Unknown certificate authority** - The certificate is signed by an unknown/untrusted CA
- **Certificate name doesn't match hostname** - The certificate's subject doesn't match the requested hostname
- **Certificate verification failed** - Generic certificate validation failure

## Bypass Mechanism and Limitations

### How Bypass Works

When a user clicks "Continue Anyway" on the error page:

1. Browser submits a POST request to `/__hudsucker_bypass_cert/{hostname}`
2. Our handler intercepts this request and adds the hostname to a bypass list
3. Handler redirects the browser back to the original site
4. Browser attempts to connect again, certificate validation fails again
5. Handler checks if the hostname is in the bypass list

### Important Limitation

**The bypass mechanism is not fully implemented** due to a fundamental limitation:

Certificate validation happens at the **TLS connection level**, not the HTTP request level. We cannot disable certificate validation for specific requests after the proxy is created.

To implement true certificate bypass, you would need:

1. **Per-host TLS configuration** - Create separate HTTP clients with different certificate validation settings
2. **Dynamic connector switching** - Route requests to different connectors based on bypass status
3. **Proxy architecture changes** - Modify hudsucker to support per-destination TLS configuration

### Current Bypass Behavior

When bypass is attempted, the system displays a message explaining that full bypass is not implemented:

```html
<h1>Certificate Bypass Not Fully Implemented</h1>
<p>You chose to bypass the certificate error for example.com, but the certificate 
validation still failed. Full certificate bypass requires modifying the 
TLS configuration per-host, which is not currently implemented.</p>
```

## Building and Testing

### Build the Library

```bash
cd hudsucker-ffi
cargo build --release
```

### Generate C Header

```bash
cbindgen --config cbindgen.toml --crate hudsucker_ffi --output hudsucker_ffi.h
```

### Test Certificate Errors

Use these test sites to verify certificate error handling:

- **Self-signed certificate**: https://self-signed.badssl.com/
- **Expired certificate**: https://expired.badssl.com/
- **Untrusted root CA**: https://untrusted-root.badssl.com/
- **Wrong hostname**: https://wrong.host.badssl.com/

### Browser Configuration

1. Install the generated CA certificate in your browser/system trust store
2. Configure your browser to use `127.0.0.1:8080` as HTTP proxy
3. Visit the test sites above to see custom error pages

## Integration with Your Application

The certificate error handling is designed to work alongside your existing ad blocking logic:

1. **Ad blocking** happens in the `handle_request` method
2. **Certificate errors** are handled in the `handle_error` method
3. Both features work independently and don't interfere with each other

Your existing `HudsuckerRequestCallback` function continues to work exactly as before, but now certificate errors display custom pages instead of generic browser warnings.

## Future Improvements

To implement full certificate bypass, consider:

1. **Multiple HTTP clients** - Create clients with different certificate validation settings
2. **Dynamic routing** - Route requests to appropriate client based on bypass status
3. **User preferences** - Persist bypass decisions across sessions
4. **Certificate pinning** - Allow users to permanently accept specific certificates
5. **Detailed error reporting** - Show certificate details, validity periods, etc.

The current implementation provides a solid foundation for these enhancements while maintaining compatibility with existing code.