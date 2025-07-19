//
//  iTermBrowserProxyCertificateManager.swift
//  iTerm2
//
//  Created by George Nachman on 7/19/25.
//

import Foundation
import Security

class iTermBrowserProxyCertificateManager {
    private static let keychainService = "com.iterm.browser.proxy.certificates"
    private static let privateKeyPrefix = "privatekey"
    private static let certPrefix       = "cert"

    enum CertificateManagerError: Error {
        case failedToReadPEMData
        case failedToStoreInKeychain(OSStatus)
        case failedToRetrieveFromKeychain(OSStatus)
        case invalidPEMFormat
        case mkstempFailed(errno: Int32)
        case invalidPath
        case addTrustedCertFailed
        case executionFailed(errorInfo: [String: Any])
    }

    struct PEMCertAndKey {
        var cert: String
        var key: String
    }

    func saveCertificateAndPrivateKey(certAndKey: PEMCertAndKey,
                                      identifier: String) throws {
        guard certAndKey.cert.contains("-----BEGIN CERTIFICATE-----"),
              certAndKey.cert.contains("-----END CERTIFICATE-----") else {
            throw CertificateManagerError.invalidPEMFormat
        }

        guard certAndKey.key.contains("-----BEGIN PRIVATE KEY-----"),
              certAndKey.key.contains("-----END PRIVATE KEY-----") else {
            throw CertificateManagerError.invalidPEMFormat
        }
        guard let certData = certAndKey.cert.data(using: .utf8) else {
            throw CertificateManagerError.invalidPEMFormat
        }
        try storePrivateKey(pemKey: certAndKey.key,
                            identifier: identifier)
        try storeCert(pemCert: certAndKey.cert,
                      identifier: identifier)
        try addTrustedCert(pem: certData)
    }

    func retrieveCertificateAndPrivateKey(identifier: String) throws -> PEMCertAndKey {
        let keyPEM  = try retrievePrivateKey(identifier: identifier)
        let certPEM = try retrieveCert(identifier: identifier)
        return PEMCertAndKey(cert: certPEM,
                             key: keyPEM)
    }

    func removeCertificateAndPrivateKey(identifier: String) throws {
        let accounts = [
            "\(Self.privateKeyPrefix)-\(identifier)",
            "\(Self.certPrefix)-\(identifier)"
        ]

        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

private extension iTermBrowserProxyCertificateManager {
    // MARK: - Make cert trusted

    func addTrustedCert(pem: Data) throws {
        let path = try writeSecureTempFile(contents: pem)
        defer {
            try? FileManager.default.removeItem(at: path)
        }
        try addTrustedCert(certPath: path.path)
    }

    private func writeSecureTempFile(contents: Data) throws -> URL {
        // template must end in six X’s
        var template = "/tmp/cert.XXXXXX".utf8CString
        let fd = template.withUnsafeMutableBufferPointer { ptr in
            mkstemp(ptr.baseAddress)
        }
        guard fd >= 0 else {
            throw CertificateManagerError.mkstempFailed(errno: errno)
        }
        // mkstemp creates with 0600; write and sync
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: contents)
        fsync(fd)
        let path = template.withUnsafeBufferPointer { ptr -> String in
            return String(cString: ptr.baseAddress!)
        }
        return URL(fileURLWithPath: path)
    }

    /// Runs `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <certPath>`
    /// by invoking an AppleScript with administrator privileges.
    private func addTrustedCert(certPath: String) throws {
        if certPath.contains("\"") || certPath.contains("\\") {
            throw CertificateManagerError.invalidPath
        }
        let escapedPath = (certPath as NSString).stringEscapedForBash() as String
        let cmd = "security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \(escapedPath)"
        let src = "do shell script \"\(cmd)\" with administrator privileges"
        guard let script = NSAppleScript(source: src) else {
            throw CertificateManagerError.addTrustedCertFailed
        }

        var errInfo: NSDictionary?
        script.executeAndReturnError(&errInfo)
        if let info = errInfo as? [String: Any] {
            throw CertificateManagerError.executionFailed(errorInfo: info)
        }
    }

    // MARK: - Private key

    func storePrivateKey(pemKey: String,
                         identifier: String) throws {
        guard let rawData = pemKey.data(using: .utf8) else {
            throw CertificateManagerError.failedToReadPEMData
        }
        let account = "\(Self.privateKeyPrefix)-\(identifier)"
        try store(rawData: rawData, account: account, label: "iTerm2 Proxy Private Key")
    }

    func retrievePrivateKey(identifier: String) throws -> String {
        let account = "\(Self.privateKeyPrefix)-\(identifier)"
        return try retrieve(account: account)
    }

    // MARK: - Cert

    func storeCert(pemCert: String,
                   identifier: String) throws {
        guard let rawData = pemCert.data(using: .utf8) else {
            throw CertificateManagerError.failedToReadPEMData
        }
        let account = "\(Self.certPrefix)-\(identifier)"
        try store(rawData: rawData, account: account, label: "iTerm2 Proxy Cert")
    }

    func retrieveCert(identifier: String) throws -> String {
        let account = "\(Self.certPrefix)-\(identifier)"
        return try retrieve(account: account)
    }

    // MARK: - Keychain

    func store(rawData: Data, account: String, label: String) throws {
        var data = rawData
        defer {
            data.resetBytes(in: 0..<data.count)
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: label,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CertificateManagerError.failedToStoreInKeychain(status)
        }
    }

    func retrieve(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let rawData = item as? Data else {
            throw CertificateManagerError.failedToRetrieveFromKeychain(status)
        }

        var data = rawData
        defer {
            data.resetBytes(in: 0..<data.count)
        }

        guard let pem = String(data: data, encoding: .utf8) else {
            throw CertificateManagerError.failedToRetrieveFromKeychain(errSecInternalError)
        }
        return pem
    }
}
