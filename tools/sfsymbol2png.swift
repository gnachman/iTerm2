#!/usr/bin/env swift
import AppKit

func symbolToPNG(symbolName: String, outputPath: String, size: NSSize) {
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        print("Error: Symbol '\(symbolName)' not found.")
        return
    }

    let rect = NSRect(origin: .zero, size: size)

    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    rect.fill()

    symbol.draw(in: rect)
    image.unlockFocus()

    guard let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!) else {
        print("Error: Failed to create bitmap representation.")
        return
    }

    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Error: Failed to generate PNG data.")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Symbol '\(symbolName)' written to '\(outputPath)'.")
    } catch {
        print("Error: Failed to write PNG file: \(error.localizedDescription)")
    }
}

// Parse command line arguments
if CommandLine.argc != 3 {
    print("Usage: sfsymbol_to_png <symbolName> <outputPath>")
    print("outputPath should not include an extension. For exmaple, `sfsymbol_to_png bookmark OpenQuicklyBookmark`. Then you get OpenQuicklyBookmark.png and OpenQuicklyBookmark@2x.png")
    exit(1)
}

let symbolName = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
var size = NSSize(width: 100, height: 100)
symbolToPNG(symbolName: symbolName, outputPath: outputPath + "@2x.png", size: size)
size.width /= 2
size.height /= 2
symbolToPNG(symbolName: symbolName, outputPath: outputPath + ".png", size: size)
