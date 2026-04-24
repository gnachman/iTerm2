//
//  WorkgroupAnimalNames.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import Foundation

// Default-name pool for new workgroup sessions. Short animal names keep
// the mode-switcher + tab-bar wireframe readable at small widths. Names
// are picked in list order (deterministic) and deduped against whatever
// the workgroup already uses, so two new sessions never share one by
// default.
enum WorkgroupAnimalNames {
    static let all: [String] = [
        "Fox", "Hen", "Owl", "Cat", "Dog", "Pig", "Cow", "Bat", "Bee",
        "Elk", "Doe", "Jay", "Ram", "Ewe", "Rat", "Ant", "Yak", "Emu",
        "Ape", "Asp", "Frog", "Hare", "Wolf", "Bear", "Deer", "Goat",
        "Lion", "Mole", "Seal", "Swan", "Crab", "Tuna", "Lamb", "Kiwi",
        "Duck", "Fawn", "Lynx", "Puma", "Moth", "Wren", "Mink", "Toad",
        "Mule", "Boar", "Crow", "Dove", "Otter", "Skunk", "Koala",
        "Llama", "Camel", "Eagle", "Goose", "Hyena", "Sloth", "Gecko",
        "Panda", "Snake", "Tiger", "Whale", "Zebra", "Mouse", "Horse",
    ]

    // Returns the first animal not in `taken`. If every base name is
    // taken, tries "Fox 2", "Hen 2", …, then "Fox 3", … until it finds
    // a free one.
    static func pick(taken: Set<String>) -> String {
        for name in all where !taken.contains(name) { return name }
        var suffix = 2
        while true {
            for name in all {
                let candidate = "\(name) \(suffix)"
                if !taken.contains(candidate) { return candidate }
            }
            suffix += 1
        }
    }
}
