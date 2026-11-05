//
//  BackupUpdateCheckerTests.swift
//  iTerm2
//
//  Created by George Nachman on 11/5/26.
//

import XCTest
@testable import iTerm2SharedARC

final class BackupUpdateCheckerTests: XCTestCase {
    private let appcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>Version 3.6.11</title>
          <sparkle:minimumSystemVersion>12.4</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/a.zip" sparkle:version="3.6.11" length="1" type="application/octet-stream" sparkle:edSignature="x" />
        </item>
        <item>
          <title>Version 3.7.7</title>
          <sparkle:minimumSystemVersion>13</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/b.zip"
                     sparkle:version="3.7.7"
                     length="2"
                     type="application/octet-stream"
                     sparkle:edSignature="y" />
        </item>
        <item>
          <title>Version 3.8.0</title>
          <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/c.zip" sparkle:version="3.8.0" length="3" type="application/octet-stream" sparkle:edSignature="z" />
        </item>
      </channel>
    </rss>
    """

    func testPicksNewestVersionThisMacCanRun() {
        let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 1)
        XCTAssertEqual(BackupUpdateChecker.newestVersion(inAppcast: appcast, runningOn: os), "3.7.7")
    }

    func testHonorsMinimumSystemVersion() {
        let os = OperatingSystemVersion(majorVersion: 12, minorVersion: 6, patchVersion: 0)
        XCTAssertEqual(BackupUpdateChecker.newestVersion(inAppcast: appcast, runningOn: os), "3.6.11")
    }

    func testEmptyAppcast() {
        let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        XCTAssertNil(BackupUpdateChecker.newestVersion(inAppcast: "<rss><channel></channel></rss>", runningOn: os))
        XCTAssertNil(BackupUpdateChecker.newestVersion(inAppcast: "not xml at all", runningOn: os))
    }

    func testFeedURL() {
        XCTAssertEqual(BackupUpdateChecker.feedURL(wantsBetas: false).absoluteString,
                       "https://iterm2.com/appcasts/backup_update.xml?betas=0")
        XCTAssertEqual(BackupUpdateChecker.feedURL(wantsBetas: true).absoluteString,
                       "https://iterm2.com/appcasts/backup_update.xml?betas=1")
    }

    func testVersionComparison() {
        XCTAssertTrue(BackupUpdateChecker.version("3.7.8", isNewerThan: "3.7.7"))
        XCTAssertTrue(BackupUpdateChecker.version("3.7.10", isNewerThan: "3.7.9"))
        XCTAssertFalse(BackupUpdateChecker.version("3.7.7", isNewerThan: "3.7.7"))
        XCTAssertFalse(BackupUpdateChecker.version("3.6.11", isNewerThan: "3.7.7"))
        XCTAssertTrue(BackupUpdateChecker.version("3.7.8", isNewerThan: "3.7.8beta1"))
        XCTAssertFalse(BackupUpdateChecker.version("3.7.8beta1", isNewerThan: "3.7.8"))
        XCTAssertTrue(BackupUpdateChecker.version("3.7.8beta2", isNewerThan: "3.7.8beta1"))
        XCTAssertTrue(BackupUpdateChecker.version("3.8.0beta10", isNewerThan: "3.8.0beta9"))
        XCTAssertFalse(BackupUpdateChecker.version("3.8.0beta9", isNewerThan: "3.8.0beta10"))
        XCTAssertFalse(BackupUpdateChecker.version("3.8.0beta10", isNewerThan: "3.8.0beta10"))
        XCTAssertTrue(BackupUpdateChecker.version("3.7.8beta1", isNewerThan: "3.7.7"))
        XCTAssertTrue(BackupUpdateChecker.version("3.7.20261105-nightly", isNewerThan: "3.7.8"))
        XCTAssertTrue(BackupUpdateChecker.version("3.7.20261105-nightly", isNewerThan: "3.7.20261104-nightly"))
        XCTAssertTrue(BackupUpdateChecker.version("3.8.0", isNewerThan: "3.7.20261105-nightly"))
        XCTAssertTrue(BackupUpdateChecker.version("4.0", isNewerThan: "3.9.9"))
        XCTAssertFalse(BackupUpdateChecker.version("3.7", isNewerThan: "3.7.0"))
    }
}
