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

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func awakeFromNib() {
        do {
            let _ = define(browserPageZoom,
                           key: KEY_BROWSER_ZOOM,
                           relatedView: nil,
                           type: .slider)
        }
        do {
            let _ = define(devNullMode,
                           key: KEY_BROWSER_DEV_NULL,
                           relatedView: nil,
                           type: .checkbox)
        }
    }
}
