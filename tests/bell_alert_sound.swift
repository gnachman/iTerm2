#!/usr/bin/env swift
//
// Manual test: does AudioServicesPlayAlertSound give a custom sound file the same
// treatment as NSBeep()? Plays each way in turn so you can compare by eye and ear.
//
// Usage: swift tests/bell_alert_sound.swift [path/to/sound]
//
// Before running, in System Settings:
//   - Accessibility > Audio: turn on “Flash the screen when an alert sound occurs”
//   - Sound: set Alert volume low (for example 10%)
//   - Sound: set “Play sound effects through” to a different device than Output
//     (for example built-in speakers while output goes to headphones)
//
// For each step, note whether the screen flashed, how loud it was, and which device
// played it. Step 1 is the reference; step 3 is the candidate.

import AppKit
import AudioToolbox

let path = CommandLine.arguments.dropFirst().first ?? "/System/Library/Sounds/Glass.aiff"
let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

func pause(_ message: String) {
    print("\n\(message)\nPress Return to play.", terminator: "")
    _ = readLine()
}

func waitForCompletion(_ play: (@escaping () -> Void) -> Void) {
    let done = DispatchSemaphore(value: 0)
    play { done.signal() }
    if done.wait(timeout: .now() + 10) == .timedOut {
        print("(no completion after 10 seconds)")
    }
}

let volume = CFPreferencesCopyAppValue("com.apple.sound.beep.volume" as CFString,
                                       kCFPreferencesAnyApplication)
let flash = CFPreferencesCopyAppValue("flashScreen" as CFString,
                                      "com.apple.universalaccess" as CFString)
print("Sound file: \(url.path)")
print("com.apple.sound.beep.volume = \(volume.map { "\($0)" } ?? "(missing)")")
print("com.apple.universalaccess flashScreen = \(flash.map { "\($0)" } ?? "(missing or unreadable)")")

pause("1. NSBeep(): the reference. Expect a flash, alert volume, alert device.")
NSSound.beep()
Thread.sleep(forTimeInterval: 2)

pause("2. NSSound.play() on the file: what the PR does. Expect no flash, full volume, output device.")
guard let sound = NSSound(contentsOf: url, byReference: false) else {
    print("NSSound can’t load \(url.path)")
    exit(1)
}
sound.play()
Thread.sleep(forTimeInterval: max(2, sound.duration + 0.5))

var soundID: SystemSoundID = 0
let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
guard status == noErr else {
    print("AudioServicesCreateSystemSoundID failed: \(status)")
    exit(1)
}

pause("3. AudioServicesPlayAlertSound on the file: the candidate.")
waitForCompletion { AudioServicesPlayAlertSoundWithCompletion(soundID, $0) }

pause("4. AudioServicesPlaySystemSound on the file: same, without alert behavior.")
waitForCompletion { AudioServicesPlaySystemSoundWithCompletion(soundID, $0) }

pause("5. Step 3 twice, 0.2 seconds apart: do the two plays overlap, or does the second restart the first?")
AudioServicesPlayAlertSound(soundID)
Thread.sleep(forTimeInterval: 0.2)
waitForCompletion { AudioServicesPlayAlertSoundWithCompletion(soundID, $0) }

AudioServicesDisposeSystemSoundID(soundID)
print("\nDone.")
