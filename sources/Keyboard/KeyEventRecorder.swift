//
//  KeyEventRecorder.swift
//  iTerm2
//
//  Created by George Nachman on 3/16/25.
//
// This is used to generate recorded-keys.json for automatic execution of modern-key-reporting-test.py.

private struct KeyRecord: Codable, CustomDebugStringConvertible {
    var characters: String?
    var charactersIgnoringModifiers: String?
    var keyCode: Int
    var modifierFlags: UInt
    var timestamp: TimeInterval
    var isARepeat: Bool

    var debugDescription: String {
        return "<KeyRecord: characters=\(characters ?? "(nil)") charactersIgnoringModifiers=\(charactersIgnoringModifiers ?? "(nil)") keyCode=\(keyCode) modifierFlags=\(modifierFlags) timestamp=\(timestamp) isARepeat=\(isARepeat)>"
    }

    init(_ event: NSEvent) {
        self.characters = event.characters
        self.charactersIgnoringModifiers = event.charactersIgnoringModifiers
        self.keyCode = Int(event.keyCode)
        self.modifierFlags = event.modifierFlags.rawValue
        self.timestamp = event.timestamp
        self.isARepeat = event.isARepeat
    }

    private func createCGEvent(keyDown: Bool) -> CGEvent? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
        event?.flags = CGEventFlags(rawValue: UInt64(modifierFlags))

        // Special handling for space when Control is held
        if let chars = characters {
            let unicodeScalars = chars.unicodeScalars.map { UniChar($0.value) }
            var mutableScalars = unicodeScalars
            event?.keyboardSetUnicodeString(stringLength: unicodeScalars.count, unicodeString: &mutableScalars)
        }

        return event
    }

    func keyDownEvent(windowNumber: Int) -> NSEvent {
        if keyCode == 49 && modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0 {
            return NSEvent(cgEvent: createCGEvent(keyDown: true)!)!
        }
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags),
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            characters: characters ?? "",
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? "",
            isARepeat: isARepeat,
            keyCode: UInt16(keyCode)
        )!
    }

    func keyUpEvent(windowNumber: Int) -> NSEvent {
        if keyCode == 49 && modifierFlags & NSEvent.ModifierFlags.control.rawValue != 0 {
            return NSEvent(cgEvent: createCGEvent(keyDown: false)!)!
        }
        return NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags),
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            characters: characters ?? "",
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? "",
            isARepeat: isARepeat,
            keyCode: UInt16(keyCode)
        )!
    }
}

private struct FlagsChangedRecord: Codable {
    var modifierFlags: UInt
    var timestamp: TimeInterval
    var keyCode: Int

    init(_ event: NSEvent) {
        self.modifierFlags = event.modifierFlags.rawValue
        self.timestamp = event.timestamp
        self.keyCode = Int(event.keyCode)
    }

    func event(windowNumber: Int) -> NSEvent {
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(keyCode), keyDown: false) else {
            it_fatalError("Failed to create CGEvent")
        }
        cgEvent.flags = CGEventFlags(rawValue: UInt64(modifierFlags))
        cgEvent.type = .flagsChanged

        return NSEvent(cgEvent: cgEvent)!
    }
}

private enum RecordedEvent: Codable {
    case keyDown(KeyRecord)
    case keyUp(KeyRecord)
    case flagsChanged(FlagsChangedRecord)
    case intr
}

@objc(iTermKeyEventRecorder)
class KeyEventRecorder: NSObject {
    @objc private(set) static var instance: KeyEventRecorder?
    private var journal = [RecordedEvent]()

    @objc static func enable() {
        NSLog("Begin recording")
        instance = KeyEventRecorder()
    }
    @objc static func disable() {
        NSLog("Stop recording")
        instance?.close()
        instance = nil
    }
    @objc static func toggle() {
        if instance == nil {
            enable()
        } else {
            disable()
        }
    }

    @objc(record:)
    func record(event: NSEvent) {
        NSLog("Record \(event.description)")
        switch event.type {
        case .keyDown:
            journal.append(.keyDown(KeyRecord(event)))
        case .keyUp:
            journal.append(.keyUp(KeyRecord(event)))
        case .flagsChanged:
            journal.append(.flagsChanged(FlagsChangedRecord(event)))
        default:
            break
        }
    }

    @objc
    func recordIntr() {
        NSLog("Record SIGINT")
        journal.append(.intr)
    }

    private func close() {
        NSLog("Write journal")
        let json = try! JSONEncoder().encode(journal)
        try! json.write(to: URL(fileURLWithPath:"/tmp/recorded-keys.json"), options: [])
        journal = []
    }
}

@objc(iTermKeyEventReplayer)
class KeyEventReplayer: NSObject {
    private let journal: [RecordedEvent]
    private let windowNumber: Int
    private var nextIndex = 0
    private var timer: Timer?
    private let pid: pid_t
    private static var activeCount = 0

    @objc static var isReplaying: Bool {
        return activeCount > 0
    }

    @objc init?(path: String, windowNumber: Int, pid: pid_t) {
        self.windowNumber = windowNumber
        self.pid = pid
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            self.journal = try JSONDecoder().decode([RecordedEvent].self, from: data)
        } catch {
            return nil
        }
    }

    @objc
    func start() {
        Self.activeCount += 1
        NSLog("Start replay using pid \(pid) and window \(windowNumber)")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            if !self.next() {
                self.stop()
            }
        }
    }

    @objc
    func stop() {
        NSLog("Stop replay")
        Self.activeCount -= 1
        timer?.invalidate()
        timer = nil
        nextIndex = 0
    }

    private func next() -> Bool {
        guard nextIndex < journal.count else {
            return false
        }

        let record = journal[nextIndex]
        nextIndex += 1

        var event: NSEvent? = nil
        switch record {
        case .keyDown(let keyRecord):
            event = keyRecord.keyDownEvent(windowNumber: windowNumber)
        case .keyUp(let keyRecord):
            event = keyRecord.keyUpEvent(windowNumber: windowNumber)
        case .flagsChanged(let flagsRecord):
            event = flagsRecord.event(windowNumber: windowNumber)
        case .intr:
            NSLog("Send SIGINT to \(pid)")
            kill(pid, SIGINT)
        }

        if let event {
            print("\(record)")
            inject(event)
        }
        return true
    }

    private func inject(_ event: NSEvent) {
        print("Inject \(event.it_addressString): \(event)")
//        event.cgEvent?.post(tap: .cghidEventTap)
        NSApp.postEvent(event, atStart: false)
//        NSApp.sendEvent(event)
    }
}
