import Foundation
import Security

/// Swift wrapper for the Hudsucker MITM proxy C FFI
public class HudsuckerProxy {
    private static let caKeyLabel = "iTerm2 Proxy CA Key"
    static var standard: HudsuckerProxy?
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
        case noConsent  = -6

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
            case .noConsent:
                return "User declined permission"
            }
        }
    }
    
    /// Callback type for request filtering
    /// - Parameters:
    ///   - url: The URL being requested
    ///   - method: The HTTP method (GET, POST, etc.)
    /// - Returns: true to allow the request, false to block it
    public typealias RequestFilterCallback = (String, String) -> Bool
    
    
    // MARK: - Properties
    
    private var proxyHandle: OpaquePointer?
    private var filterCallback: RequestFilterCallback?
    private let address: String
    private let caCertPEM: String
    private let caKeyPEM: String
    private let certificateErrorHTMLTemplate: String?
    
    // MARK: - Initialization
    
    /// Initialize a new HudsuckerProxy instance
    /// - Parameters:
    ///   - address: The address to bind to (e.g., "127.0.0.1:8080")
    ///   - ports: Array of ports to try binding to
    ///   - caCertPEM: PEM-encoded CA certificate
    ///   - caKeyPEM: PEM-encoded CA private key
    ///   - requestFilter: Callback to filter requests
    ///   - certificateErrorHTMLTemplate: HTML template for certificate error pages (nil for default)
    public init(address: String,
                ports: [Int],
                caCertPEM: String,
                caKeyPEM: String, 
                requestFilter: @escaping RequestFilterCallback,
                certificateErrorHTMLTemplate: String?) throws {
        self.address = address
        self.caCertPEM = caCertPEM
        self.caKeyPEM = caKeyPEM
        self.filterCallback = requestFilter
        self.certificateErrorHTMLTemplate = certificateErrorHTMLTemplate
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

    private static func userConsentsToAddCACert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Permission Needed"
        alert.informativeText = "To enable advanced ad blocking, a trusted root certificate must be added to the system. This is scary and you should understand what you’re doing before allowing this."

        class LinkTextField: NSTextField {
            override func resetCursorRects() {
                super.resetCursorRects()
                addCursorRect(bounds, cursor: .pointingHand)
            }
        }
        let linkField = LinkTextField(labelWithString: "")
        linkField.isEditable = false
        linkField.isBordered = false
        linkField.drawsBackground = false
        linkField.allowsEditingTextAttributes = true
        linkField.isSelectable = true

        let title = "Learn more"
        let attributed = NSMutableAttributedString(string: title)
        guard let url = URL(string: "https://iterm2.com/documentation-proxy-adblocking.html") else {
            return false
        }
        attributed.addAttribute(.link,
                                value: url,
                                range: NSRange(location: 0, length: title.count))
        attributed.addAttribute(.underlineStyle,
                                value: NSUnderlineStyle.single.rawValue,
                                range: NSRange(location: 0, length: title.count))
        attributed.addAttribute(.foregroundColor,
                                value: NSColor.linkColor,
                                range: NSRange(location: 0, length: title.count))

        linkField.attributedStringValue = attributed
        linkField.sizeToFit()
        alert.accessoryView = linkField
        alert.alertStyle = .critical
        let allow = alert.addButton(withTitle: "Allow")
        allow.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static let identifier = "com.googlecode.iterm2.proxy-cert-and-key"
    private static func addCACert(certManager: iTermBrowserProxyCertificateManager) throws -> iTermBrowserProxyCertificateManager.PEMCertAndKey {
        guard userConsentsToAddCACert() else {
            throw ProxyError.noConsent
        }
        let certAndKey = try generateCACertificate()
        try certManager.saveCertificateAndPrivateKey(certAndKey: certAndKey, identifier: identifier)
        return certAndKey
    }

    private static func loadCACertAndKey(certManager: iTermBrowserProxyCertificateManager) -> iTermBrowserProxyCertificateManager.PEMCertAndKey? {
        return try? certManager.retrieveCertificateAndPrivateKey(identifier: identifier)
    }

    private static func loadOrAddCertAndKey() throws -> iTermBrowserProxyCertificateManager.PEMCertAndKey {
        let certManager = iTermBrowserProxyCertificateManager()
        if let certAndKey = loadCACertAndKey(certManager: certManager) {
            return certAndKey
        } else {
            return try addCACert(certManager: certManager)
        }
    }

    public static func createAddingCertIfNeeded(address: String,
                                                ports: [Int],
                                                requestFilter: @escaping RequestFilterCallback,
                                                certificateErrorHTMLTemplate: String?) throws -> HudsuckerProxy {
        let certAndKey = try loadOrAddCertAndKey()
        return try HudsuckerProxy(address: address,
                                  ports: ports,
                                  caCertPEM: certAndKey.cert,
                                  caKeyPEM: certAndKey.key,
                                  requestFilter: requestFilter,
                                  certificateErrorHTMLTemplate: certificateErrorHTMLTemplate)
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
        
        // Use certificate error handling if template is provided
        if let htmlTemplate = certificateErrorHTMLTemplate {
            result = hudsucker_create_proxy_with_cert_errors(
                "\(address):\(port)",
                caCertPEM,
                caKeyPEM,
                cCallback,
                selfPtr,
                htmlTemplate,
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
        return certificateErrorHTMLTemplate != nil
    }
    
    /// Add a domain to the certificate bypass list
    /// - Parameters:
    ///   - domain: The domain to bypass certificate validation for (e.g., "example.com")
    ///   - token: Valid bypass token from certificate error page
    /// - Throws: ProxyError if the operation fails or token is invalid
    public func addBypassedDomain(_ domain: String, token: String) throws {
        guard let handle = proxyHandle else {
            throw ProxyError.runtimeError
        }
        
        let result = hudsucker_add_bypassed_domain(handle, domain, token)
        
        guard let error = ProxyError(rawValue: result), error == .success else {
            throw ProxyError(rawValue: result) ?? .runtimeError
        }
    }
    
    // MARK: - Static Methods
    
    /// Generate a new CA certificate and private key pair
    /// - Returns: A tuple containing (certificate PEM, private key PEM)
    private static func generateCACertificate() throws -> iTermBrowserProxyCertificateManager.PEMCertAndKey {
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
        
        return iTermBrowserProxyCertificateManager.PEMCertAndKey(cert: cert, key: key)
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
    _ htmlTemplate: UnsafePointer<CChar>?,
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

@_silgen_name("hudsucker_add_bypassed_domain")
private func hudsucker_add_bypassed_domain(_ proxy: OpaquePointer?, _ domain: UnsafePointer<CChar>, _ token: UnsafePointer<CChar>) -> Int32
