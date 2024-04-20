//
//  NerdFontInstaller.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/15/23.
//

import Foundation

enum NerdFontInstallerError: LocalizedError {
    case userDeniedPermission
    case downloadFailed(reason: String)
    case saveDownloadFailed(reason: String)
    case unzipFailed(reason: String)
    case missingRequiredFonts
    case fontInstallationFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .userDeniedPermission:
            return "User denied permission"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .saveDownloadFailed(let reason):
            return "Downloaded file could not be saved: \(reason)"
        case .unzipFailed(let reason):
            return "Unzip failed: \(reason)"
        case .missingRequiredFonts:
            return "The downloaded bundle is missing some required fonts"
        case .fontInstallationFailed(let reason):
            return "Installation of downloaded fonts failed: \(reason)"
        }
    }
}

class NerdFontInstaller {
    private static var instance: NerdFontInstaller?
    private weak var window: NSWindow?
    private var completion: (NerdFontInstallerError?) -> ()

    static var configString: String {
        let path = Bundle(for: SpecialExceptionsWindowController.self).path(forResource: "nerd", ofType: "itse")!
        return try! String(contentsOf: URL.init(fileURLWithPath: path))
    }

    static var config: FontTable.Config = {
        FontTable.Config(string: configString)!
    }()

    private var neededFontPostscriptNames: [String] {
        let config = Self.config
        return config.entries.compactMap { entry in
            let needFont = NSFont(name: entry.fontName, size: 10) == nil
            return needFont ? entry.fontName : nil
        }
    }

    private enum State: CustomDebugStringConvertible {
        case ground
        case downloading
        case unzipping(from: URL, to: URL)
        case installing(folder: String)
        case updatingProfile
        case successful
        case failed(NerdFontInstallerError)

        var debugDescription: String {
            switch self {
            case .ground: return "ground"
            case .downloading: return "downloading"
            case .unzipping(from: let from, to: let todir): return "unzipping from \(from.absoluteString) to \(todir.absoluteString)"
            case .updatingProfile: return "updating profile"
            case .successful: return "successful"
            case .failed(let nerdError): return "error \(nerdError.errorDescription ?? "unknown")"
            case .installing(folder: let folder): return "installing to \(folder)"
            }
        }
    }

    private var state = State.ground {
        didSet {
            DLog("State became \(state.debugDescription)")
            switch state {
            case .ground:
                break
            case .downloading:
                initiateDownload()
            case .unzipping(from: let zip, to: let dir):
                unzip(zip, to: dir)
            case .installing(folder: let folder):
                install(from: folder)
            case .updatingProfile:
                state = .successful
                completion(nil)
            case .successful:
                break
            case .failed(let error):
                completion(error)
            }
        }
    }

    static func start(window: NSWindow?, completion: @escaping (NerdFontInstallerError?) -> ()) {
        Self.instance = NerdFontInstaller(window, completion: completion)
    }

    private init(_ window: NSWindow?, completion: @escaping (NerdFontInstallerError?) -> ()) {
        self.window = window
        self.completion = completion
        state = .ground

        defer {
            if neededFontPostscriptNames.isEmpty {
                state = .updatingProfile
            } else {
                state = .downloading
            }
        }
    }

    private func askUserForPermissionToDownload() -> Bool {
        let selection = iTermWarning.show(
            withTitle: "To install the Nerd Font Bundle iTerm2 must first download and install these fonts: \(neededFontPostscriptNames.joined(separator: ", ")).",
            actions: ["Download", "Cancel"],
            accessory: nil,
            identifier: "SpecialExceptionsMissingFontsForNerdBundle",
            silenceable: .kiTermWarningTypePersistent,
            heading: "Download Needed",
            window: window)
        return selection == .kiTermWarningSelection0
    }

    private var task: URLSessionTask?

    private func initiateDownload() {
        if !askUserForPermissionToDownload() {
            state = .failed(NerdFontInstallerError.userDeniedPermission)
            return
        }

        NSLog("Start download task")
        let url = URL(string: "https://iterm2.com/downloads/assets/nerd-fonts-v1.zip")!
        task = URLSession.shared.downloadTask(with: url) { [weak self] (location, response, error) in
            self?.downloadDidComplete(location: location, response: response, error: error)
            self?.task = nil
        }
        task?.resume()
    }

    // Runs on a private queue
    private func downloadDidComplete(location: URL?, response: URLResponse?, error: Error?) {
        NSLog("Download completed. error=\(String(describing: error))")
        if let error {
            DispatchQueue.main.async {
                self.state = .failed(NerdFontInstallerError.downloadFailed(
                    reason: "The Nerd Font Bundle download failed with an error: \(error.localizedDescription)"))
            }
            return
        }
        if let location {
            let tempDir = URL(fileURLWithPath: FileManager.default.it_temporaryDirectory()!)
            let zip = tempDir.appendingPathComponent("file.zip")
            do {
                DLog("Move \(location.path) to \(zip.path)")
                try FileManager.default.moveItem(at: location, to: zip)
                let destination = Self.contentsFolder(tempDir)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                DispatchQueue.main.async {
                    self.state = .unzipping(from: zip, to: destination)
                }
            } catch {
                DispatchQueue.main.async {
                    let nerdError = NerdFontInstallerError.saveDownloadFailed(reason: error.localizedDescription)
                    self.state = .failed(nerdError)
                }
            }
        }
    }

    private static func contentsFolder(_ location: URL) -> URL {
        return location.appendingPathComponent("Contents")
    }

    private func unzip(_ location: URL, to destination: URL) {
        iTermCommandRunner.unzipURL(location,
                                    withArguments: ["-q"],
                                    destination: destination.path,
                                    callbackQueue: DispatchQueue.main,
                                    completion: { [weak self] error in
            if let error {
                self?.state = .failed(.unzipFailed(reason: error.localizedDescription))
                return
            }
            self?.state = .installing(folder: destination.path)
        })
    }

    private var installedFontFamilyNames: Set<String> {
        let fontCollection = CTFontManagerCopyAvailableFontFamilyNames()
        return Set(Array(fontCollection))
    }

    private func install(from tempDir: String) {
        let fileManager = FileManager.default
        let fontDescriptors = fileManager.flatMapRegularFiles(in: tempDir) { itemURL in
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(itemURL as CFURL) {
                return Array<CTFontDescriptor>(descriptors)
            }
            return []
        }
        install(descriptors: fontDescriptors) { [weak self] error in
            if let error {
                self?.state = .failed(error)
            } else if let self {
                if !self.neededFontPostscriptNames.isEmpty {
                    self.state = .failed(.missingRequiredFonts)
                    return
                }
                self.state = .updatingProfile
            }
        }
    }

    private func install(descriptors: [CTFontDescriptor], completion: @escaping (NerdFontInstallerError?) -> ()) {
        if descriptors.isEmpty {
            completion(nil)
            return
        }
        CTFontManagerRegisterFontDescriptors(descriptors.cfArray,
                                             .persistent,
                                             true) { errors, done in
            let errorsArray = Array<CFError>(errors)
            if errorsArray.isEmpty {
                if done {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
                return true
            }
            var reason = errorsArray.compactMap { CFErrorCopyDescription($0) as String? }.joined(separator: ", ")
            if reason.isEmpty {
                reason = "Unknown errors occurred"
            }
            DLog("\(reason)")
            DispatchQueue.main.async {
                completion(NerdFontInstallerError.fontInstallationFailed(reason: reason))
            }
            return false
        }
    }
}

extension Array {
    var cfArray: CFArray {
        let count = self.count
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        pointer.initialize(repeating: nil, count: count)

        for (index, element) in self.enumerated() {
            pointer[index] = UnsafeRawPointer(Unmanaged.passRetained(element as AnyObject).toOpaque())
        }

        var callbacks = kCFTypeArrayCallBacks
        callbacks.retain = { source, pointer in
            return UnsafeRawPointer(Unmanaged<AnyObject>.fromOpaque(pointer!).retain().toOpaque())
        }

        callbacks.release = { source, pointer in
            Unmanaged<AnyObject>.fromOpaque(pointer!).release()
        }

        let cfArray = CFArrayCreate(kCFAllocatorDefault, pointer, count, &callbacks)
        pointer.deallocate()

        return cfArray!
    }
}

extension Array {
    init(_ cfArray: CFArray) {
        self.init()

        let count = CFArrayGetCount(cfArray)
        for index in 0..<count {
            if let value = CFArrayGetValueAtIndex(cfArray, index) {
                append(unsafeBitCast(value, to: Element.self))
            }
        }
    }
}

extension FileManager {
    func flatMapRegularFiles<T>(in folder: String, closure: (URL) throws -> ([T])) rethrows -> [T] {
        var result = [T]()
        try enumerateRegularFiles(in: folder) {
            let value = try closure($0)
            result.append(contentsOf: value)
        }
        return result
    }

    func enumerateRegularFiles(in folder: String, closure: (URL) throws -> ()) rethrows {
        let directoryContents = try? contentsOfDirectory(atPath: folder)
        for itemName in directoryContents ?? [] {
            if itemName.hasPrefix(".") {
                continue
            }

            var isDirectory: ObjCBool = false
            let itemURL = URL(fileURLWithPath: folder).appendingPathComponent(itemName)
            guard fileExists(atPath: itemURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue else {
                continue
            }
            try closure(itemURL)
        }
    }
}

extension CTFontDescriptor {
    var postscriptName: String? {
        let fontFamilyNameKey = kCTFontNameAttribute as String
        return CTFontDescriptorCopyAttribute(self, fontFamilyNameKey as CFString) as? String
    }
}
