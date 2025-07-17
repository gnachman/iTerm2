// Certificate error handling module for hudsucker-ffi
// This module extends the basic hudsucker proxy with custom certificate error page generation
// and the ability to bypass certificate errors on a per-host basis.

use hudsucker::{
    hyper::{Request, Response, StatusCode, Method},
    hyper_util,
    rustls,
    Body, HttpContext, HttpHandler, RequestOrResponse,
};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::error::Error;
use std::time::{SystemTime, Duration};

/// Information about the current valid bypass token
#[derive(Clone, Debug)]
struct BypassToken {
    /// The token string
    token: String,
    /// The domain this token is bound to
    domain: String,
    /// When this token expires
    expires_at: SystemTime,
}

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
    
    /// Custom HTML template for certificate error pages
    /// The template should contain placeholders: {error_type}
    pub html_template: String,
    
    /// Insecure HTTP client that accepts all certificates
    /// Used for domains that have been added to the bypass list
    pub insecure_client: Arc<hyper_util::client::legacy::Client<hyper_tls::HttpsConnector<hyper_util::client::legacy::connect::HttpConnector>, Body>>,
    
    /// Current valid bypass token (only one at a time for security)
    pub current_bypass_token: Arc<Mutex<Option<BypassToken>>>,
    
    /// Store the current request URI for hostname extraction during error handling
    pub current_request_uri: Arc<Mutex<Option<hudsucker::hyper::Uri>>>,
}

impl CertErrorHandler {
    pub fn new(proxy_id: usize, html_template: String) -> Self {
        // Create insecure HTTP client that accepts all certificates
        let insecure_client = {
            use hyper_util::client::legacy::connect::HttpConnector;
            use hyper_util::rt::TokioExecutor;
            
            let mut http = HttpConnector::new();
            http.enforce_http(false);
            
            // Create TLS connector that accepts invalid certificates
            let tls = hyper_tls::native_tls::TlsConnector::builder()
                .danger_accept_invalid_certs(true)
                .danger_accept_invalid_hostnames(true)
                .build()
                .expect("Failed to create insecure TLS connector");
            
            let https = hyper_tls::HttpsConnector::from((http, tls.into()));
            Arc::new(hyper_util::client::legacy::Client::builder(TokioExecutor::new()).build(https))
        };
        
        Self {
            base_handler: crate::CallbackHandler { proxy_id },
            bypassed_hosts: Arc::new(Mutex::new(HashSet::new())),
            html_template,
            insecure_client,
            current_bypass_token: Arc::new(Mutex::new(None)),
            current_request_uri: Arc::new(Mutex::new(None)),
        }
    }

    /// Generate the certificate error page by substituting placeholders in the template
    fn generate_cert_error_page(&self, error_type: &str, domain: &str) -> String {
        // Generate a cryptographically secure random secret for this error page
        if let Some(bypass_secret) = self.generate_bypass_secret() {
            // Store the token with expiration (10 minutes from now)
            // This replaces any existing token (only one active at a time)
            let expires_at = SystemTime::now() + Duration::from_secs(10 * 60);
            let token_info = BypassToken { 
                token: bypass_secret.clone(),
                domain: domain.to_string(),
                expires_at,
            };
            
            if let Ok(mut current_token) = self.current_bypass_token.lock() {
                *current_token = Some(token_info);
            }
            
            self.html_template
                .replace("{error_type}", error_type)
                .replace("{bypass_secret}", &bypass_secret)
        } else {
            // Security failure - return error page without bypass option
            self.html_template
                .replace("{error_type}", error_type)
                .replace("{bypass_secret}", "")
        }
    }
    
    /// Generate a cryptographically secure random bypass secret for authentication
    /// Returns None if secure random generation fails (disables bypass behavior)
    fn generate_bypass_secret(&self) -> Option<String> {
        use getrandom::getrandom;
        
        // Generate 32 bytes (256 bits) of cryptographically secure random data
        let mut bytes = [0u8; 32];
        match getrandom(&mut bytes) {
            Ok(()) => {
                // Convert to hex string
                Some(hex::encode(bytes))
            }
            Err(_) => {
                // Security failure - disable bypass behavior entirely
                eprintln!("SECURITY ERROR: Failed to generate cryptographically secure random token. Certificate bypass disabled.");
                None
            }
        }
    }
    
    /// Validate and consume a bypass token (one-time use)
    /// Returns true if the token is valid, not expired, and bound to the correct domain
    pub fn validate_and_consume_bypass_token(&self, token: &str, domain: &str) -> bool {
        let now = SystemTime::now();
        
        if let Ok(mut current_token) = self.current_bypass_token.lock() {
            if let Some(token_info) = current_token.as_ref() {
                // Check if token matches, domain matches, and hasn't expired
                if token_info.token == token && 
                   token_info.domain == domain &&
                   token_info.expires_at > now {
                    // Consume the token (remove it)
                    *current_token = None;
                    return true;
                }
            }
            
            // If token is expired, doesn't match, or domain doesn't match, clear it
            *current_token = None;
        }
        
        false
    }
    
    /// Clear the current bypass token (if any)
    pub fn clear_bypass_token(&self) {
        if let Ok(mut current_token) = self.current_bypass_token.lock() {
            *current_token = None;
        }
    }

    /// Parse the error from hyper/rustls/native-tls to determine if it's a certificate error
    /// and extract the error type
    /// 
    /// # How certificate errors manifest:
    /// 
    /// When rustls validates certificates, it checks:
    /// 1. Certificate is signed by a trusted CA (in the WebPKI roots)
    /// 2. Certificate is currently valid (not expired, not "not yet valid")
    /// 3. Certificate hostname matches the requested hostname
    /// 4. Certificate chain can be built to a trusted root
    /// 
    /// These errors come through the hyper client error, and we use type-based
    /// pattern matching instead of string parsing for reliability.
    fn parse_cert_error(error: &hyper_util::client::legacy::Error) -> Option<String> {
        eprintln!("DEBUG: Analyzing error: {}", error);
        
        // Walk the error chain and check for specific error types
        let mut source_error = error.source();
        let mut best_error_message = error.to_string(); // Start with the top-level error
        
        while let Some(err) = source_error {
            eprintln!("DEBUG: Checking source error type: {}", err);
            
            // Always update to the more specific error message as we go deeper
            best_error_message = err.to_string();
            
            // Check for rustls-specific certificate errors
            if let Some(rustls_error) = err.downcast_ref::<rustls::Error>() {
                eprintln!("DEBUG: Found rustls error: {:?}", rustls_error);
                if let Some(result) = Self::classify_rustls_error(rustls_error) {
                    return Some(result);
                }
            }
            
            source_error = err.source();
        }
        
        // For any connection error that we can't classify, use the most specific error message
        // from the deepest part of the error chain
        Some(best_error_message)
    }
    
    /// Classify rustls-specific errors into user-friendly messages
    fn classify_rustls_error(error: &rustls::Error) -> Option<String> {
        use rustls::Error as RustlsError;
        
        match error {
            RustlsError::InvalidCertificate(cert_error) => {
                use rustls::CertificateError;
                let error_msg = match cert_error {
                    CertificateError::Expired => "Certificate has expired",
                    CertificateError::NotValidYet => "Certificate is not yet valid",
                    CertificateError::UnknownIssuer => "Unknown certificate authority",
                    CertificateError::BadSignature => "Invalid certificate signature",
                    CertificateError::NotValidForName => "Certificate name doesn't match hostname",
                    CertificateError::UnhandledCriticalExtension => "Unsupported certificate extension",
                    CertificateError::InvalidPurpose => "Certificate not valid for this purpose",
                    _ => "Certificate validation error",
                };
                Some(error_msg.to_string())
            }
            RustlsError::NoCertificatesPresented => {
                Some("No certificate presented".to_string())
            }
            RustlsError::UnsupportedNameType => {
                Some("Unsupported certificate name type".to_string())
            }
            RustlsError::DecryptError => {
                Some("TLS decryption error".to_string())
            }
            RustlsError::PeerIncompatible(_) => {
                Some("TLS protocol incompatibility".to_string())
            }
            _ => {
                // For unknown rustls errors, include the actual error details
                Some(format!("TLS error: {}", error))
            }
        }
    }
}


impl HttpHandler for CertErrorHandler {
    async fn handle_request(
        &mut self,
        ctx: &HttpContext,
        req: Request<Body>,
    ) -> RequestOrResponse {
        // Store the current request URI for hostname extraction during error handling
        if let Ok(mut current_uri) = self.current_request_uri.lock() {
            *current_uri = Some(req.uri().clone());
        }
        
        // Handle bypass certificate requests
        if req.uri().path().starts_with("/__hudsucker_bypass_cert") {
            if req.method() == Method::POST {
                // Extract hostname from the Referer header if available
                let host = if let Some(referer) = req.headers().get("referer") {
                    if let Ok(referer_str) = referer.to_str() {
                        if let Ok(referer_uri) = referer_str.parse::<hudsucker::hyper::Uri>() {
                            referer_uri.host().unwrap_or("unknown").to_string()
                        } else {
                            "unknown".to_string()
                        }
                    } else {
                        "unknown".to_string()
                    }
                } else {
                    "unknown".to_string()
                };
                
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
        
        // Check if this request is for a bypassed host
        if let Some(host) = req.uri().host() {
            let host_string = host.to_string();
            let is_bypassed = self.bypassed_hosts
                .lock()
                .map(|hosts| hosts.contains(&host_string))
                .unwrap_or(false);
            
            if is_bypassed {
                // Make the request using the insecure client
                eprintln!("DEBUG: Making insecure request to bypassed host: {}", host_string);
                
                // Create new request for the insecure client
                let mut new_req = Request::builder()
                    .method(req.method())
                    .uri(req.uri().clone());
                
                // Copy headers
                for (key, value) in req.headers() {
                    new_req = new_req.header(key, value);
                }
                
                let new_req = new_req.body(req.into_body()).expect("Failed to build request");
                
                // Make the request with the insecure client
                match self.insecure_client.request(new_req).await {
                    Ok(response) => {
                        eprintln!("DEBUG: Insecure request succeeded for {}", host_string);
                        return response.map(Body::from).into();
                    }
                    Err(e) => {
                        eprintln!("DEBUG: Insecure request failed for {}: {}", host_string, e);
                        // Fall through to normal handling - but we consumed the request!
                        // Return an error response instead
                        let error_response = Response::builder()
                            .status(StatusCode::BAD_GATEWAY)
                            .body(Body::from("Insecure request failed"))
                            .expect("Failed to build error response");
                        return error_response.into();
                    }
                }
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
        
        if let Some(error_type) = Self::parse_cert_error(&err) {
            eprintln!("DEBUG: Parsed as cert error - type: {}", error_type);
            
            // Extract hostname from the stored request URI
            let hostname = if let Ok(current_uri) = self.current_request_uri.lock() {
                current_uri.as_ref()
                    .and_then(|uri| uri.authority())
                    .map(|auth| auth.host().to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            } else {
                "unknown".to_string()
            };
            
            eprintln!("DEBUG: Certificate error for hostname: {}", hostname);
            
            // Generate custom error page with domain binding
            let html = self.generate_cert_error_page(&error_type, &hostname);
            
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