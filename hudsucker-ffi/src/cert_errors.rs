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
    /// The template should contain placeholders: {host} and {error_type}
    pub html_template: String,
}

impl CertErrorHandler {
    pub fn new(proxy_id: usize, html_template: String) -> Self {
        Self {
            base_handler: crate::CallbackHandler { proxy_id },
            bypassed_hosts: Arc::new(Mutex::new(HashSet::new())),
            html_template,
        }
    }

    /// Generate the certificate error page by substituting placeholders in the template
    fn generate_cert_error_page(&self, error_type: &str) -> String {
        self.html_template
            .replace("{error_type}", error_type)
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
        
        if let Some(error_type) = Self::parse_cert_error(&err) {
            eprintln!("DEBUG: Parsed as cert error - type: {}", error_type);
            
            // Generate custom error page
            let html = self.generate_cert_error_page(&error_type);
            
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