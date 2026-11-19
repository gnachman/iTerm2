// Uses of the bridging header's declarations, so that the fixture module
// imports them as the app does.
import Foundation

class ObjCUser: NSObject {
    @objc func use(_ t: SIFObjCThing) throws {
        try t.save(toPath: "/dev/null")
        t.newName(x: 3)
        try t.load(from: "/dev/null", error: ())
    }
}
