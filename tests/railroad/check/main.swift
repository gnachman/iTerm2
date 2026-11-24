// Compares the Swift railroad port with the Rust reference SVGs.
// Run: tests/railroad/check-swift-port.sh [fixture names...]
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let css = try! String(contentsOf: root.appendingPathComponent("light.css"), encoding: .utf8)
let dslDir = root.appendingPathComponent("dsl")
let names = try! FileManager.default.contentsOfDirectory(atPath: dslDir.path)
    .filter { $0.hasSuffix(".dsl") && (CommandLine.arguments.count < 3 || CommandLine.arguments[2...].contains(String($0.dropLast(4)))) }.sorted()
var failures = 0
for name in names {
    let base = String(name.dropLast(4))
    let dsl = try! String(contentsOf: dslDir.appendingPathComponent(name), encoding: .utf8)
    let expected = try! String(contentsOf: root.appendingPathComponent("svg/\(base).svg"), encoding: .utf8)
    let actual: String
    do {
        actual = try RailroadDSL.svg(dsl, css: css)
    } catch {
        print("FAIL \(base): parse error \(error)")
        failures += 1
        continue
    }
    if actual == expected {
        continue
    }
    failures += 1
    let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
    let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
    let i = (0..<min(a.count, e.count)).first { a[$0] != e[$0] } ?? min(a.count, e.count)
    print("FAIL \(base): first difference at line \(i + 1)")
    print("  expected: \(i < e.count ? String(e[i]) : "<end>")")
    print("  actual:   \(i < a.count ? String(a[i]) : "<end>")")
}
print("\(names.count - failures)/\(names.count) match")
exit(failures == 0 ? 0 : 1)
