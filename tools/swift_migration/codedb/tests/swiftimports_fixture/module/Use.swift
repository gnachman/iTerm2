// The swiftimports fixture module's one Swift file: it uses imported
// declarations as callers would.
import Foundation

func useProbe() -> Int {
    let p = Probe(title: "x")
    p.title = "y"
    p.extraThing()
    p.setTags(["a"])
    return p.count + p.__refinedValue() + Int(PROBE_LIMIT)
}
