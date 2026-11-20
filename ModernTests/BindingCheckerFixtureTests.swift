//
//  BindingCheckerFixtureTests.swift
//  ModernTests
//
//  Proves that each checker of the binding tests (BindingCheckers.swift)
//  fails when what it protects breaks: each fixture below contains
//  deliberate breaks (a wrong class name, a wrong outlet, a wrong action, a
//  wrong key, and so on) and the test asserts that the checker reports
//  exactly those problems and nothing else. The runtime is a fake
//  (BindingFakeRuntime), so the fixtures name classes that do not exist in
//  the app.
//

import XCTest
import SQLite3

final class BindingCheckerFixtureTests: XCTestCase {
    private func keys(_ problems: [BindingProblem]) -> [String] {
        return problems.map(\.key).sorted()
    }

    private func methods(_ names: String...) -> Set<String> {
        return Set(names)
    }

    // MARK: - Key-value coding search order

    func testKVCSetterSearchOrder() {
        let runtime = BindingFakeRuntime(classes: [
            "NSObject": .init(),
            "Base": .init(superclass: "NSObject", instanceMethods: methods("setInherited:"), ivars: ["isFromBaseIvar"]),
            "Thing": .init(superclass: "Base",
                           instanceMethods: methods("setPlain:", "_setUnderscored:", "readonly", "customSetterName:"),
                           ivars: ["_ivarOnly", "_isFlag", "bare"],
                           propertyTypes: ["readonly": nil, "custom": nil]),
        ])
        let queries = BindingRuntimeQueries(runtime)
        XCTAssertEqual(queries.kvcSetter("Thing", key: "plain"), "-setPlain:")
        XCTAssertEqual(queries.kvcSetter("Thing", key: "underscored"), "-_setUnderscored:")
        XCTAssertEqual(queries.kvcSetter("Thing", key: "inherited"), "-setInherited:")
        XCTAssertEqual(queries.kvcSetter("Thing", key: "ivarOnly"), "ivar _ivarOnly")
        XCTAssertEqual(queries.kvcSetter("Thing", key: "flag"), "ivar _isFlag")
        XCTAssertEqual(queries.kvcSetter("Thing", key: "bare"), "ivar bare")
        XCTAssertEqual(queries.kvcSetter("Thing", key: "fromBaseIvar"), "ivar isFromBaseIvar")
        // A getter alone does not make a key settable, and a property whose
        // setter has another name is not found by key.
        XCTAssertNil(queries.kvcSetter("Thing", key: "readonly"))
        XCTAssertNil(queries.kvcSetter("Thing", key: "custom"))
    }

    func testKVCGetterSearchOrder() {
        let runtime = BindingFakeRuntime(classes: [
            "NSObject": .init(instanceMethods: ["self"]),
            "Thing": .init(superclass: "NSObject",
                           instanceMethods: methods("getAlpha", "beta", "isGamma", "_delta",
                                                    "countOfRows", "objectInRowsAtIndex:",
                                                    "countOfTags", "enumeratorOfTags", "memberOfTags:",
                                                    "countOfBroken"),
                           ivars: ["_epsilon"]),
        ])
        let queries = BindingRuntimeQueries(runtime)
        XCTAssertEqual(queries.kvcGetter("Thing", key: "alpha"), "-getAlpha")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "beta"), "-beta")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "gamma"), "-isGamma")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "delta"), "-_delta")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "rows"), "-countOfRows (indexed)")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "tags"), "-countOfTags (unordered)")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "epsilon"), "ivar _epsilon")
        XCTAssertEqual(queries.kvcGetter("Thing", key: "self"), "-self")
        // countOf<Key> without an element accessor is not enough.
        XCTAssertNil(queries.kvcGetter("Thing", key: "broken"))
        XCTAssertNil(queries.kvcGetter("Thing", key: "missing"))
    }

    func testPropertyTypeFromAttributes() {
        XCTAssertEqual(BindingObjCRuntime.objectClass(fromAttributes: "T@\"NSString\",C,N,V_name"), "NSString")
        XCTAssertEqual(BindingObjCRuntime.objectClass(fromAttributes: "T@\"NSView<Foo>\",W,N"), "NSView")
        XCTAssertNil(BindingObjCRuntime.objectClass(fromAttributes: "T@,&,N"))
        XCTAssertNil(BindingObjCRuntime.objectClass(fromAttributes: "T@\"<Foo>\",W,N"))
        XCTAssertNil(BindingObjCRuntime.objectClass(fromAttributes: "Tc,N,V_flag"))
    }

    // MARK: - Known failures table

    func testKnownFailureComparison() {
        func problem(_ file: String, _ name: String) -> BindingProblem {
            return BindingProblem(file: file, kind: "outlet", elementID: "1", label: nil, name: name, detail: "")
        }
        let problems = [problem("a.xib", "known"), problem("a.xib", "new")]
        let known = ["a.xib|outlet|1|known": "reason",
                     "a.xib|outlet|1|fixed": "reason",
                     "b.sdef|propertyKey|1|other": "reason"]
        let comparison = BindingKnownFailures.compare(problems, known: known) { $0.contains("|outlet|") }
        XCTAssertEqual(comparison.unexpected.map(\.key), ["a.xib|outlet|1|new"])
        XCTAssertEqual(comparison.nowPassing, ["a.xib|outlet|1|fixed"])
        XCTAssertNotNil(BindingKnownFailures.message(comparison))
        let clean = BindingKnownFailures.compare([problem("a.xib", "known")],
                                                 known: ["a.xib|outlet|1|known": "reason"]) { _ in true }
        XCTAssertNil(BindingKnownFailures.message(clean))
    }

    // MARK: - Xib

    private let xibFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <document type="com.apple.InterfaceBuilder3.Cocoa.XIB" version="3.0">
        <objects>
            <customObject id="-2" userLabel="File's Owner" customClass="FakeOwner">
                <connections>
                    <outlet property="goodOutlet" destination="btn" id="c1"/>
                    <outlet property="wrongOutlet" destination="btn" id="c2"/>
                    <outlet property="viaUnderscoreSetter" destination="btn" id="c3"/>
                    <outlet property="viaIsIvar" destination="btn" id="c4"/>
                    <outlet property="readonlyThing" destination="btn" id="c5"/>
                    <outlet property="dangling" destination="nowhere" id="c6"/>
                </connections>
            </customObject>
            <customObject id="-1" userLabel="First Responder" customClass="FirstResponder"/>
            <customObject id="-3" userLabel="Application" customClass="NSObject"/>
            <customObject id="obj" customClass="MissingClass"/>
            <customObject id="swift" customClass="SwiftThing" customModule="Mod"/>
            <customObject id="swiftBad" customClass="Gone" customModule="Mod"/>
            <customObject id="ctl" customClass="FakeController"/>
            <button id="btn" title="Press">
                <connections>
                    <action selector="goodAction:" target="-2" id="a1"/>
                    <action selector="wrongAction:" target="-2" id="a2"/>
                    <action selector="inherited:" target="ctl" id="a3"/>
                    <action selector="otherWrongAction:" target="ctl" id="a4"/>
                    <action selector="appAction:" target="-3" id="a5"/>
                    <action selector="copy:" target="-1" id="a6"/>
                    <action selector="unknown:" target="obj" id="a7"/>
                    <action selector="swiftAction:" target="swift" id="a8"/>
                    <binding destination="-2" name="value" keyPath="model.title" id="b1"/>
                    <binding destination="-2" name="enabled" keyPath="self.wrongKey" id="b2"/>
                    <binding destination="-2" name="hidden" keyPath="untyped.anything" id="b3"/>
                </connections>
            </button>
            <customView id="view" customClass="FakeView">
                <userDefinedRuntimeAttributes>
                    <userDefinedRuntimeAttribute type="boolean" keyPath="flag" value="YES"/>
                    <userDefinedRuntimeAttribute type="string" keyPath="wrongAttribute" value="x"/>
                </userDefinedRuntimeAttributes>
            </customView>
            <frobnicator id="weird">
                <connections>
                    <outlet property="x" destination="btn" id="c7"/>
                </connections>
            </frobnicator>
        </objects>
    </document>
    """

    private func xibRuntime() -> BindingFakeRuntime {
        return BindingFakeRuntime(
            classes: [
                "NSObject": .init(instanceMethods: ["self"]),
                "NSView": .init(superclass: "NSObject"),
                "NSButton": .init(superclass: "NSView"),
                "FakeOwner": .init(superclass: "NSObject",
                                   instanceMethods: methods("setGoodOutlet:", "_setViaUnderscoreSetter:", "goodAction:",
                                                            "readonlyThing", "model", "untyped", "setDangling:"),
                                   ivars: ["_isViaIsIvar"],
                                   propertyTypes: ["model": "FakeModel", "untyped": nil]),
                "FakeModel": .init(superclass: "NSObject", instanceMethods: ["title"]),
                "FakeBase": .init(superclass: "NSObject", instanceMethods: ["inherited:"]),
                "FakeController": .init(superclass: "FakeBase"),
                "FakeView": .init(superclass: "NSView", instanceMethods: ["setFlag:"]),
                "FakeApp": .init(superclass: "NSObject", instanceMethods: ["appAction:"]),
                "Mod.SwiftThing": .init(superclass: "NSObject", instanceMethods: ["swiftAction:"]),
            ],
            aliases: ["_TtC3Mod10SwiftThing": "Mod.SwiftThing"])
    }

    func testXibCheckerReportsExactlyTheBrokenNames() throws {
        let document = try BindingXibDocument.parse(Data(xibFixture.utf8), path: "Fixture.xib")
        let result = BindingXibChecker.check(document, queries: BindingRuntimeQueries(xibRuntime()), applicationClass: "FakeApp")
        XCTAssertEqual(keys(result.problems), [
            "Fixture.xib|action|btn|otherWrongAction:",
            "Fixture.xib|action|btn|wrongAction:",
            "Fixture.xib|binding|btn|self.wrongKey",
            "Fixture.xib|customClass|obj|MissingClass",
            "Fixture.xib|customClass|swiftBad|Mod.Gone",
            "Fixture.xib|elementClass|weird|NSFrobnicator",
            "Fixture.xib|outletDestination|-2|dangling",
            "Fixture.xib|outlet|-2|readonlyThing",
            "Fixture.xib|outlet|-2|wrongOutlet",
            "Fixture.xib|runtimeAttribute|view|wrongAttribute",
        ])
        // Failures name the file, the element id and label, and the name.
        let action = try XCTUnwrap(result.problems.first { $0.name == "wrongAction:" })
        XCTAssertEqual(action.label, "Press")
        XCTAssertTrue(action.description.contains("Fixture.xib"))
        XCTAssertTrue(action.description.contains("id=btn"))
        XCTAssertTrue(action.description.contains("FakeOwner"))
        let swift = try XCTUnwrap(result.problems.first { $0.name == "Mod.Gone" })
        XCTAssertTrue(swift.detail.contains("_TtC3Mod4Gone"), swift.detail)

        XCTAssertEqual(result.firstResponderActions.map(\.selector), ["copy:"])
        XCTAssertEqual(result.counts.customClasses, 6)
        XCTAssertEqual(result.counts.outlets, 7)
        XCTAssertEqual(result.counts.actionsToFileOwner, 2)
        XCTAssertEqual(result.counts.actionsToObjects, 4)
        XCTAssertEqual(result.counts.actionsToApplication, 1)
        XCTAssertEqual(result.counts.actionsToFirstResponder, 1)
        XCTAssertEqual(result.counts.bindings, 3)
        XCTAssertEqual(result.counts.runtimeAttributes, 2)
        // untyped.anything: the type of “untyped” is not a named class.
        XCTAssertEqual(result.counts.uncheckedDeeperKeys, 1)
    }

    func testXibCheckerIsCleanWhenEverythingResolves() throws {
        let runtime = xibRuntime()
        runtime.classes["MissingClass"] = .init(superclass: "NSObject", instanceMethods: ["unknown:"])
        runtime.classes["Mod.Gone"] = .init(superclass: "NSObject")
        runtime.aliases["_TtC3Mod4Gone"] = "Mod.Gone"
        runtime.classes["NSFrobnicator"] = .init(superclass: "NSObject", instanceMethods: ["setX:"])
        runtime.classes["FakeOwner"]?.instanceMethods.formUnion(["setWrongOutlet:", "setReadonlyThing:", "wrongAction:", "wrongKey"])
        runtime.classes["FakeController"]?.instanceMethods.insert("otherWrongAction:")
        runtime.classes["FakeView"]?.instanceMethods.insert("setWrongAttribute:")
        let source = xibFixture.replacingOccurrences(of: "destination=\"nowhere\"", with: "destination=\"btn\"")
        let document = try BindingXibDocument.parse(Data(source.utf8), path: "Fixture.xib")
        let result = BindingXibChecker.check(document, queries: BindingRuntimeQueries(runtime), applicationClass: "FakeApp")
        XCTAssertEqual(keys(result.problems), [])
    }

    func testStoryboardPlaceholders() throws {
        let storyboard = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.Cocoa.Storyboard.XIB" version="3.0">
            <scenes>
                <scene sceneID="s1">
                    <objects>
                        <application id="app">
                            <menu id="m">
                                <items>
                                    <menuItem title="Quit" id="q">
                                        <connections>
                                            <action selector="terminate:" target="fr" id="x1"/>
                                        </connections>
                                    </menuItem>
                                </items>
                            </menu>
                            <connections>
                                <outlet property="delegate" destination="del" id="x2"/>
                            </connections>
                        </application>
                        <customObject id="del" customClass="FakeDelegate"/>
                        <customObject id="fr" userLabel="First Responder" customClass="NSResponder" sceneMemberID="firstResponder"/>
                    </objects>
                </scene>
            </scenes>
        </document>
        """
        let runtime = BindingFakeRuntime(classes: [
            "NSObject": .init(),
            "FakeDelegate": .init(superclass: "NSObject"),
            "FakeApp": .init(superclass: "NSObject"),
        ])
        let document = try BindingXibDocument.parse(Data(storyboard.utf8), path: "Fixture.storyboard")
        let result = BindingXibChecker.check(document, queries: BindingRuntimeQueries(runtime), applicationClass: "FakeApp")
        // The application's outlets are checked on the principal class, not
        // on NSApplication or on the element's customClass.
        XCTAssertEqual(keys(result.problems), ["Fixture.storyboard|outlet|app|delegate"])
        XCTAssertEqual(result.firstResponderActions.map(\.selector), ["terminate:"])
        XCTAssertEqual(result.counts.customClasses, 1)
    }

    // MARK: - First Responder

    func testFirstResponderCheckerReportsUnimplementedActionsAndTableChanges() {
        let runtime = BindingFakeRuntime(classes: [:], implementers: [
            "copy:": BindingImplementers(app: [], system: ["NSText"]),
            "newThing:": BindingImplementers(app: ["New"], system: []),
            "same:": BindingImplementers(app: ["A", "B"], system: []),
        ])
        let actions = [
            BindingFirstResponderAction(file: "Menu.xib", elementID: "1", label: "Copy", selector: "copy:"),
            BindingFirstResponderAction(file: "Menu.xib", elementID: "2", label: "New", selector: "newThing:"),
            BindingFirstResponderAction(file: "Menu.xib", elementID: "3", label: "Nothing", selector: "nothing:"),
            BindingFirstResponderAction(file: "Menu.xib", elementID: "4", label: "Same", selector: "same:"),
        ]
        let recorded = ["copy:": [], "newThing:": ["Old"], "same:": ["A", "B"], "stale:": ["X"]]
        let result = BindingFirstResponderChecker.check(actions, runtime: runtime, recorded: recorded)
        XCTAssertEqual(keys(result.problems), ["Menu.xib|firstResponderAction|3|nothing:"])
        XCTAssertEqual(result.tableDifferences, [
            "newThing:: implementers added [\"New\"], removed [\"Old\"]",
            "nothing:: not in the recorded table; app implementers now []",
            "stale:: recorded, but no First Responder action uses it any more",
        ])
        XCTAssertEqual(result.pasteLines, [
            "replace:         \"newThing:\": [\"New\"],",
            "add:             \"nothing:\": [],",
            "remove:          \"stale:\": [\"X\"],",
        ])
    }

    // MARK: - Scripting definition

    func testSdefCheckerReportsExactlyTheBrokenNames() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary title="Fixture">
          <suite name="S" code="SSSS">
            <command name="good" code="aaaabbbb"><cocoa class="GoodCommand"/></command>
            <command name="bad" code="aaaacccc"><cocoa class="NotACommand"/></command>
            <command name="missing" code="aaaadddd"><cocoa class="NoSuchCommand"/></command>
            <command name="plain" code="aaaaeeee"/>
            <value-type name="v" code="vvvv"><cocoa class="NoSuchValue"/></value-type>
            <class name="thing" code="thng"><cocoa class="FakeThing"/>
              <property name="title" code="titl" type="text"><cocoa key="title"/></property>
              <property name="read only name" code="rona" type="text" access="r"/>
              <property name="size" code="size" type="integer"><cocoa key="size"/></property>
              <property name="gone" code="gone" type="text" access="r"><cocoa key="goneKey"/></property>
              <element type="part" access="r"/>
              <element type="widget" access="r"><cocoa key="widgets"/></element>
              <responds-to command="good"><cocoa method="handleGood:"/></responds-to>
              <responds-to command="plain"><cocoa method="handleMissing:"/></responds-to>
              <responds-to command="nonexistent"/>
            </class>
            <class name="part" code="part" plural="parts"><cocoa class="NoSuchPart"/></class>
            <class name="proxy" code="prox"><cocoa class="FakeProxy"/>
              <property name="frame" code="fram" type="rectangle" access="r"><cocoa key="frame"/></property>
              <responds-to command="good"><cocoa method="handleGood:"/></responds-to>
            </class>
          </suite>
        </dictionary>
        """
        let runtime = BindingFakeRuntime(classes: [
            "NSObject": .init(),
            "NSScriptCommand": .init(superclass: "NSObject"),
            "GoodCommand": .init(superclass: "NSScriptCommand"),
            "NotACommand": .init(superclass: "NSObject"),
            "FakeThing": .init(superclass: "NSObject",
                               instanceMethods: methods("title", "setTitle:", "readOnlyName", "size",
                                                        "countOfParts", "objectInPartsAtIndex:", "handleGood:")),
            "FakeProxy": .init(),
            "TargetA": .init(superclass: "NSObject", instanceMethods: methods("frame", "handleGood:")),
            "TargetB": .init(superclass: "NSObject", instanceMethods: methods("handleGood:")),
        ])
        let root = try BindingXMLParser.parse(Data(sdef.utf8), path: "Fixture.sdef")
        let result = BindingSdefChecker.check(root, path: "Fixture.sdef", queries: BindingRuntimeQueries(runtime)) {
            $0 == "FakeProxy" ? ["TargetA", "TargetB"] : nil
        }
        XCTAssertEqual(keys(result.problems), [
            "Fixture.sdef|class|class part|NoSuchPart",
            "Fixture.sdef|commandClass|command bad|NotACommand",
            "Fixture.sdef|commandClass|command missing|NoSuchCommand",
            "Fixture.sdef|elementKey|class thing|widgets",
            "Fixture.sdef|propertyKey|class proxy|frame",
            "Fixture.sdef|propertyKey|class thing|goneKey",
            "Fixture.sdef|propertySetter|class thing|size",
            "Fixture.sdef|respondsToCommand|class thing|nonexistent",
            "Fixture.sdef|respondsToMethod|class thing|handleMissing:",
            "Fixture.sdef|valueTypeClass|value-type v|NoSuchValue",
        ])
        let proxy = try XCTUnwrap(result.problems.first { $0.name == "frame" })
        XCTAssertTrue(proxy.detail.contains("TargetB"), proxy.detail)
        XCTAssertEqual(result.counts.classes, 3)
        XCTAssertEqual(result.counts.properties, 5)
        XCTAssertEqual(result.counts.elements, 2)
        XCTAssertEqual(result.counts.respondsTo, 4)
        XCTAssertEqual(result.counts.commands, 4)
        XCTAssertEqual(result.counts.commandClasses, 3)
    }

    func testSdefKeyNaming() {
        XCTAssertEqual(BindingSdefChecker.camelCase("current window"), "currentWindow")
        XCTAssertEqual(BindingSdefChecker.camelCase("name"), "name")
        XCTAssertEqual(BindingSdefChecker.camelCase("ANSI black color"), "ansiBlackColor")
    }

    // MARK: - Info.plist

    func testInfoPlistCheckerReportsExactlyTheBrokenNames() {
        let runtime = BindingFakeRuntime(classes: [
            "NSObject": .init(),
            "FakeApp": .init(superclass: "NSObject"),
            "FakeProvider": .init(superclass: "NSObject", instanceMethods: ["openTab:userData:error:"]),
        ])
        let plist: [String: Any] = [
            "NSPrincipalClass": "FakeApp",
            "NSServices": [["NSMessage": "openTab"], ["NSMessage": "missing"]],
            "CFBundleDocumentTypes": [["NSDocumentClass": "NoSuchDocument"], ["CFBundleTypeName": "x"]],
        ]
        let result = BindingInfoPlistChecker.check(plist, file: "Info.plist", queries: BindingRuntimeQueries(runtime), servicesProvider: "FakeProvider")
        XCTAssertEqual(keys(result.problems), [
            "Info.plist|documentClass|CFBundleDocumentTypes[0]|NoSuchDocument",
            "Info.plist|principalClass|NSPrincipalClass|FakeApp",
            "Info.plist|serviceMessage|NSServices[1]|missing:userData:error:",
        ])
        XCTAssertEqual(result.counts.services, 2)
        XCTAssertEqual(result.counts.documentTypes, 2)
        XCTAssertEqual(result.counts.documentClasses, 1)
    }

    // MARK: - Core Data

    func testCoreDataCheckerReportsExactlyTheBrokenNames() throws {
        let model = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0">
            <entity name="Good" representedClassName="GoodMO" syncable="YES"/>
            <entity name="Bad" representedClassName="NoSuchMO" syncable="YES"/>
            <entity name="NotManaged" representedClassName="PlainObject" syncable="YES"/>
            <entity name="Plain" syncable="YES"/>
        </model>
        """
        let runtime = BindingFakeRuntime(classes: [
            "NSObject": .init(),
            "NSManagedObject": .init(superclass: "NSObject"),
            "GoodMO": .init(superclass: "NSManagedObject"),
            "PlainObject": .init(superclass: "NSObject"),
        ])
        let root = try BindingXMLParser.parse(Data(model.utf8), path: "contents")
        let result = BindingCoreDataChecker.check(root, file: "contents", queries: BindingRuntimeQueries(runtime))
        XCTAssertEqual(keys(result.problems), [
            "contents|entityClass|entity Bad|NoSuchMO",
            "contents|entityClass|entity NotManaged|PlainObject",
        ])
        XCTAssertEqual(result.entities, 4)
    }

    // MARK: - Persisted and wire names

    func testPersistedNamesCheckerReportsExactlyTheBrokenNames() {
        let runtime = BindingFakeRuntime(
            classes: [
                "NSObject": .init(),
                "Good": .init(superclass: "NSObject"),
                "Mod.Swift": .init(superclass: "NSObject"),
                "Mod.Old": .init(superclass: "NSObject"),
                "R1": .init(superclass: "NSObject", classMethods: ["restore:"]),
                "R2": .init(superclass: "NSObject"),
            ],
            aliases: ["Old": "Mod.Old"],
            protocols: ["P": ["a:"]])
        let problems = BindingPersistedNamesChecker.check(
            names: [
                .init(name: "Good", runtimeName: "Good", kind: .persisted),
                .init(name: "Swift", runtimeName: "Mod.Swift", kind: .persisted),
                .init(name: "Renamed", runtimeName: "Old", kind: .persisted),
                .init(name: "Missing", runtimeName: "Missing", kind: .xpc),
            ],
            protocols: [("P", ["a:", "b:"]), ("Q", ["c:", "d:"])],
            restorationClasses: ["R1", "R2", "R3"],
            restorationSelector: "restore:",
            queries: BindingRuntimeQueries(runtime))
        let file = BindingPersistedNamesChecker.file
        XCTAssertEqual(keys(problems), [
            "\(file)|persistedName|names table: Missing (xpc)|Missing",
            "\(file)|persistedName|names table: Renamed (persisted)|Old",
            "\(file)|restorationClass|window restoration|R2",
            "\(file)|restorationClass|window restoration|R3",
            "\(file)|xpcProtocol|protocol Q|Q",
            "\(file)|xpcSelector|protocol P|b:",
        ])
    }

    // MARK: - Keyed archives

    private func archiveData(renaming className: String) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName(className, for: NSMutableArray.self)
        archiver.encode(NSMutableArray(array: ["text"]), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func archiveRuntime(_ names: [String]) -> BindingFakeRuntime {
        var classes = [String: BindingClassInfo]()
        for name in names where name.hasPrefix("NS") {
            classes[name] = .init()
        }
        return BindingFakeRuntime(classes: classes)
    }

    func testArchiveScannerFindsNestedArchivesAndReportsUnknownClasses() throws {
        let archive = try archiveData(renaming: "NoSuchArchivedClass")
        let plist: [String: Any] = ["nested": archive, "list": [archive, "not data"], "number": 3]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let archives = BindingArchiveScanner.archives(inData: data, file: "fixture.plist", location: "<root>")
        XCTAssertEqual(archives.map(\.location), ["<root>/list/0/<data>", "<root>/nested/<data>"])
        XCTAssertTrue(archives[0].classNames.contains("NoSuchArchivedClass"), "\(archives[0].classNames)")
        let problems = BindingArchiveScanner.check(archives, runtime: archiveRuntime(archives.flatMap(\.classNames)))
        // One problem per file and class name.
        XCTAssertEqual(keys(problems), ["fixture.plist|archiveClass|archive|NoSuchArchivedClass"])

        // A top-level archive file is an archive at its root.
        let top = BindingArchiveScanner.archives(inData: archive, file: "top.plist", location: "<root>")
        XCTAssertEqual(top.map(\.location), ["<root>"])

        // Without the rename every class resolves.
        let clean = try archiveData(renaming: "NSMutableArray")
        let cleanArchives = BindingArchiveScanner.archives(inData: clean, file: "clean.plist", location: "<root>")
        XCTAssertEqual(keys(BindingArchiveScanner.check(cleanArchives, runtime: archiveRuntime(cleanArchives.flatMap(\.classNames)))), [])
    }

    func testArchiveScannerReadsSQLiteBlobsWithoutTouchingTheOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("binding-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("fixture.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE t (id INTEGER PRIMARY KEY, data BLOB, txt TEXT)", nil, nil, nil), SQLITE_OK)
        let archive = try archiveData(renaming: "NoSuchArchivedClass")
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO t (data, txt) VALUES (?, 'plain text')", -1, &statement, nil), SQLITE_OK)
        _ = archive.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

        let archives = try BindingArchiveScanner.archives(inSQLiteAt: url, file: "fixture.sqlite")
        XCTAssertEqual(archives.map(\.location), ["table t rowid 1 column data"])
        let problems = BindingArchiveScanner.check(archives, runtime: archiveRuntime(archives.flatMap(\.classNames)))
        XCTAssertEqual(keys(problems), ["fixture.sqlite|archiveClass|archive|NoSuchArchivedClass"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
    }

    // Name, size and modification time of every file in a directory.
    private func listing(_ directory: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
            .map { url in
                let values = try url.resourceValues(forKeys: Set(keys))
                let modified = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1
                return "\(url.lastPathComponent) \(values.fileSize ?? -1) \(modified)"
            }
            .sorted()
    }

    // A database left in WAL mode with a write that is only in the -wal file:
    // the scan sees that write, and the source directory is unchanged.
    func testArchiveScannerReadsUncheckpointedWALWithoutTouchingTheOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("binding-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("fixture.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        // The writer stays open until the scan is done: closing the last
        // connection would checkpoint the write into the main file.
        defer {
            sqlite3_close(db)
        }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE t (id INTEGER PRIMARY KEY, data BLOB); PRAGMA wal_checkpoint(TRUNCATE); PRAGMA wal_autocheckpoint=0", nil, nil, nil), SQLITE_OK)
        let archive = try archiveData(renaming: "NoSuchArchivedClass")
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO t (data) VALUES (?)", -1, &statement, nil), SQLITE_OK)
        _ = archive.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
        let walSize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path + "-wal")[.size] as? Int)
        XCTAssertGreaterThan(walSize, 0, "the write should be in the -wal file only")
        let before = try listing(directory)

        let archives = try BindingArchiveScanner.archives(inSQLiteAt: url, file: "fixture.sqlite")
        XCTAssertEqual(archives.map(\.location), ["table t rowid 1 column data"])
        XCTAssertEqual(try listing(directory), before)
    }
}
