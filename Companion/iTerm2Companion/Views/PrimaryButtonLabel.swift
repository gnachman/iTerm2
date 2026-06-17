//
//  PrimaryButtonLabel.swift
//  iTerm2 Companion
//
//  A full-width primary call-to-action label. We build the prominent look
//  ourselves rather than using .borderedProminent, because a borderedProminent
//  button whose label is sized with maxWidth: .infinity renders a ghost copy of
//  the label at the top of the screen. Pair it with .buttonStyle(.plain).
//

import SwiftUI

struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
    }
}
