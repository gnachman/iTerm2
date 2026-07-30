//
//  ScriptRuntimeBackendTests.swift
//  ModernTests
//
//  Phase 2 of the uv Python-runtime migration. A full-environment script's runtime
//  backend is determined by what is on disk, independent of the pythonRuntimeUsesUV
//  gate: a uv script has .venv + python-runtime.json; a legacy script has iterm2env.
//  This is what lets the gate be toggled without stranding an already-provisioned
//  script. See docs/uv-python-runtime-migration.md (Phase 2, "Development gating").
//

import XCTest
@testable import iTerm2SharedARC

final class ScriptRuntimeBackendTests: XCTestCase {
    private func makeContainer() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("scriptrt-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ path: String, _ contents: String = "x") throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testDetectsUvBackend() throws {
        let c = try makeContainer()
        try write((c as NSString).appendingPathComponent(".venv/bin/python"))
        try write((c as NSString).appendingPathComponent("python-runtime.json"), "{}")
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: c), .uv)
        XCTAssertEqual(iTermScriptRuntime.uvInterpreterPath(forScriptContainer: c),
                       (c as NSString).appendingPathComponent(".venv/bin/python"))
    }

    func testDetectsLegacyBackend() throws {
        let c = try makeContainer()
        try FileManager.default.createDirectory(
            atPath: (c as NSString).appendingPathComponent("iterm2env"), withIntermediateDirectories: true)
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: c), .legacy)
        XCTAssertNil(iTermScriptRuntime.uvInterpreterPath(forScriptContainer: c))
    }

    func testNoneWhenEmpty() throws {
        let c = try makeContainer()
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: c), .none)
        XCTAssertNil(iTermScriptRuntime.uvInterpreterPath(forScriptContainer: c))
    }

    func testUvRequiresBothVenvAndMarker() throws {
        // A .venv without the marker (or vice versa) is not recognized as uv.
        let c1 = try makeContainer()
        try write((c1 as NSString).appendingPathComponent(".venv/bin/python"))
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: c1), .none)

        let c2 = try makeContainer()
        try write((c2 as NSString).appendingPathComponent("python-runtime.json"), "{}")
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: c2), .none)
    }

    func testUvTakesPrecedenceOverLegacy() throws {
        // Should not normally coexist (migration renames iterm2env to saved-iterm2env),
        // but if both are present the uv environment wins.
        let c = try makeContainer()
        try write((c as NSString).appendingPathComponent(".venv/bin/python"))
        try write((c as NSString).appendingPathComponent("python-runtime.json"), "{}")
        try FileManager.default.createDirectory(
            atPath: (c as NSString).appendingPathComponent("iterm2env"), withIntermediateDirectories: true)
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: c), .uv)
    }

    // MARK: - python-runtime.json marker

    func testMarkerRoundTripsWithSnakeCaseKeys() throws {
        let marker = iTermPythonRuntimeMarker(uvVersion: "0.12.0", python: "3.9", remappedFrom: "3.7")
        let data = try marker.jsonData()
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"uv_version\""))
        XCTAssertTrue(json.contains("\"remapped_from\""))
        XCTAssertFalse(json.contains("\"uvVersion\""))
        XCTAssertEqual(iTermPythonRuntimeMarker.from(jsonData: data), marker)
    }

    func testMarkerDefaultsSchemaAndBackend() throws {
        let marker = iTermPythonRuntimeMarker(uvVersion: "0.12.0", python: "3.11", remappedFrom: nil)
        XCTAssertEqual(marker.schema, 1)
        XCTAssertEqual(marker.backend, "uv")
        let decoded = try XCTUnwrap(iTermPythonRuntimeMarker.from(jsonData: marker.jsonData()))
        XCTAssertNil(decoded.remappedFrom)
        XCTAssertEqual(decoded.backend, "uv")
    }
}
