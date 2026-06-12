//
//  ProfilesWebPreferencesViewController.swift
//  iTerm2
//
//  Created by George Nachman on 6/26/25.
//

@objc(ProfilesWebPreferencesViewController)
class ProfilesWebPreferencesViewController: iTermProfilePreferencesBaseViewController {
    @IBOutlet var browserPageZoom: NSSlider!
    @IBOutlet var devNullMode: NSButton!
    @IBOutlet var enableInstantReplay: NSButton!

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func awakeFromNib() {
        do {
            let _ = defineControl(browserPageZoom,
                                  key: KEY_BROWSER_ZOOM,
                                  displayName: "Browser page zoom",
                                  type: .slider)
        }
        do {
            let _ = defineControl(devNullMode,
                                  key: KEY_BROWSER_DEV_NULL,
                                  relatedView: nil,
                                  type: .checkbox)
        }
        do {
            _ = defineControl(enableInstantReplay,
                              key: KEY_INSTANT_REPLAY,
                              relatedView: nil,
                              type: .checkbox)
        }
    }
}
