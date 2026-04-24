//
//  ButtonPillInfo.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/31/26.
//

import AppKit

/// Represents a group of buttons that should be rendered inside a pill-shaped container.
@objc(iTermButtonPillInfo)
class ButtonPillInfo: NSObject {
    /// The bounding rect for the pill container (in points).
    /// Note: The Y coordinate is relative to row 0 without margins. The renderer
    /// should recalculate Y based on `line` and current margins.
    @objc let rect: NSRect

    /// X positions (in points, relative to rect.minX) where vertical dividers should be drawn.
    @objc let dividerXPositions: [NSNumber]

    /// The buttons in this group.
    @objc let buttons: [TerminalButton]

    /// The absolute Y line number of the buttons in this pill.
    @objc let absLine: Int64

    /// Returns the index of the pressed button, or -1 if none are pressed.
    @objc var pressedButtonIndex: Int {
        for (index, button) in buttons.enumerated() {
            if button.state == .pressedInside {
                return index
            }
        }
        return -1
    }

    @objc init(rect: NSRect, dividerXPositions: [NSNumber], buttons: [TerminalButton], absLine: Int64) {
        self.rect = rect
        self.dividerXPositions = dividerXPositions
        self.buttons = buttons
        self.absLine = absLine
        super.init()
    }

    /// Create pill info from a dictionary of buttons grouped by y-coordinate.
    /// - Parameters:
    ///   - buttonsByLine: Buttons grouped by their absY coordinate
    ///   - horizontalPadding: Extra padding on left/right of the pill
    ///   - verticalPadding: Extra padding on top/bottom of the pill
    /// - Returns: Array of ButtonPillInfo for each group
    @objc static func createPillInfos(from buttons: [TerminalButton],
                                       absCoordProvider: (TerminalButton) -> VT100GridAbsCoord,
                                       horizontalPadding: CGFloat,
                                       verticalPadding: CGFloat) -> [ButtonPillInfo] {
        // Group buttons by their y-coordinate
        var buttonsByLine: [Int64: [TerminalButton]] = [:]
        for button in buttons {
            guard button.wantsFrame else { continue }
            let absCoord = absCoordProvider(button)
            let key = absCoord.y
            if buttonsByLine[key] == nil {
                buttonsByLine[key] = []
            }
            buttonsByLine[key]!.append(button)
        }

        // Create pill info for each group
        var result: [ButtonPillInfo] = []
        for (absLine, groupButtons) in buttonsByLine {
            guard !groupButtons.isEmpty else { continue }

            // Sort buttons by x position
            let sortedButtons = groupButtons.sorted { $0.desiredFrame.minX < $1.desiredFrame.minX }

            // Calculate the union rect for all buttons
            var unionRect = sortedButtons[0].desiredFrame
            for button in sortedButtons.dropFirst() {
                unionRect = unionRect.union(button.desiredFrame)
            }

            // Apply padding - asymmetric vertical: the top edge moves down by verticalPadding
            // to align with line-style marks. In flipped coordinates: origin.y is top.
            let paddedRect = NSRect(
                x: unionRect.origin.x - horizontalPadding,
                y: unionRect.origin.y + verticalPadding,
                width: unionRect.width + 2 * horizontalPadding,
                height: unionRect.height
            )

            // Calculate divider positions (between adjacent buttons)
            var dividers: [NSNumber] = []
            for i in 0..<(sortedButtons.count - 1) {
                let button1 = sortedButtons[i]
                let button2 = sortedButtons[i + 1]
                // Divider at the midpoint between buttons, relative to paddedRect.minX
                let dividerX = round(((button1.desiredFrame.maxX + button2.desiredFrame.minX) / 2.0 - paddedRect.minX) * 2.0) / 2.0
                dividers.append(NSNumber(value: Double(dividerX)))
            }

            // Set drawsBackground = false for buttons in the group (they're inside the pill now)
            for button in sortedButtons {
                button.drawsBackground = false
            }

            result.append(ButtonPillInfo(rect: paddedRect,
                                         dividerXPositions: dividers,
                                         buttons: sortedButtons,
                                         absLine: absLine))
        }

        return result
    }
}
