import Foundation
import Security

/// Swift wrapper for the Hudsucker MITM proxy C FFI
public class HudsuckerProxy {
    static let standard = try? HudsuckerProxy.withCertificateErrorHandling(address: "127.0.0.1",
                                                                           ports: [1912, 1913, 1914, 1915],
                                                                           requestFilter: filterRequest(url:method:))
    static var filterCallback: ((String, String) -> Bool)?
    private(set) var port: Int!

    static func filterRequest(url: String, method: String) -> Bool {
        guard let filterCallback else {
            return true
        }
        return filterCallback(url, method)
    }

    // MARK: - Types
    
    /// Error types that can be thrown by the HudsuckerProxy
    public enum ProxyError: Int32, Error, CaseIterable {
        case success = 0
        case invalidParameter = -1
        case proxyCreationFailed = -2
        case proxyStartFailed = -3
        case runtimeError = -4
        case memoryError = -5
        
        var localizedDescription: String {
            switch self {
            case .success:
                return "Success"
            case .invalidParameter:
                return "Invalid parameter"
            case .proxyCreationFailed:
                return "Proxy creation failed"
            case .proxyStartFailed:
                return "Proxy start failed"
            case .runtimeError:
                return "Runtime error"
            case .memoryError:
                return "Memory error"
            }
        }
    }
    
    /// Callback type for request filtering
    /// - Parameters:
    ///   - url: The URL being requested
    ///   - method: The HTTP method (GET, POST, etc.)
    /// - Returns: true to allow the request, false to block it
    public typealias RequestFilterCallback = (String, String) -> Bool
    
    /// Configuration options for certificate error handling
    public struct CertificateErrorOptions {
        /// Whether to enable custom certificate error pages
        public let enableCustomErrorPages: Bool
        /// Custom branding text to show on error pages
        public let brandingText: String?
        /// Custom CSS styles for error pages
        public let customCSS: String?
        
        public init(enableCustomErrorPages: Bool = true, 
                   brandingText: String? = nil, 
                   customCSS: String? = nil) {
            self.enableCustomErrorPages = enableCustomErrorPages
            self.brandingText = brandingText
            self.customCSS = customCSS
        }
    }
    
    // MARK: - Properties
    
    private var proxyHandle: OpaquePointer?
    private var filterCallback: RequestFilterCallback?
    private let address: String
    private let caCertPEM: String
    private let caKeyPEM: String
    private let certificateErrorOptions: CertificateErrorOptions?
    
    // MARK: - Initialization
    
    /// Initialize a new HudsuckerProxy instance
    /// - Parameters:
    ///   - address: The address to bind to (e.g., "127.0.0.1:8080")
    ///   - ports: Array of ports to try binding to
    ///   - caCertPEM: PEM-encoded CA certificate
    ///   - caKeyPEM: PEM-encoded CA private key
    ///   - requestFilter: Callback to filter requests
    ///   - certificateErrorOptions: Optional configuration for certificate error handling
    public init(address: String,
                ports: [Int],
                caCertPEM: String,
                caKeyPEM: String, 
                requestFilter: @escaping RequestFilterCallback,
                certificateErrorOptions: CertificateErrorOptions? = nil) throws {
        self.address = address
        self.caCertPEM = caCertPEM
        self.caKeyPEM = caKeyPEM
        self.filterCallback = requestFilter
        self.certificateErrorOptions = certificateErrorOptions
        for port in ports {
            do {
                try start(port: port)
                self.port = port
                return
            } catch {
                if let error = error as? ProxyError, error == .proxyCreationFailed {
                    DLog("Proxy creation failed, try next port")
                } else {
                    throw error
                }
            }
        }
        throw ProxyError.proxyCreationFailed
    }
    
    /// Convenience initializer that generates a new CA certificate
    /// - Parameters:
    ///   - address: The address to bind to (e.g., "127.0.0.1:8080")
    ///   - ports: Array of ports to try binding to
    ///   - requestFilter: Callback to filter requests
    ///   - certificateErrorOptions: Optional configuration for certificate error handling
    public convenience init(address: String,
                            ports: [Int],
                            requestFilter: @escaping RequestFilterCallback,
                            certificateErrorOptions: CertificateErrorOptions? = nil) throws {
        let (cert, key) = try Self.generateCACertificate()
        try self.init(address: address,
                      ports: ports,
                      caCertPEM: cert,
                      caKeyPEM: key,
                      requestFilter: requestFilter,
                      certificateErrorOptions: certificateErrorOptions)
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods

    public var caCert: SecCertificate? {
        let pem = caCertPEM
        let lines = pem.components(separatedBy: .newlines)
        let base64Lines = lines.filter { line in
            return !line.hasPrefix("-----BEGIN CERTIFICATE")
                && !line.hasPrefix("-----END CERTIFICATE")
        }
        let base64 = base64Lines.joined()
        guard let derData = Data(base64Encoded: base64) else {
            return nil
        }
        return SecCertificateCreateWithData(nil, derData as CFData)
    }

    /// Start the proxy server
    public func start(port: Int) throws {
        guard proxyHandle == nil else {
            // Already started
            return
        }
        
        let cCallback: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Bool = { url, method, userData in
            guard let url = url, let method = method, let userData = userData else {
                return true // Allow by default if parameters are invalid
            }
            
            let proxy = Unmanaged<HudsuckerProxy>.fromOpaque(userData).takeUnretainedValue()
            
            let urlString = String(cString: url)
            let methodString = String(cString: method)
            
            return proxy.filterCallback?(urlString, methodString) ?? true
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        var handle: OpaquePointer?
        let result: Int32
        
        // Use certificate error handling if enabled
        if let certOptions = certificateErrorOptions, certOptions.enableCustomErrorPages {
            result = hudsucker_create_proxy_with_cert_errors(
                "\(address):\(port)",
                caCertPEM,
                caKeyPEM,
                cCallback,
                selfPtr,
                &handle
            )
        } else {
            result = hudsucker_create_proxy(
                "\(address):\(port)",
                caCertPEM,
                caKeyPEM,
                cCallback,
                selfPtr,
                &handle
            )
        }
        
        guard let error = ProxyError(rawValue: result), error == .success else {
            throw ProxyError(rawValue: result) ?? .runtimeError
        }
        
        self.proxyHandle = handle
    }
    
    /// Stop the proxy server
    public func stop() {
        if let handle = proxyHandle {
            _ = hudsucker_destroy_proxy(handle)
            proxyHandle = nil
        }
    }
    
    /// Check if the proxy is currently running
    public var isRunning: Bool {
        return proxyHandle != nil
    }
    
    /// Check if certificate error handling is enabled
    public var isCertificateErrorHandlingEnabled: Bool {
        return certificateErrorOptions?.enableCustomErrorPages ?? false
    }
    
    // MARK: - Static Methods
    
    /// Generate a new CA certificate and private key pair
    /// - Returns: A tuple containing (certificate PEM, private key PEM)
    public static func generateCACertificate() throws -> (String, String) {
        var certPtr: UnsafeMutablePointer<CChar>?
        var keyPtr: UnsafeMutablePointer<CChar>?
        
        let result = hudsucker_generate_ca_cert(&certPtr, &keyPtr)
        
        guard let error = ProxyError(rawValue: result), error == .success else {
            throw ProxyError(rawValue: result) ?? .runtimeError
        }
        
        guard let certCStr = certPtr, let keyCStr = keyPtr else {
            throw ProxyError.memoryError
        }
        
        let cert = String(cString: certCStr)
        let key = String(cString: keyCStr)
        
        // Free the C strings
        hudsucker_free_string(certPtr)
        hudsucker_free_string(keyPtr)
        
        return (cert, key)
    }
    
    /// Create a proxy with certificate error handling enabled
    /// - Parameters:
    ///   - address: The address to bind to (e.g., "127.0.0.1")
    ///   - ports: Array of ports to try binding to
    ///   - requestFilter: Callback to filter requests
    ///   - brandingText: Optional custom branding text for error pages
    ///   - customCSS: Optional custom CSS for error pages
    /// - Returns: A configured HudsuckerProxy instance
    /// - Throws: ProxyError if the proxy cannot be created
    public static func withCertificateErrorHandling(
        address: String,
        ports: [Int],
        requestFilter: @escaping RequestFilterCallback,
        brandingText: String? = nil,
        customCSS: String? = nil
    ) throws -> HudsuckerProxy {
        let certOptions = CertificateErrorOptions(
            enableCustomErrorPages: true,
            brandingText: brandingText,
            customCSS: customCSS
        )
        
        return try HudsuckerProxy(
            address: address,
            ports: ports,
            requestFilter: requestFilter,
            certificateErrorOptions: certOptions
        )
    }
}

// MARK: - C FFI Bridge

// Import the C functions from the hudsucker FFI
@_silgen_name("hudsucker_create_proxy")
private func hudsucker_create_proxy(
    _ addr: UnsafePointer<CChar>,
    _ caCertPem: UnsafePointer<CChar>,
    _ caKeyPem: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Bool,
    _ userData: UnsafeMutableRawPointer?,
    _ proxyOut: UnsafeMutablePointer<OpaquePointer?>
) -> Int32

/// Create a new proxy instance with certificate error handling
@_silgen_name("hudsucker_create_proxy_with_cert_errors")
private func hudsucker_create_proxy_with_cert_errors(
    _ addr: UnsafePointer<CChar>,
    _ caCertPem: UnsafePointer<CChar>,
    _ caKeyPem: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Bool,
    _ userData: UnsafeMutableRawPointer?,
    _ proxyOut: UnsafeMutablePointer<OpaquePointer?>
) -> Int32

@_silgen_name("hudsucker_start_proxy")
private func hudsucker_start_proxy(_ proxy: OpaquePointer?) -> Int32

@_silgen_name("hudsucker_destroy_proxy")
private func hudsucker_destroy_proxy(_ proxy: OpaquePointer?) -> Int32

@_silgen_name("hudsucker_generate_ca_cert")
private func hudsucker_generate_ca_cert(
    _ certOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ keyOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32

@_silgen_name("hudsucker_free_string")
private func hudsucker_free_string(_ ptr: UnsafeMutablePointer<CChar>?)
