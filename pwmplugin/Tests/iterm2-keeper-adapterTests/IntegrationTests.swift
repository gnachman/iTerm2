import XCTest
import Foundation

final class KeeperIntegrationTests: XCTestCase {
    private final class MockKeeperServer {
        private let process: Process
        let baseURL: String

        init(scenario: String = "ok") throws {
            let script = """
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCENARIO = os.environ.get("SCENARIO", "ok")
REQUESTS = {}

def _send(handler, code, obj):
    payload = json.dumps(obj).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)

class H(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_POST(self):
        if self.path.endswith("/executecommand-async"):
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length).decode("utf-8")
            body = json.loads(raw) if raw else {}
            cmd = body.get("command", "")
            if SCENARIO == "async_error":
                _send(self, 401, {"error": "bad api key"})
                return
            req_id = str(len(REQUESTS) + 1)
            REQUESTS[req_id] = cmd
            _send(self, 202, {"request_id": req_id, "status": "queued"})
            return
        _send(self, 404, {"error": "not found"})

    def do_GET(self):
        if "/status/" in self.path:
            if SCENARIO == "status_failed":
                _send(self, 200, {"status": "failed"})
            else:
                _send(self, 200, {"status": "completed"})
            return
        if "/result/" in self.path:
            req_id = self.path.rsplit("/", 1)[-1]
            cmd = REQUESTS.get(req_id, "")
            if cmd.startswith("ls "):
                result = {"command": "ls", "data": {"records": [
                    {"title": "1  UIDAAAAAAAAAAAAAA  login  Web  user@example.com @ https://testbook.com"},
                    {"title": "2  UID1234567890123  login  Mysql  hborase@keepersecurity.com @ 127.0.0.1:3366"}
                ]}}
                _send(self, 200, {"status": "success", "result": json.dumps(result)})
                return
            if " --format=json" in cmd and cmd.startswith("get "):
                _send(self, 200, {"record": {"password": "pw-123", "login": "user@example.com"}})
                return
            if " --format=password" in cmd and cmd.startswith("get "):
                _send(self, 200, "pw-123")
                return
            if cmd.startswith("record-update "):
                if SCENARIO == "set_password_error":
                    _send(self, 200, {"error": "password invalid"})
                else:
                    _send(self, 200, {"status": "success"})
                return
            if cmd.startswith("record-add "):
                _send(self, 200, {"status": "success", "data": {"record_uid": "NEWUID1234567890"}})
                return
            if cmd.startswith("rm -f "):
                _send(self, 200, {"status": "success"})
                return
            if cmd == "sync-down":
                _send(self, 200, {"status": "success"})
                return
            _send(self, 200, {"status": "success"})
            return
        _send(self, 404, {"error": "not found"})

server = ThreadingHTTPServer(("127.0.0.1", 0), H)
print(server.server_port, flush=True)
server.serve_forever()
"""
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = ["-c", script]
            proc.environment = ["SCENARIO": scenario]
            let output = Pipe()
            proc.standardOutput = output
            proc.standardError = output
            try proc.run()
            let data = output.fileHandleForReading.availableData
            guard let line = String(data: data, encoding: .utf8)?
                    .split(separator: "\n")
                    .first,
                  let port = Int(line) else {
                proc.terminate()
                throw NSError(domain: "KeeperTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not start mock server"])
            }
            self.process = proc
            self.baseURL = "http://127.0.0.1:\(port)"
        }

        deinit {
            process.terminate()
        }
    }

    private var adapterURL: URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("iterm2-keeper-adapter")
    }

    private func run(_ subcommand: String, input: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = adapterURL
        process.arguments = [subcommand]

        let stdin = Pipe()
        let output = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = output
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func token(_ value: String = "api-key") -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func header(_ baseURL: String) -> String {
        #"{"pathToDatabase":"\#(baseURL)","pathToExecutable":null,"mode":"terminal"}"#
    }

    private func decodeJSON(_ text: String) throws -> [String: Any] {
        let payload = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    }

    func testHandshakeSuccess() throws {
        let input = #"{"iTermVersion":"3.5.0","minProtocolVersion":0,"maxProtocolVersion":0}"#
        let result = try run("handshake", input: input)
        XCTAssertEqual(result.status, 0, result.output)
        let payload = try XCTUnwrap(result.output.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        XCTAssertEqual(json?["protocolVersion"] as? Int, 0)
        XCTAssertEqual(json?["name"] as? String, "Keeper Security")
    }

    func testHandshakeRejectsNegativeProtocol() throws {
        let input = #"{"iTermVersion":"3.5.0","minProtocolVersion":0,"maxProtocolVersion":-1}"#
        let result = try run("handshake", input: input)
        XCTAssertNotEqual(result.status, 0, result.output)
        let payload = try XCTUnwrap(result.output.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "Protocol version 0 is required")
    }

    func testLoginSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"masterPassword":"api-key"}"#
        let result = try run("login", input: input)
        XCTAssertEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        XCTAssertEqual(json["token"] as? String, token())
    }

    func testListAccountsSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())"}"#
        let result = try run("list-accounts", input: input)
        XCTAssertEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        let accounts = try XCTUnwrap(json["accounts"] as? [[String: Any]])
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts[0]["userName"] as? String, "user@example.com")
        XCTAssertEqual(accounts[1]["userName"] as? String, "hborase@keepersecurity.com")
    }

    func testGetPasswordSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())","accountIdentifier":{"accountID":"UID1234567890123"}}"#
        let result = try run("get-password", input: input)
        XCTAssertEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        XCTAssertEqual(json["password"] as? String, "pw-123")
    }

    func testSetPasswordSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())","accountIdentifier":{"accountID":"UID1234567890123"},"newPassword":"new-pass"}"#
        let result = try run("set-password", input: input)
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testAddAccountSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())","userName":"user@example.com","accountName":"Example","password":"new-pass"}"#
        let result = try run("add-account", input: input)
        XCTAssertEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        let accountIdentifier = try XCTUnwrap(json["accountIdentifier"] as? [String: Any])
        XCTAssertEqual(accountIdentifier["accountID"] as? String, "NEWUID1234567890")
    }

    func testDeleteAccountSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())","accountIdentifier":{"accountID":"UID1234567890123"}}"#
        let result = try run("delete-account", input: input)
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testKeeperSyncDownSuccess() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())","commandName":"sync-down"}"#
        let result = try run("sync-down", input: input)
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testListAccountsInvalidTokenFails() throws {
        let server = try MockKeeperServer()
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"not-base64"}"#
        let result = try run("list-accounts", input: input)
        XCTAssertNotEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        XCTAssertEqual(json["error"] as? String, "Invalid or missing API key")
    }

    func testLoginHTTPErrorUsesHumanReadableError() throws {
        let server = try MockKeeperServer(scenario: "async_error")
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"masterPassword":"api-key"}"#
        let result = try run("login", input: input)
        XCTAssertNotEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        XCTAssertEqual(json["error"] as? String, "bad api key")
    }

    func testSetPasswordErrorMapsToUserFacingMessage() throws {
        let server = try MockKeeperServer(scenario: "set_password_error")
        let input = #"{"header":\#(header(server.baseURL)),"userAccountID":null,"token":"\#(token())","accountIdentifier":{"accountID":"UID1234567890123"},"newPassword":"new-pass"}"#
        let result = try run("set-password", input: input)
        XCTAssertNotEqual(result.status, 0, result.output)
        let json = try decodeJSON(result.output)
        XCTAssertEqual(json["error"] as? String, "Password field is required.")
    }
}
