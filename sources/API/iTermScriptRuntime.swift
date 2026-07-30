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

@objc(iTermScriptRuntime)
class iTermScriptRuntime: NSObject {
    @objc static let venvDirectoryName = ".venv"
    @objc static let markerFileName = "python-runtime.json"
    @objc static let legacyDirectoryName = "iterm2env"

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
}
