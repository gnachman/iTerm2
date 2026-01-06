//
//  PseudoTerminal.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

@objc
extension PseudoTerminal {
    // Set the session's profile dictionary and initialize its screen and name. Sets the
    // window title to the session's name. If size is not nil then the session is initialized to fit
    // a view of that size; otherwise the size is derived from the existing window if there is already
    // an open tab, or its bookmark's preference if it's the first session in the window.
    @objc(setupSessionImpl:screenSize:withSize:)
    func setup(session: PTYSession,
               screenSize: NSSize,
               size: UnsafePointer<NSSize>?) {
        let sessionSize = windowSizeHelper.sessionSize(
            profile: session.profile,
            existingViewSize: currentSession()?.view?.scrollview?.documentVisibleRect.size,
            desiredPointSize: size?.pointee,
            hasScrollbar: scrollbarShouldBeVisible(),
            scrollerStyle: scrollerStyle(),
            rightExtra: currentSession()?.desiredRightExtra() ?? 0.0,
            screenSize: screenSize)
        windowSizeHelper.updateDesiredSize(sessionSize.desiredSize)
        if session.setScreenSize(sessionSize.pointSize,
                                 parent: self) {
            DLog("setupSession - call safelySetSessionSize")
            safelySetSessionSize(session,
                                 rows: sessionSize.gridSize.height,
                                 columns: sessionSize.gridSize.width)

            DLog("setupSession - call setPreferencesFromAddressBookEntry")
            session.setPreferencesFromAddressBookEntry(session.profile)
            session.loadInitialColorTableAndResetCursorGuide()
            session.screen.resetTimestamps()
        }
    }
}
