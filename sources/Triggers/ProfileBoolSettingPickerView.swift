//
//  ProfileBoolSettingPickerView.swift
//  iTerm2SharedARC
//
//  The parameter editor for the "Set Profile Setting" trigger action. A searchable, path-grouped
//  picker (SearchableComboView) selects which profile boolean to set, and a small On/Off popup
//  selects the value. The whole thing round-trips a single encoded string param of the form
//  <profile key>\u{1}<0|1> via the `param` property, and calls `onChange` when either control
//  changes so TriggerController can write it back.
//

import AppKit
import SearchableComboListView

@objc(iTermProfileBoolSettingPickerView)
class ProfileBoolSettingPickerView: NSView, SearchableComboViewDelegate {
    // Called when either control changes. TriggerController reads `param` back in the handler.
    @objc var onChange: (() -> Void)?

    private let comboView: SearchableComboView
    // Internal (not private) so tests can drive the On/Off value without the dropdown.
    let onOffButton = NSPopUpButton(frame: .zero, pullsDown: false)

    // The currently-selected setting key. Tracked explicitly rather than read from
    // comboView.selectedItem, which is derived from the table's selectedRow and is transient: it is
    // cleared when the dropdown panel closes (and is never set at all for a picker that was never
    // opened). Updated by the delegate callback and the param setter.
    private var selectedKeyStorage: String?

    @objc override init(frame frameRect: NSRect) {
        comboView = SearchableComboView(Self.groups(), defaultTitle: "Select Setting…")
        super.init(frame: frameRect)

        comboView.delegate = self
        addSubview(comboView)

        onOffButton.addItem(withTitle: "On")
        onOffButton.addItem(withTitle: "Off")
        onOffButton.target = self
        onOffButton.action = #selector(onOffChanged(_:))
        addSubview(onOffButton)

        layoutControls()
    }

    required init?(coder: NSCoder) {
        it_fatalError("not supported")
    }

    // MARK: - Layout (frame-based; no autolayout)

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutControls()
    }

    override func layout() {
        super.layout()
        layoutControls()
    }

    private func layoutControls() {
        let onOffWidth: CGFloat = 70
        let gap: CGFloat = 6
        let comboWidth = max(0, bounds.width - onOffWidth - gap)
        comboView.frame = NSRect(x: 0, y: 0, width: comboWidth, height: bounds.height)
        onOffButton.frame = NSRect(x: comboWidth + gap, y: 0, width: onOffWidth, height: bounds.height)
    }

    // MARK: - Param round-trip

    // The last param set on us. Returned unchanged by the getter when no eligible setting is
    // currently selected (e.g. the stored key is not in the eligible list because it was excluded
    // or became hiddenFromActions/feature-gated in this build). Without this, touching the On/Off
    // control while the combo shows "Select Setting…" would return "" and silently discard the
    // previously-configured setting.
    private var storedParam: String = ""

    // Testable: the param to report given the current selection state. Preserves storedParam when
    // no eligible setting is selected, so touching On/Off never discards a configured-but-ineligible
    // key.
    static func param(forSelectedKey selectedKey: String?, valueIsOn: Bool, storedParam: String) -> String {
        guard let key = selectedKey else { return storedParam }
        return TwoParameterTriggerCodec.convert(tuple: (key, valueIsOn ? "1" : "0"))
    }

    // Testable: the On/Off popup index (0 = On, 1 = Off) for a stored raw value. Mirrors
    // SetProfileBooleanTrigger.keyAndValue, which executes On iff raw == "1"; any other value
    // (corrupt/hand-edited) is Off, so the UI must not display it as On.
    static func onOffIndex(forRawValue raw: String) -> Int {
        return raw == "1" ? 0 : 1
    }

    @objc var param: String {
        get {
            return Self.param(forSelectedKey: selectedKey,
                              valueIsOn: onOffButton.indexOfSelectedItem == 0,
                              storedParam: storedParam)
        }
        set {
            storedParam = newValue
            let (key, raw) = TwoParameterTriggerCodec.convert(string: newValue)
            // Track the key only if it is actually an eligible item; otherwise leave it nil so the
            // getter preserves storedParam verbatim (an ineligible/hand-edited key).
            let selected = comboView.selectItem(withIdentifier: NSUserInterfaceItemIdentifier(key))
            selectedKeyStorage = selected ? key : nil
            onOffButton.selectItem(at: Self.onOffIndex(forRawValue: raw))
        }
    }

    private var selectedKey: String? {
        return selectedKeyStorage
    }

    @objc private func onOffChanged(_ sender: Any?) {
        onChange?()
    }

    // MARK: - SearchableComboViewDelegate

    func searchableComboView(_ view: SearchableComboView, didSelectItem item: SearchableComboViewItem?) {
        selectedKeyStorage = item?.identifier
        onChange?()
    }

    // MARK: - Groups

    // Build the path-grouped list of eligible profile-boolean settings from the shared catalog
    // (ProfileBoolSettingCatalog), so this picker and SetProfileBooleanTrigger's row description
    // cannot drift. Each item's identifier is the profile key, used for selection round-trip.
    private static func groups() -> [SearchableComboViewGroup] {
        var itemsByPath: [String: [SearchableComboViewItem]] = [:]
        for (index, entry) in ProfileBoolSettingCatalog.entries().enumerated() {
            let path = entry.pathComponents.joined(separator: " > ")
            itemsByPath[path, default: []].append(
                SearchableComboViewItem(entry.label, tag: index, identifier: entry.key))
        }
        return itemsByPath.keys.sorted().map { path in
            let items = (itemsByPath[path] ?? []).sorted {
                $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            return SearchableComboViewGroup(path, items: items)
        }
    }
}
