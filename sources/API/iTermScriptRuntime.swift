//
//  iTermScriptRuntime.swift
//  iTerm2SharedARC
//
//  Phase 2 of the uv Python-runtime migration. Determines a full-environment
//  script's runtime backend from what is on disk, independent of the
//  pythonRuntimeUsesUV gate. Launching keys off this (so toggling the gate never
//  strands an already-provisioned script); only provisioning branches on the gate.
//  See docs/uv-python-runtime-migration.md (Phase 2, "Development gating").
//

import Foundation

@objc enum iTermScriptRuntimeBackend: Int {
    case none    // no recognizable runtime environment
    case uv      // a uv-provisioned .venv plus the python-runtime.json marker
    case legacy  // the bundled Python runtime's iterm2env tree
}

// The python-runtime.json marker a uv-provisioned script carries. Deliberately a
// different filename/shape from the legacy iterm2env-metadata.json so an older
// iTerm2 build does not misread a uv environment.
struct iTermPythonRuntimeMarker: Codable, Equatable {
    var schema = 1
    var backend = "uv"
    var uvVersion: String
    var python: String          // the resolved interpreter version, e.g. "3.9"
    var remappedFrom: String?   // the original pin if it was bumped, else nil

    enum CodingKeys: String, CodingKey {
        case schema
        case backend
        case uvVersion = "uv_version"
        case python
        case remappedFrom = "remapped_from"
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    static func from(jsonData data: Data) -> iTermPythonRuntimeMarker? {
        return try? JSONDecoder().decode(iTermPythonRuntimeMarker.self, from: data)
    }
}

// What the "Install Python Runtime" menu item should do, decided from the gate and what
// is installed. The menu controller maps this to a title/action/target.
@objc enum iTermPythonRuntimeMenuAction: Int {
    case uvInstall            // uv gate on, uv not installed
    case uvCheckForUpdate     // uv gate on, uv installed
    case legacyInstall        // uv gate off, legacy runtime not installed
    case legacyCheckForUpdate // uv gate off, legacy runtime installed
}

@objc(iTermScriptRuntime)
class iTermScriptRuntime: NSObject {

    // The single place that decides the Scripts > Manage runtime menu item, so the title
    // and target never disagree with the gate (the bug where a leftover legacy runtime
    // retargeted the item at the legacy updater even with the gate on). Pure and tested.
    @objc static func pythonRuntimeMenuAction(uvGateEnabled: Bool,
                                              uvInstalled: Bool,
                                              legacyInstalled: Bool) -> iTermPythonRuntimeMenuAction {
        if uvGateEnabled {
            return uvInstalled ? .uvCheckForUpdate : .uvInstall
        }
        return legacyInstalled ? .legacyCheckForUpdate : .legacyInstall
    }

    @objc static func isCheckForUpdate(_ action: iTermPythonRuntimeMenuAction) -> Bool {
        return action == .uvCheckForUpdate || action == .legacyCheckForUpdate
    }

    @objc static func pythonRuntimeMenuItemTitle(for action: iTermPythonRuntimeMenuAction) -> String {
        return isCheckForUpdate(action) ? "Check for Updated Runtime" : "Install Python Runtime"
    }

    @objc static let venvDirectoryName = ".venv"
    @objc static let markerFileName = "python-runtime.json"
    @objc static let legacyDirectoryName = "iterm2env"

    // The Python version a new or exported script defaults to when none can be
    // determined (no shebang, no setup.cfg, and no legacy runtime installed to report
    // its latest version). Kept in one place so every fallback agrees; uv remaps it to
    // an available minor at provision time if necessary.
    @objc static let defaultPythonVersion = "3.12"

    // The interpreter inside a uv .venv is at the flat venv location, unlike the
    // legacy pyenv tree (iterm2env/versions/<X.Y.Z>/bin/python3).
    private static func venvInterpreterPath(forScriptContainer container: String) -> String {
        return ((container as NSString).appendingPathComponent(venvDirectoryName) as NSString)
            .appendingPathComponent("bin/python")
    }

    @objc static func backend(forScriptContainer container: String) -> iTermScriptRuntimeBackend {
        let fm = FileManager.default
        let marker = (container as NSString).appendingPathComponent(markerFileName)
        if fm.fileExists(atPath: venvInterpreterPath(forScriptContainer: container)),
           fm.fileExists(atPath: marker) {
            return .uv
        }
        var isDirectory: ObjCBool = false
        let legacy = (container as NSString).appendingPathComponent(legacyDirectoryName)
        if fm.fileExists(atPath: legacy, isDirectory: &isDirectory), isDirectory.boolValue {
            return .legacy
        }
        return .none
    }

    // The python interpreter to launch for a uv-provisioned script, or nil if the
    // container is not a uv environment.
    @objc static func uvInterpreterPath(forScriptContainer container: String) -> String? {
        guard backend(forScriptContainer: container) == .uv else {
            return nil
        }
        return venvInterpreterPath(forScriptContainer: container)
    }

    // The resolved Python version recorded in a script's python-runtime.json marker
    // (e.g. "3.10"), or nil if the marker is absent or unreadable.
    @objc static func pythonVersion(forScriptContainer container: String) -> String? {
        let marker = (container as NSString).appendingPathComponent(markerFileName)
        guard let data = FileManager.default.contents(atPath: marker) else {
            return nil
        }
        return iTermPythonRuntimeMarker.from(jsonData: data)?.python
    }

    // The Python version a LEGACY full-environment script was actually built on, read from
    // its iterm2env/versions/<X.Y.Z> directory, or nil if none is present. setup.cfg's
    // python_requires is often absent or a range (e.g. ">=3.7") that the pinned-version
    // parser returns nil for; without this a 3.7-era script would migrate to the current
    // default with no forced-remap warning. The on-disk version is authoritative.
    @objc(legacyEnvironmentPythonVersionForContainer:)
    static func legacyEnvironmentPythonVersion(container: String) -> String? {
        let versionsDir = ((container as NSString).appendingPathComponent(legacyDirectoryName) as NSString)
            .appendingPathComponent("versions")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: versionsDir) else {
            return nil
        }
        // A version directory like "3.7.9": at least two dot-separated, all-numeric parts.
        return entries.sorted().first { entry in
            let parts = entry.split(separator: ".")
            return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        }
    }
}
