//
//  AppDelegate.swift
//  SearchableComboViewDemo
//
//  Created by George Nachman on 1/25/20.
//  Copyright © 2020 George Nachman. All rights reserved.
//

import Cocoa
import SearchableComboListView

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var container: NSView!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let groups: [SearchableComboViewGroup] = [
            SearchableComboViewGroup(
                "Animals",
                items: [
                    SearchableComboViewItem("Aardvark", tag: 1),
                    SearchableComboViewItem("Beetle", tag: 2),
                    SearchableComboViewItem("Caterpillar", tag: 3),
                    SearchableComboViewItem("Dog", tag: 4),
                    SearchableComboViewItem("Elephant", tag: 5),
                    SearchableComboViewItem("Frog", tag: 6),
                    SearchableComboViewItem("Grasshopper", tag: 7),
                    SearchableComboViewItem("Hoot owl", tag: 8)]),
            SearchableComboViewGroup(
                "Vehicles",
                items: [
                    SearchableComboViewItem("Car", tag: 9),
                    SearchableComboViewItem("Truck", tag: 10),
                    SearchableComboViewItem("Bicycle", tag: 11),
                    SearchableComboViewItem("Airplane", tag: 12),
                    SearchableComboViewItem("Rocket ship", tag: 13),
                    SearchableComboViewItem("Lamborghini Aventador LP 750-4 Superveloce Roadster", tag: 100)]),
            SearchableComboViewGroup(
                "Colors",
                items: [
                    SearchableComboViewItem("Red", tag: 14),
                    SearchableComboViewItem("Orange", tag: 15),
                    SearchableComboViewItem("Yellow", tag: 16),
                    SearchableComboViewItem("Green", tag: 17),
                    SearchableComboViewItem("Blue", tag: 18),
                    SearchableComboViewItem("Indigo", tag: 19),
                    SearchableComboViewItem("Violet", tag: 20)]),
            SearchableComboViewGroup(
                "Foods",
                items: [
                    SearchableComboViewItem("Apple", tag: 21),
                    SearchableComboViewItem("Banana", tag: 22),
                    SearchableComboViewItem("Carrot", tag: 23),
                    SearchableComboViewItem("Dandelion salad", tag: 24),
                    SearchableComboViewItem("Eggplant", tag: 25),
                    SearchableComboViewItem("French toast", tag: 26),
                    SearchableComboViewItem("Garbanzo beans", tag: 27)]),
            SearchableComboViewGroup(
                "Tech Companies",
                items: [
                    SearchableComboViewItem("Facebook", tag: 28),
                    SearchableComboViewItem("Amazon", tag: 29),
                    SearchableComboViewItem("Apple", tag: 30),
                    SearchableComboViewItem("Netflix", tag: 31),
                    SearchableComboViewItem("Google", tag: 32)]),
            SearchableComboViewGroup(
                "Software",
                items: [
                    SearchableComboViewItem("Finder", tag: 33),
                    SearchableComboViewItem("Chrome", tag: 34),
                    SearchableComboViewItem("Calendar", tag: 35),
                    SearchableComboViewItem("Xcode", tag: 36),
                    SearchableComboViewItem("iTerm2", tag: 37),
                    SearchableComboViewItem("Spotify", tag: 38),
                    SearchableComboViewItem("Terminal", tag: 39),
                    SearchableComboViewItem("Pages", tag: 40),
                    SearchableComboViewItem("Preview", tag: 41),
                    SearchableComboViewItem("Activity Monitor", tag: 42),
                    SearchableComboViewItem("Safari", tag: 43)])
        ]
        let comboView = SearchableComboView(groups, defaultTitle: "Choose Thing…")
        comboView.frame = container.bounds
        comboView.title = "Choose a Thing…"
        container.addSubview(comboView)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

