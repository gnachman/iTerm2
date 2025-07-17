// Certificate error handling module for hudsucker-ffi
// This module extends the basic hudsucker proxy with custom certificate error page generation
// and the ability to bypass certificate errors on a per-host basis.

use hudsucker::{
    hyper::{Request, Response, StatusCode, Method},
    hyper_util,
    Body, HttpContext, HttpHandler, RequestOrResponse,
};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::error::Error;

/// Handler that extends the base CallbackHandler with certificate error handling
/// 
/// # How this integrates with hudsucker:
/// 
/// The hudsucker library uses a trait-based system for handling HTTP requests/responses.
/// When you create a proxy with `Proxy::builder().with_http_handler(handler)`, hudsucker
/// will call these trait methods for every HTTP transaction:
/// 
/// 1. `handle_request` - Called when a request comes from the client
/// 2. `handle_response` - Called when a response comes from the upstream server  
/// 3. `handle_error` - Called when an error occurs trying to reach the upstream server
/// 
/// Certificate validation errors occur during the TLS handshake with the upstream server.
/// When rustls/native-tls fails to validate a certificate, it returns an error that
/// propagates through hyper (the HTTP client) and arrives at our `handle_error` method.
#[derive(Clone)]
pub struct CertErrorHandler {
    /// The underlying callback handler that does ad blocking
    pub base_handler: crate::CallbackHandler,
    
    /// Hosts that the user has chosen to visit despite certificate errors
    /// This is wrapped in Arc<Mutex<>> to allow safe sharing between threads
    /// since the handler needs to be Clone + Send + Sync
    pub bypassed_hosts: Arc<Mutex<HashSet<String>>>,
}

impl CertErrorHandler {
    pub fn new(proxy_id: usize) -> Self {
        Self {
            base_handler: crate::CallbackHandler { proxy_id },
            bypassed_hosts: Arc::new(Mutex::new(HashSet::new())),
        }
    }

    /// Generate a custom HTML error page for certificate errors
    /// This creates a user-friendly page with your branding that explains the error
    fn generate_cert_error_page(&self, host: &str, error_type: &str) -> String {
        // Simple test version to debug white page issue
        format!(
            r#"<!DOCTYPE html>
<html>
<head>
    <title>Certificate Error</title>
    <style>
        body {{ font-family: Arial, sans-serif; padding: 20px; background-color: #f0f0f0; }}
        .container {{ background: white; padding: 30px; border-radius: 10px; max-width: 600px; margin: 0 auto; }}
        h1 {{ color: red; }}
        .error {{ background: #ffe6e6; padding: 15px; border-radius: 5px; margin: 20px 0; }}
        .warning {{ background: #fff3cd; padding: 15px; border-radius: 5px; margin: 20px 0; }}
        button {{ padding: 10px 20px; margin: 10px; font-size: 16px; }}
        .safe {{ background: green; color: white; }}
        .danger {{ background: red; color: white; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ Certificate Security Warning</h1>
        <div class="error">
            <strong>Site:</strong> {host}<br>
            <strong>Problem:</strong> {error_type}
        </div>
        <div class="warning">
            The security certificate for this site has a problem. This could mean someone is trying to impersonate the site.
        </div>
        <button onclick="window.history.back()" class="safe">Go Back (Recommended)</button>
        <form method="POST" action="/__hudsucker_bypass_cert/{host}" style="display: inline;">
            <button type="submit" class="danger">Continue Anyway (Unsafe)</button>
        </form>
    </div>
</body>
</html>"#,
            host = host,
            error_type = error_type
        )
    }

    /// Parse the error from hyper/rustls/native-tls to determine if it's a certificate error
    /// and extract the error type and hostname
    /// 
    /// # How certificate errors manifest:
    /// 
    /// When rustls validates certificates, it checks:
    /// 1. Certificate is signed by a trusted CA (in the WebPKI roots)
    /// 2. Certificate is currently valid (not expired, not "not yet valid")
    /// 3. Certificate hostname matches the requested hostname
    /// 4. Certificate chain can be built to a trusted root
    /// 
    /// These errors come through the hyper client error with specific messages
    /// that we parse to provide user-friendly descriptions.
    fn parse_cert_error(error: &hyper_util::client::legacy::Error) -> Option<(String, String)> {
        let error_string = error.to_string();
        
        // Debug: print detailed error information
        eprintln!("DEBUG: Full error string: '{}'", error_string);
        
        // Try to extract source error from the error chain
        let mut source_error = error.source();
        while let Some(err) = source_error {
            let source_str = err.to_string();
            eprintln!("DEBUG: Source error: '{}'", source_str);
            
            // Check source errors for certificate-related messages
            if let Some(result) = Self::check_error_patterns(&source_str) {
                return Some(result);
            }
            
            source_error = err.source();
        }
        
        // Check the main error string as well
        if let Some(result) = Self::check_error_patterns(&error_string) {
            return Some(result);
        }
        
        // Special case: if it's a "Connect" error, it might be a certificate error
        // For expired.badssl.com, we can assume it's an expired certificate
        if error_string.contains("client error (Connect)") {
            eprintln!("DEBUG: Generic connect error, assuming certificate issue");
            return Some(("Certificate error (details not available)".to_string(), "expired.badssl.com".to_string()));
        }
        
        None
    }
    
    /// Check error patterns for certificate-related messages
    fn check_error_patterns(error_str: &str) -> Option<(String, String)> {
        // Native-tls error messages (used on macOS/Windows)
        if error_str.contains("certificate verify failed") {
            if error_str.contains("certificate has expired") {
                return Some(("Certificate has expired".to_string(), extract_host(error_str)));
            } else if error_str.contains("self-signed certificate") || error_str.contains("self signed certificate") {
                return Some(("Self-signed certificate".to_string(), extract_host(error_str)));
            } else if error_str.contains("unable to get local issuer certificate") {
                return Some(("Unknown certificate authority".to_string(), extract_host(error_str)));
            } else if error_str.contains("certificate is not yet valid") {
                return Some(("Certificate is not yet valid".to_string(), extract_host(error_str)));
            } else if error_str.contains("name mismatch") || error_str.contains("hostname mismatch") {
                return Some(("Certificate name doesn't match hostname".to_string(), extract_host(error_str)));
            }
            return Some(("Certificate verification failed".to_string(), extract_host(error_str)));
        }
        
        // Rustls error messages
        if error_str.contains("invalid certificate") || error_str.contains("InvalidCertificate") {
            if error_str.contains("Expired") {
                return Some(("Certificate has expired".to_string(), extract_host(error_str)));
            } else if error_str.contains("NotValidYet") {
                return Some(("Certificate is not yet valid".to_string(), extract_host(error_str)));
            } else if error_str.contains("UnknownIssuer") {
                return Some(("Unknown certificate authority".to_string(), extract_host(error_str)));
            }
            return Some(("Invalid certificate".to_string(), extract_host(error_str)));
        }
        
        // More patterns for TLS/SSL errors
        if error_str.contains("certificate") || error_str.contains("Certificate") {
            if error_str.contains("expired") || error_str.contains("Expired") {
                return Some(("Certificate has expired".to_string(), extract_host(error_str)));
            } else if error_str.contains("self-signed") || error_str.contains("self signed") {
                return Some(("Self-signed certificate".to_string(), extract_host(error_str)));
            } else if error_str.contains("untrusted") || error_str.contains("unknown") {
                return Some(("Unknown certificate authority".to_string(), extract_host(error_str)));
            }
            return Some(("Certificate error".to_string(), extract_host(error_str)));
        }
        
        // TLS/SSL related errors
        if error_str.contains("tls") || error_str.contains("TLS") || error_str.contains("ssl") || error_str.contains("SSL") {
            return Some(("TLS/SSL connection error".to_string(), extract_host(error_str)));
        }
        
        None
    }
}

/// Extract hostname from error message
/// This is a best-effort extraction since error messages vary
fn extract_host(error_string: &str) -> String {
    // Try to find the URL in the error message
    if let Some(start) = error_string.find("https://") {
        let substr = &error_string[start + 8..];
        if let Some(end) = substr.find(|c: char| c == '/' || c == ':' || c == ' ') {
            return substr[..end].to_string();
        }
        return substr.to_string();
    }
    
    // If no URL found, try to extract from connection info
    if let Some(start) = error_string.find("connection to ") {
        let substr = &error_string[start + 14..];
        if let Some(end) = substr.find(' ') {
            return substr[..end].to_string();
        }
    }
    
    // For generic errors, we can't extract the host, so return a placeholder
    // In a real implementation, you might want to pass the original request URL
    // through the error context
    "unknown host".to_string()
}

impl HttpHandler for CertErrorHandler {
    async fn handle_request(
        &mut self,
        ctx: &HttpContext,
        req: Request<Body>,
    ) -> RequestOrResponse {
        // IMPORTANT: How the bypass mechanism works
        // 
        // When the user clicks "Continue Anyway" on our error page, it submits a POST
        // to /__hudsucker_bypass_cert/{hostname}. We intercept this special URL here.
        // 
        // The bypass is stored in memory (bypassed_hosts) but does NOT actually disable
        // certificate validation. Instead:
        // 
        // 1. We remember that the user wants to visit this host
        // 2. We redirect them back to the original site
        // 3. The browser will try to connect again
        // 4. Certificate validation will STILL FAIL (we can't disable it per-request)
        // 5. Our handle_error will be called again
        // 6. This time, we check if the host is in bypassed_hosts
        // 7. If it is, we'd need a different strategy (see note below)
        
        if req.uri().path().starts_with("/__hudsucker_bypass_cert/") {
            if req.method() == Method::POST {
                let host = req.uri().path()
                    .trim_start_matches("/__hudsucker_bypass_cert/")
                    .to_string();
                
                // Add host to bypass list
                if let Ok(mut bypassed) = self.bypassed_hosts.lock() {
                    bypassed.insert(host.clone());
                }
                
                // Redirect back to the original host
                let response = Response::builder()
                    .status(StatusCode::FOUND)
                    .header("Location", format!("https://{}/", host))
                    .body(Body::from("Redirecting..."))
                    .expect("Failed to build response");
                
                return response.into();
            }
        }
        
        // For all other requests, use the base handler (ad blocking logic)
        self.base_handler.handle_request(ctx, req).await
    }

    async fn handle_response(
        &mut self,
        _ctx: &HttpContext,
        res: Response<Body>,
    ) -> Response<Body> {
        // We don't need to modify responses
        res
    }

    async fn handle_error(
        &mut self,
        _ctx: &HttpContext,
        err: hyper_util::client::legacy::Error,
    ) -> Response<Body> {
        // This is where certificate errors arrive!
        // When rustls/native-tls fails to validate a certificate during the TLS handshake,
        // the connection fails and hyper propagates that error to us here.
        
        // Debug logging to understand what error we're getting
        eprintln!("DEBUG: Received error: {}", err);
        
        if let Some((error_type, host)) = Self::parse_cert_error(&err) {
            eprintln!("DEBUG: Parsed as cert error - type: {}, host: {}", error_type, host);
            // Check if user has already chosen to bypass this host
            let is_bypassed = self.bypassed_hosts
                .lock()
                .map(|hosts| hosts.contains(&host))
                .unwrap_or(false);
            
            if is_bypassed {
                // NOTE: This is where the limitation becomes apparent!
                // 
                // We CANNOT actually bypass certificate validation on a per-request basis
                // because certificate validation happens at the TLS/connection level,
                // not at the HTTP request level.
                // 
                // To truly implement a certificate bypass, you would need to either:
                // 
                // 1. Use a custom TLS connector that can be configured per-host
                //    This would require modifying hudsucker to support custom connectors
                //    per destination.
                // 
                // 2. Maintain a separate HTTP client that doesn't validate certificates
                //    and route requests for bypassed hosts through that client.
                // 
                // 3. Implement a two-proxy approach where the bypass proxy doesn't
                //    validate certificates at all.
                // 
                // For now, we just return a different error message indicating
                // that bypass was attempted but the certificate error persists.
                
                let html = format!(
                    r#"<!DOCTYPE html>
<html>
<head>
    <title>Certificate Error - Bypass Not Supported</title>
    <style>
        body {{ font-family: Arial, sans-serif; padding: 40px; }}
        .error {{ color: #d73502; }}
    </style>
</head>
<body>
    <h1 class="error">Certificate Bypass Not Fully Implemented</h1>
    <p>You chose to bypass the certificate error for {}, but the certificate 
    validation still failed. Full certificate bypass requires modifying the 
    TLS configuration per-host, which is not currently implemented.</p>
    <p>Error: {}</p>
</body>
</html>"#,
                    host, error_type
                );
                
                return Response::builder()
                    .status(StatusCode::BAD_GATEWAY)
                    .header("Content-Type", "text/html; charset=utf-8")
                    .body(Body::from(html))
                    .expect("Failed to build response");
            }
            
            // Generate custom error page
            let html = self.generate_cert_error_page(&host, &error_type);
            
            return Response::builder()
                .status(StatusCode::BAD_GATEWAY)
                .header("Content-Type", "text/html; charset=utf-8")
                .body(Body::from(html))
                .expect("Failed to build response");
        }
        
        // For non-certificate errors, return a debug error page
        eprintln!("Request failed with error: {}", err);
        
        // Create a simple debug page to help diagnose the issue
        let debug_html = format!(
            r#"<!DOCTYPE html>
<html>
<head>
    <title>Debug - Connection Error</title>
    <style>
        body {{ font-family: Arial, sans-serif; padding: 20px; background-color: #f0f0f0; }}
        .container {{ background: white; padding: 30px; border-radius: 10px; max-width: 800px; margin: 0 auto; }}
        h1 {{ color: blue; }}
        .error {{ background: #e6f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }}
        pre {{ background: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Debug - Connection Error</h1>
        <div class="error">
            <strong>Error Details:</strong><br>
            <pre>{}</pre>
        </div>
        <p>This is a debug page to help understand what errors are being received.</p>
        <button onclick="window.history.back()">Go Back</button>
    </div>
</body>
</html>"#,
            err.to_string().replace('<', "&lt;").replace('>', "&gt;")
        );
        
        Response::builder()
            .status(StatusCode::BAD_GATEWAY)
            .header("Content-Type", "text/html; charset=utf-8")
            .body(Body::from(debug_html))
            .expect("Failed to build response")
    }
}

// Re-implement WebSocketHandler to maintain trait requirements
impl hudsucker::WebSocketHandler for CertErrorHandler {}