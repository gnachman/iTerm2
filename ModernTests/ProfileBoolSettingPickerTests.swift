//
//  ProfileBoolSettingPickerTests.swift
//  ModernTests
//
//  Tests for the "Set Profile Setting" trigger picker's param round-trip, specifically that it
//  preserves a configured parameter whose key is not currently selectable (F4) instead of
//  silently discarding it when the On/Off control is touched.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class ProfileBoolSettingPickerTests: XCTestCase {
    private func encode(_ key: String, _ on: Bool) -> String {
        return TwoParameterTriggerCodec.convert(tuple: (key, on ? "1" : "0"))
    }

    // F4: when no eligible setting is selected (selectedKey == nil), the getter must return the
    // stored param unchanged rather than "" -- otherwise touching On/Off drops the key half and
    // wipes the configured setting.
    func testPreservesStoredParamWhenNoKeySelectedOn() {
        let stored = encode("Prevent Sleep", true)
        XCTAssertEqual(
            ProfileBoolSettingPickerView.param(forSelectedKey: nil, valueIsOn: true, storedParam: stored),
            stored)
    }

    func testPreservesStoredParamWhenNoKeySelectedOff() {
        let stored = encode("Prevent Sleep", false)
        // Even if the On/Off control reads "On", with no selected key we must not synthesize a
        // param from it; we return the stored value verbatim.
        XCTAssertEqual(
            ProfileBoolSettingPickerView.param(forSelectedKey: nil, valueIsOn: true, storedParam: stored),
            stored)
    }

    func testComputesParamFromSelectionWhenKeySelected() {
        XCTAssertEqual(
            ProfileBoolSettingPickerView.param(forSelectedKey: "Prevent Sleep", valueIsOn: true, storedParam: "old"),
            encode("Prevent Sleep", true))
        XCTAssertEqual(
            ProfileBoolSettingPickerView.param(forSelectedKey: "Prevent Sleep", valueIsOn: false, storedParam: "old"),
            encode("Prevent Sleep", false))
    }

    func testEmptyStoredParamWithNoSelectionStaysEmpty() {
        XCTAssertEqual(
            ProfileBoolSettingPickerView.param(forSelectedKey: nil, valueIsOn: true, storedParam: ""),
            "")
    }

    // F23: setting param records the key in a stable ivar (not the transient combo selectedItem),
    // so flipping the On/Off popup WITHOUT reopening the dropdown updates the value and keeps the
    // key. Before the fix, selectedKey was nil once the panel closed, so the getter returned the
    // stale storedParam and the On/Off change was silently dropped.
    func testOnOffChangeWithClosedDropdownKeepsKeyAndUpdatesValue() {
        let picker = ProfileBoolSettingPickerView(frame: .zero)
        picker.param = encode("Prevent Sleep", true)      // On
        XCTAssertEqual(picker.param, encode("Prevent Sleep", true))
        picker.onOffButton.selectItem(at: 1)              // flip to Off, dropdown never opened
        XCTAssertEqual(picker.param, encode("Prevent Sleep", false),
                       "On/Off change must be reflected and the key preserved")
    }

    // F11: the On/Off decode must mirror the trigger (On iff raw == "1"); any non-"1" value is Off.
    func testOnOffIndexMirrorsTrigger() {
        XCTAssertEqual(ProfileBoolSettingPickerView.onOffIndex(forRawValue: "1"), 0)   // On
        XCTAssertEqual(ProfileBoolSettingPickerView.onOffIndex(forRawValue: "0"), 1)   // Off
        // Non-canonical values execute as Off in the trigger, so the UI must show Off, not On.
        XCTAssertEqual(ProfileBoolSettingPickerView.onOffIndex(forRawValue: "yes"), 1)
        XCTAssertEqual(ProfileBoolSettingPickerView.onOffIndex(forRawValue: ""), 1)
    }
    // F-400: the On/Off popup was a fixed 70pt, which clipped pt-BR “Inativo”. It must be wide
    // enough for its longest item, whichever one is selected.
    func testOnOffPopupFitsItsLongestItem() throws {
        for selectedIndex in [0, 1] {
            let picker = ProfileBoolSettingPickerView(frame: .zero)
            picker.onOffButton.item(at: 1)?.title = "Inativo Inativo"
            picker.onOffButton.selectItem(at: selectedIndex)
            picker.frame = NSRect(x: 0, y: 0, width: 400, height: 22)
            picker.layoutSubtreeIfNeeded()

            let cell = try XCTUnwrap(picker.onOffButton.cell)
            XCTAssertGreaterThanOrEqual(picker.onOffButton.frame.width, ceil(cell.cellSize.width),
                                        "selected index \(selectedIndex)")
            picker.onOffButton.selectItem(at: 1)
            XCTAssertGreaterThanOrEqual(picker.onOffButton.frame.width, ceil(cell.cellSize.width),
                                        "Off selected after layout, from index \(selectedIndex)")
            XCTAssertLessThanOrEqual(picker.onOffButton.frame.maxX, picker.bounds.width)
        }
    }

    func testOnOffPopupKeepsItsWidthForShortTitles() {
        let picker = ProfileBoolSettingPickerView(frame: NSRect(x: 0, y: 0, width: 400, height: 22))
        picker.layoutSubtreeIfNeeded()
        XCTAssertEqual(picker.onOffButton.frame.width, 70)
    }
}
