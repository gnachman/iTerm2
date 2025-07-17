use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::net::SocketAddr;
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::sync::Mutex;

use hudsucker::{
    certificate_authority::RcgenAuthority,
    hyper::{Request, Response},
    rcgen::{CertificateParams, KeyPair},
    rustls::crypto::aws_lc_rs,
    Body, HttpContext, HttpHandler, Proxy, RequestOrResponse, WebSocketHandler,
};
use once_cell::sync::Lazy;
use tokio::runtime::Runtime;

// Certificate error handling module
mod cert_errors;
use cert_errors::CertErrorHandler;

// Error codes
#[repr(C)]
#[derive(Debug)]
pub enum HudsuckerError {
    Success = 0,
    InvalidParameter = -1,
    ProxyCreationFailed = -2,
    ProxyStartFailed = -3,
    RuntimeError = -4,
    MemoryError = -5,
}

// Opaque handle for the proxy
#[repr(C)]
pub struct HudsuckerProxy {
    _private: [u8; 0],
}

// Callback function type for request handling
// Returns true to allow the request, false to block it
pub type HudsuckerRequestCallback = extern "C" fn(
    url: *const c_char,
    method: *const c_char,
    user_data: *mut c_void,
) -> bool;

// Internal proxy state
struct ProxyState {
    runtime: Runtime,
    proxy_handle: Option<tokio::task::JoinHandle<()>>,
    callback: Option<HudsuckerRequestCallback>,
    user_data: usize, // Store as usize to make it Send/Sync
}

// SAFETY: We need to ensure ProxyState can be sent between threads
unsafe impl Send for ProxyState {}
unsafe impl Sync for ProxyState {}

// Global registry for proxy instances
static PROXY_REGISTRY: Lazy<Mutex<HashMap<usize, Box<ProxyState>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static NEXT_PROXY_ID: Lazy<Mutex<usize>> = Lazy::new(|| Mutex::new(1));

// Handler that calls back to C code
#[derive(Clone)]
pub struct CallbackHandler {
    pub proxy_id: usize,
}

impl HttpHandler for CallbackHandler {
    async fn handle_request(
        &mut self,
        _ctx: &HttpContext,
        req: Request<Body>,
    ) -> RequestOrResponse {
        let registry = PROXY_REGISTRY.lock().unwrap();
        if let Some(proxy_state) = registry.get(&self.proxy_id) {
            if let Some(callback) = proxy_state.callback {
                let uri = req.uri();
                let method = req.method();
                
                // Convert to C strings
                let url_str = uri.to_string();
                let method_str = method.to_string();
                
                if let (Ok(url_cstr), Ok(method_cstr)) = (
                    CString::new(url_str),
                    CString::new(method_str),
                ) {
                    let should_allow = callback(
                        url_cstr.as_ptr(),
                        method_cstr.as_ptr(),
                        proxy_state.user_data as *mut c_void,
                    );
                    
                    if !should_allow {
                        // Return a 403 Forbidden response
                        let response = Response::builder()
                            .status(403)
                            .header("content-type", "text/plain")
                            .body(Body::from("Request blocked by ad blocker"))
                            .unwrap();
                        return response.into();
                    }
                }
            }
        }
        
        // Allow the request to proceed
        req.into()
    }
}

impl WebSocketHandler for CallbackHandler {}

/// Create a new proxy instance
/// 
/// # Parameters
/// * `addr` - Address to bind to (e.g., "127.0.0.1:8080")
/// * `ca_cert_pem` - PEM-encoded CA certificate
/// * `ca_key_pem` - PEM-encoded CA private key
/// * `callback` - Callback function for request filtering
/// * `user_data` - User data pointer passed to callback
/// * `proxy_out` - Output parameter for proxy handle
/// 
/// # Returns
/// * `HudsuckerError::Success` on success
/// * Error code on failure
#[no_mangle]
pub extern "C" fn hudsucker_create_proxy(
    addr: *const c_char,
    ca_cert_pem: *const c_char,
    ca_key_pem: *const c_char,
    callback: HudsuckerRequestCallback,
    user_data: *mut c_void,
    proxy_out: *mut *mut HudsuckerProxy,
) -> HudsuckerError {
    if addr.is_null() || ca_cert_pem.is_null() || ca_key_pem.is_null() || proxy_out.is_null() {
        return HudsuckerError::InvalidParameter;
    }

    let addr_str = match unsafe { CStr::from_ptr(addr) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    let ca_cert_str = match unsafe { CStr::from_ptr(ca_cert_pem) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    let ca_key_str = match unsafe { CStr::from_ptr(ca_key_pem) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    // Parse address
    let socket_addr: SocketAddr = match addr_str.parse() {
        Ok(addr) => addr,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    // Create runtime
    let runtime = match Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return HudsuckerError::RuntimeError,
    };

    // Get unique proxy ID
    let proxy_id = {
        let mut next_id = NEXT_PROXY_ID.lock().unwrap();
        let id = *next_id;
        *next_id += 1;
        id
    };

    // Create proxy state
    let mut proxy_state = Box::new(ProxyState {
        runtime,
        proxy_handle: None,
        callback: Some(callback),
        user_data: user_data as usize,
    });

    // Set up certificate authority
    let key_pair = match KeyPair::from_pem(ca_key_str) {
        Ok(kp) => kp,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    let ca_cert = match CertificateParams::from_ca_cert_pem(ca_cert_str)
        .and_then(|params| params.self_signed(&key_pair))
    {
        Ok(cert) => cert,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    let ca = RcgenAuthority::new(key_pair, ca_cert, 1_000, aws_lc_rs::default_provider());

    // Create the proxy
    let handler = CallbackHandler { proxy_id };
    
    let proxy = match Proxy::builder()
        .with_addr(socket_addr)
        .with_ca(ca)
        .with_rustls_client(aws_lc_rs::default_provider())
        .with_http_handler(handler.clone())
        .with_websocket_handler(handler)
        .build()
    {
        Ok(p) => p,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    // Start the proxy in the background
    let proxy_handle = proxy_state.runtime.spawn(async move {
        if let Err(e) = proxy.start().await {
            eprintln!("Proxy error: {}", e);
        }
    });

    proxy_state.proxy_handle = Some(proxy_handle);

    // Store in registry
    {
        let mut registry = PROXY_REGISTRY.lock().unwrap();
        registry.insert(proxy_id, proxy_state);
    }

    // Return opaque handle (using proxy_id as the pointer value)
    unsafe {
        *proxy_out = proxy_id as *mut HudsuckerProxy;
    }

    HudsuckerError::Success
}

/// Stop and destroy the proxy
/// 
/// # Parameters
/// * `proxy` - Proxy handle from `hudsucker_create_proxy`
/// 
/// # Returns
/// * `HudsuckerError::Success` on success
/// * Error code on failure
#[no_mangle]
pub extern "C" fn hudsucker_destroy_proxy(proxy: *mut HudsuckerProxy) -> HudsuckerError {
    if proxy.is_null() {
        return HudsuckerError::InvalidParameter;
    }

    let proxy_id = proxy as usize;
    
    let proxy_state = {
        let mut registry = PROXY_REGISTRY.lock().unwrap();
        registry.remove(&proxy_id)
    };

    if let Some(mut state) = proxy_state {
        if let Some(handle) = state.proxy_handle.take() {
            handle.abort();
        }
        // Runtime will be dropped automatically when state is dropped
    }

    HudsuckerError::Success
}

/// Get the last error message (not implemented in this basic version)
#[no_mangle]
pub extern "C" fn hudsucker_get_last_error() -> *const c_char {
    ptr::null()
}

/// Generate a CA certificate and private key pair
/// 
/// # Parameters
/// * `cert_out` - Output buffer for PEM-encoded certificate (caller must free)
/// * `key_out` - Output buffer for PEM-encoded private key (caller must free)
/// 
/// # Returns
/// * `HudsuckerError::Success` on success
/// * Error code on failure
#[no_mangle]
pub extern "C" fn hudsucker_generate_ca_cert(
    cert_out: *mut *mut c_char,
    key_out: *mut *mut c_char,
) -> HudsuckerError {
    if cert_out.is_null() || key_out.is_null() {
        return HudsuckerError::InvalidParameter;
    }

    use rcgen::{BasicConstraints, CertificateParams, DistinguishedName, IsCa, KeyPair, KeyUsagePurpose};

    // Generate key pair
    let key_pair = match KeyPair::generate() {
        Ok(kp) => kp,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    // Create CA certificate parameters
    let mut params = CertificateParams::new(vec!["Hudsucker CA".to_string()]).unwrap();
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.key_usages = vec![
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
    ];

    let mut dn = DistinguishedName::new();
    dn.push(rcgen::DnType::CommonName, "Hudsucker CA");
    dn.push(rcgen::DnType::OrganizationName, "Hudsucker");
    dn.push(rcgen::DnType::CountryName, "US");
    params.distinguished_name = dn;

    // Generate certificate
    let cert = match params.self_signed(&key_pair) {
        Ok(c) => c,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    // Convert to PEM
    let cert_pem = cert.pem();
    let key_pem = key_pair.serialize_pem();

    // Allocate C strings
    let cert_c = match CString::new(cert_pem) {
        Ok(s) => s,
        Err(_) => return HudsuckerError::MemoryError,
    };

    let key_c = match CString::new(key_pem) {
        Ok(s) => s,
        Err(_) => return HudsuckerError::MemoryError,
    };

    unsafe {
        *cert_out = cert_c.into_raw();
        *key_out = key_c.into_raw();
    }

    HudsuckerError::Success
}

/// Free a string allocated by this library
#[no_mangle]
pub extern "C" fn hudsucker_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Create a new proxy instance with certificate error handling
/// 
/// This function creates a proxy that will intercept certificate validation errors
/// and display custom-branded error pages instead of generic browser errors.
/// The error pages include an option to bypass the certificate error.
/// 
/// # How certificate error handling works:
/// 
/// 1. When a client connects to a site with a certificate error (expired, self-signed, etc.),
///    the rustls/native-tls library fails during the TLS handshake
/// 2. This error propagates through hyper as a connection error
/// 3. Our custom handler intercepts this error in the `handle_error` method
/// 4. We parse the error message to identify certificate-specific issues
/// 5. Instead of returning a generic 502 error, we return a custom HTML page
/// 6. The HTML page explains the issue and offers a "Continue Anyway" option
/// 
/// # Parameters
/// * `addr` - Address to bind to (e.g., "127.0.0.1:8080")
/// * `ca_cert_pem` - PEM-encoded CA certificate
/// * `ca_key_pem` - PEM-encoded CA private key
/// * `callback` - Callback function for request filtering (ad blocking)
/// * `user_data` - User data pointer passed to callback
/// * `html_template` - Optional HTML template for error pages (can be NULL for default)
/// * `proxy_out` - Output parameter for proxy handle
/// 
/// # Returns
/// * `HudsuckerError::Success` on success
/// * Error code on failure
#[no_mangle]
pub extern "C" fn hudsucker_create_proxy_with_cert_errors(
    addr: *const c_char,
    ca_cert_pem: *const c_char,
    ca_key_pem: *const c_char,
    callback: HudsuckerRequestCallback,
    user_data: *mut c_void,
    html_template: *const c_char,
    proxy_out: *mut *mut HudsuckerProxy,
) -> HudsuckerError {
    if addr.is_null() || ca_cert_pem.is_null() || ca_key_pem.is_null() || proxy_out.is_null() {
        return HudsuckerError::InvalidParameter;
    }

    let addr_str = match unsafe { CStr::from_ptr(addr) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    let ca_cert_str = match unsafe { CStr::from_ptr(ca_cert_pem) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    let ca_key_str = match unsafe { CStr::from_ptr(ca_key_pem) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    // Parse address
    let socket_addr: SocketAddr = match addr_str.parse() {
        Ok(addr) => addr,
        Err(_) => return HudsuckerError::InvalidParameter,
    };

    // Create runtime
    let runtime = match Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return HudsuckerError::RuntimeError,
    };

    // Get unique proxy ID
    let proxy_id = {
        let mut next_id = NEXT_PROXY_ID.lock().unwrap();
        let id = *next_id;
        *next_id += 1;
        id
    };

    // Create proxy state
    let mut proxy_state = Box::new(ProxyState {
        runtime,
        proxy_handle: None,
        callback: Some(callback),
        user_data: user_data as usize,
    });

    // Set up certificate authority
    let key_pair = match KeyPair::from_pem(ca_key_str) {
        Ok(kp) => kp,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    let ca_cert = match CertificateParams::from_ca_cert_pem(ca_cert_str)
        .and_then(|params| params.self_signed(&key_pair))
    {
        Ok(cert) => cert,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    let ca = RcgenAuthority::new(key_pair, ca_cert, 1_000, aws_lc_rs::default_provider());

    // HTML template is required for certificate error handling
    if html_template.is_null() {
        return HudsuckerError::InvalidParameter;
    }
    
    let template_str = match unsafe { CStr::from_ptr(html_template) }.to_str() {
        Ok(s) => s,
        Err(_) => return HudsuckerError::InvalidParameter,
    };
    
    // Create the certificate error handler
    // This handler wraps the basic callback handler with certificate error handling
    let cert_handler = CertErrorHandler::new(proxy_id, template_str.to_string());
    
    // Build the proxy with the certificate error handler
    // When you call .with_http_handler(), you're telling hudsucker to use this
    // implementation for all HTTP-related operations (requests, responses, errors)
    let proxy = match Proxy::builder()
        .with_addr(socket_addr)
        .with_ca(ca)
        .with_rustls_client(aws_lc_rs::default_provider())
        .with_http_handler(cert_handler.clone())
        .with_websocket_handler(cert_handler)
        .build()
    {
        Ok(p) => p,
        Err(_) => return HudsuckerError::ProxyCreationFailed,
    };

    // Start the proxy in the background
    let proxy_handle = proxy_state.runtime.spawn(async move {
        if let Err(e) = proxy.start().await {
            eprintln!("Proxy error: {}", e);
        }
    });

    proxy_state.proxy_handle = Some(proxy_handle);

    // Store in registry
    {
        let mut registry = PROXY_REGISTRY.lock().unwrap();
        registry.insert(proxy_id, proxy_state);
    }

    // Return opaque handle (using proxy_id as the pointer value)
    unsafe {
        *proxy_out = proxy_id as *mut HudsuckerProxy;
    }

    HudsuckerError::Success
}
