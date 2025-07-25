// Certificate error handling module for hudsucker-ffi
// This module extends the basic hudsucker proxy with custom certificate error page generation
// and the ability to bypass certificate errors on a per-host basis.

use hudsucker::{
    certificate_authority::CertificateAuthority,
    hyper::{Request, Response, StatusCode, Method},
    hyper_util,
    rustls,
    Body, HttpContext, HttpHandler, RequestOrResponse,
};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::error::Error;
use std::time::{SystemTime, Duration};
use rustls::client::danger::{ServerCertVerifier, ServerCertVerified, HandshakeSignatureValid};
use rustls::crypto::CryptoProvider;
use rustls::ClientConfig;
use rustls::pki_types::{CertificateDer, ServerName as PkiServerName, UnixTime as PkiUnixTime, PrivateKeyDer, PrivatePkcs8KeyDer};
use rustls::ServerConfig;
use hudsucker::rustls::crypto::aws_lc_rs;
use webpki_roots;
use http::uri::Authority;
use moka::future::Cache;
use rand::{thread_rng, Rng};
use rcgen::{
    Certificate, CertificateParams, DistinguishedName, DnType, Ia5String, KeyPair, SanType, ExtendedKeyUsagePurpose,
};
use time::{Duration as TimeDuration, OffsetDateTime};

// Certificate constants (copied from hudsucker since they're private)
const TTL_SECS: i64 = 365 * 24 * 60 * 60;
const NOT_BEFORE_OFFSET: i64 = 60;
const CACHE_TTL: u64 = TTL_SECS as u64 / 2;

/// Custom certificate verifier that bypasses verification for domains in the bypass list
/// This is called during TLS handshake and allows us to make per-domain security decisions
#[derive(Debug)]
pub struct BypassAwareVerifier {
    /// The default verifier to use for non-bypassed domains
    default_verifier: Arc<dyn ServerCertVerifier>,
    /// Domains that should bypass certificate verification
    bypass_list: Arc<Mutex<HashSet<String>>>,
}

impl BypassAwareVerifier {
    pub fn new(bypass_list: Arc<Mutex<HashSet<String>>>) -> Self {
        // Use webpki verifier as the default
        let mut root_store = rustls::RootCertStore::empty();
        root_store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        
        let default_verifier = rustls::client::WebPkiServerVerifier::builder(Arc::new(root_store))
            .build()
            .unwrap();
        
        Self {
            default_verifier,
            bypass_list,
        }
    }
}

impl ServerCertVerifier for BypassAwareVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &PkiServerName<'_>,
        ocsp_response: &[u8],
        now: PkiUnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        // Extract hostname from server_name
        let hostname = server_name.to_str();
        
        // Check if this hostname is in the bypass list
        match self.bypass_list.lock() {
            Ok(bypass_hosts) => {
                if bypass_hosts.contains(&hostname.to_string()) {
                    return Ok(ServerCertVerified::assertion());
                }
            }
            Err(_) => {
                // Fall back to default verification if lock fails
            }
        }
        
        // Use default verification for non-bypassed hostnames
        // Use default verification for non-bypassed hostnames
        self.default_verifier.verify_server_cert(
            end_entity,
            intermediates,
            server_name,
            ocsp_response,
            now,
        )
    }
    
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        self.default_verifier.verify_tls12_signature(message, cert, dss)
    }
    
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        self.default_verifier.verify_tls13_signature(message, cert, dss)
    }
    
    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.default_verifier.supported_verify_schemes()
    }
}

/// Custom certificate authority that generates server certificates with proper Extended Key Usage
/// This fixes the issue where hudsucker's default RcgenAuthority doesn't include ServerAuth EKU
pub struct EKUFixedRcgenAuthority {
    key_pair: KeyPair,
    ca_cert: Certificate,
    private_key: PrivateKeyDer<'static>,
    cache: Cache<Authority, Arc<ServerConfig>>,
    provider: Arc<CryptoProvider>,
}

impl EKUFixedRcgenAuthority {
    /// Creates a new rcgen authority with proper Extended Key Usage support
    pub fn new(
        key_pair: KeyPair,
        ca_cert: Certificate,
        cache_size: u64,
        provider: CryptoProvider,
    ) -> Self {
        let private_key = PrivateKeyDer::from(PrivatePkcs8KeyDer::from(key_pair.serialize_der()));

        Self {
            key_pair,
            ca_cert,
            private_key,
            cache: Cache::builder()
                .max_capacity(cache_size)
                .time_to_live(std::time::Duration::from_secs(CACHE_TTL))
                .build(),
            provider: Arc::new(provider),
        }
    }

    fn gen_cert(&self, authority: &Authority) -> CertificateDer<'static> {
        let mut params = CertificateParams::default();
        params.serial_number = Some(thread_rng().gen::<u64>().into());

        let not_before = OffsetDateTime::now_utc() - TimeDuration::seconds(NOT_BEFORE_OFFSET);
        params.not_before = not_before;
        params.not_after = not_before + TimeDuration::seconds(TTL_SECS);

        let mut distinguished_name = DistinguishedName::new();
        distinguished_name.push(DnType::CommonName, authority.host());
        params.distinguished_name = distinguished_name;

        params.subject_alt_names.push(SanType::DnsName(
            Ia5String::try_from(authority.host()).expect("Failed to create Ia5String"),
        ));

        // Add Extended Key Usage for SSL/TLS server authentication
        params.extended_key_usages = vec![
            ExtendedKeyUsagePurpose::ServerAuth,
        ];

        params
            .signed_by(&self.key_pair, &self.ca_cert, &self.key_pair)
            .expect("Failed to sign certificate")
            .into()
    }
}

impl CertificateAuthority for EKUFixedRcgenAuthority {
    async fn gen_server_config(&self, authority: &Authority) -> Arc<ServerConfig> {
        if let Some(server_cfg) = self.cache.get(authority).await {
            return server_cfg;
        }

        let certs = vec![self.gen_cert(authority)];

        let mut server_cfg = ServerConfig::builder_with_provider(Arc::clone(&self.provider))
            .with_safe_default_protocol_versions()
            .expect("Failed to specify protocol versions")
            .with_no_client_auth()
            .with_single_cert(certs, self.private_key.clone_key())
            .expect("Failed to build ServerConfig");

        server_cfg.alpn_protocols = vec![
            b"h2".to_vec(),        // HTTP/2 support
            b"http/1.1".to_vec(),  // HTTP/1.1 fallback
        ];

        let server_cfg = Arc::new(server_cfg);

        self.cache
            .insert(authority.clone(), Arc::clone(&server_cfg))
            .await;

        server_cfg
    }
}

/// Create a modern CryptoProvider with enhanced TLS capabilities
pub fn create_modern_crypto_provider() -> CryptoProvider {
    aws_lc_rs::default_provider()
}

/// Create a custom ClientConfig that uses our BypassAwareVerifier
/// This is what we'll actually use with the proxy
pub fn create_bypass_aware_client_config(bypass_list: Arc<Mutex<HashSet<String>>>) -> Result<ClientConfig, rustls::Error> {
    // Create our custom verifier
    let custom_verifier = Arc::new(BypassAwareVerifier::new(bypass_list));
    
    // Create the client config with our custom verifier and modern TLS support
    let mut config = ClientConfig::builder_with_provider(Arc::new(aws_lc_rs::default_provider()))
        .with_safe_default_protocol_versions()?
        .dangerous()
        .with_custom_certificate_verifier(custom_verifier)
        .with_no_client_auth();
    
    // Add ALPN protocols to support HTTP/2 and HTTP/1.1
    // This is critical for sites like Google that require HTTP/2
    config.alpn_protocols = vec![
        b"h2".to_vec(),        // HTTP/2
        b"http/1.1".to_vec(),  // HTTP/1.1 fallback
    ];
    
    Ok(config)
}

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
        // Walk the error chain and check for specific error types
        let mut source_error = error.source();
        let mut best_error_message = error.to_string(); // Start with the top-level error
        
        while let Some(err) = source_error {
            // Always update to the more specific error message as we go deeper
            best_error_message = err.to_string();
            
            // Check for rustls-specific certificate errors
            if let Some(rustls_error) = err.downcast_ref::<rustls::Error>() {
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
                // Create new request for the insecure client
                let method = req.method().clone();
                let mut new_req = Request::builder()
                    .method(method.clone())
                    .uri(req.uri().clone());
                
                // Copy headers
                for (key, value) in req.headers() {
                    new_req = new_req.header(key, value);
                }
                
                let new_req = match new_req.body(req.into_body()) {
                    Ok(req) => req,
                    Err(_) => {
                        let error_response = Response::builder()
                            .status(StatusCode::INTERNAL_SERVER_ERROR)
                            .body(Body::from("Failed to build request"))
                            .expect("Failed to build error response");
                        return error_response.into();
                    }
                };
                
                // Make the request with the insecure client
                match self.insecure_client.request(new_req).await {
                    Ok(response) => {
                        return response.map(Body::from).into();
                    }
                    Err(e) => {
                        // Return a detailed error response
                        let error_html = format!(
                            r#"<!DOCTYPE html>
<html>
<head>
    <title>Certificate Bypass Failed</title>
    <style>
        body {{ font-family: Arial, sans-serif; padding: 20px; background-color: #f0f0f0; }}
        .container {{ background: white; padding: 30px; border-radius: 10px; max-width: 800px; margin: 0 auto; }}
        h1 {{ color: #d9534f; }}
        .error {{ background: #f2dede; padding: 15px; border-radius: 5px; margin: 20px 0; }}
        pre {{ background: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Certificate Bypass Failed</h1>
        <div class="error">
            <p>The request to the bypassed domain failed. This usually happens when:</p>
            <ul>
                <li>The server is unreachable</li>
                <li>The server closed the connection</li>
                <li>There's a protocol mismatch</li>
            </ul>
            <strong>Error Details:</strong>
            <pre>{}</pre>
        </div>
        <button onclick="window.history.back()">Go Back</button>
    </div>
</body>
</html>"#,
                            e.to_string().replace('<', "&lt;").replace('>', "&gt;")
                        );
                        
                        let error_response = Response::builder()
                            .status(StatusCode::BAD_GATEWAY)
                            .header("Content-Type", "text/html; charset=utf-8")
                            .body(Body::from(error_html))
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
        
        if let Some(error_type) = Self::parse_cert_error(&err) {
            // Extract hostname from the stored request URI
            let hostname = if let Ok(current_uri) = self.current_request_uri.lock() {
                current_uri.as_ref()
                    .and_then(|uri| uri.authority())
                    .map(|auth| auth.host().to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            } else {
                "unknown".to_string()
            };
            
            // Generate custom error page with domain binding
            let html = self.generate_cert_error_page(&error_type, &hostname);
            
            return Response::builder()
                .status(StatusCode::BAD_GATEWAY)
                .header("Content-Type", "text/html; charset=utf-8")
                .body(Body::from(html))
                .expect("Failed to build response");
        }
        
        // For non-certificate errors, return a debug error page
        
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