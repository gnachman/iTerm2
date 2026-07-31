//
//  iTermUvCommand.swift
//  iTerm2SharedARC
//
//  Phase 1 of the uv Python-runtime migration. Pure builders for uv command lines
//  and the provision-time environment, kept free of side effects so they can be
//  unit-tested. The subprocess execution, download, and signature verification
//  live in the (injectable) runner and are exercised by the e2e harness. See
//  docs/uv-python-runtime-migration.md (Phase 1).
//

import Foundation

enum iTermUvCommand {
    // Environment set on every uv subprocess. only-managed forces
    // python-build-standalone and never a system/Homebrew interpreter; no-config
    // ignores the user's uv.toml; clone gives APFS copy-on-write dedup of packages
    // from the cache. These are set at provision time only; launching a script is a
    // bare exec of the venv's python and involves no uv.
    static func provisionEnvironment(pythonInstallDir: String,
                                     cacheDir: String) -> [String: String] {
        return [
            "UV_PYTHON_INSTALL_DIR": pythonInstallDir,
            "UV_CACHE_DIR": cacheDir,
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_CONFIG": "1",
            "UV_PYTHON_DOWNLOADS": "automatic",
            "UV_LINK_MODE": "clone",
        ]
    }

    // Create a virtual environment at venvPath using the given Python version
    // (uv downloads that python-build-standalone interpreter if needed).
    // --relocatable keeps the venv working if the script folder is later moved or
    // renamed (and lets the import path provision then move it into place), by using
    // relative paths in console-script shebangs rather than baking in the venv path.
    static func venvArgs(pythonVersion: String, venvPath: String) -> [String] {
        return ["venv", "--relocatable", "--python", pythonVersion, venvPath]
    }

    // Install packages into an existing venv, wheels only. --only-binary :all: is
    // what enforces the no-compiler guarantee: a source-only dependency fails
    // loudly instead of silently trying to build.
    static func pipInstallArgs(venvPythonPath: String, packages: [String], upgrade: Bool = false) -> [String] {
        var arguments = ["pip", "install", "--python", venvPythonPath, "--only-binary", ":all:"]
        if upgrade {
            arguments.append("--upgrade")
        }
        return arguments + packages
    }

    // List interpreters uv knows about (installed and downloadable) as JSON, used
    // to discover which minor versions python-build-standalone offers for remap.
    static func pythonListArgs() -> [String] {
        return ["python", "list", "--all-versions", "--output-format", "json"]
    }

    // Run a pip subcommand (e.g. ["show", "requests"], ["install", "requests"],
    // ["install", "requests", "--upgrade"], ["uninstall", "requests"]) through uv pip
    // against a specific venv. `install` is forced wheels-only so a source-only
    // dependency fails loudly rather than needing a compiler, matching provisioning.
    static func pipPassthroughArgs(pipArguments: [String], venvPythonPath: String) -> [String] {
        var arguments = ["pip"] + pipArguments
        if pipArguments.first == "install" {
            arguments += ["--only-binary", ":all:"]
        }
        arguments += ["--python", venvPythonPath]
        return arguments
    }
}
