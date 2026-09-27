//
//  KittyStalePlacementTests.swift
//  ModernTests
//
//  Regression tests for issue 13028: retransmitting a Kitty image under an id
//  that is already in use must replace the bitmap for every existing placement
//  of that id, so a placement (virtual or not, any placement id) draws the newest
//  image instead of the one captured when it was first displayed. Previously a
//  placement held a strong reference to the old Image, and retransmission never
//  updated it, so the stale bitmap was drawn forever, including for a placement
//  left behind by a program that had since exited.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class KittyStalePlacementTests: XCTestCase {
    // 64x64 solid squares encoded as PNG, from the issue report's encoder.
    private let redPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeUlEQVR4nO3PQQkAMAzAwAqrfxUTMxF7HINABFzm7H7dcEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFj108cEE8uoIF1wAAAABJRU5ErkJggg=="
    private let greenPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwBfMJEY0pSH8OITBAtxmnf11wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYBl0YBLT20X6MAAAAASUVORK5CYII="
    // A 32x32 green square (smaller than the 64x64 fixtures above), for retransmit-with-resize tests.
    private let green32PNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGOwWRVFU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFrfAExTPJMuAAAAAElFTkSuQmCC"

    // KittyImageController.delegate is weak, so the test must keep the delegate alive for the
    // duration of the test method; otherwise it deallocates and executeDisplay bails out before
    // creating any placement.
    private var delegates = [FakeKittyImageControllerDelegate]()

    private func makeController(imageCacheBudget: Int? = nil) -> KittyImageController {
        return makeControllerWithDelegate(imageCacheBudget: imageCacheBudget).0
    }

    private func makeControllerWithDelegate(imageCacheBudget: Int? = nil) -> (KittyImageController, FakeKittyImageControllerDelegate) {
        let delegate = FakeKittyImageControllerDelegate()
        delegates.append(delegate)
        let controller = imageCacheBudget.map { KittyImageController(imageCacheBudget: $0) } ?? KittyImageController()
        controller.delegate = delegate
        return (controller, delegate)
    }

    // a=T transmit and display. Set U=1 for a virtual placement (Unicode placeholder). A nil
    // placementId leaves p off so it defaults to 0.
    private func transmitAndDisplay(id: Int,
                                    pngBase64: String,
                                    virtual: Bool,
                                    placementId: Int? = nil) -> KittyImageCommand {
        var apc = "a=T,f=100,t=d,i=\(id)"
        if virtual {
            apc += ",U=1,c=4,r=2"
        }
        if let placementId {
            apc += ",p=\(placementId)"
        }
        apc += ",q=2;\(pngBase64)"
        return KittyImageCommand(apc)!
    }

    // The original repro: reuse the same id and the default placement id of 0. The green
    // transmission must supersede the red one and leave exactly one placement pointing at green.
    func testRetransmitSameIdAndPlacementIdSupersedes() {
        let controller = makeController()

        controller.execute(command: transmitAndDisplay(id: 7, pngBase64: redPNGBase64, virtual: true))
        let afterRed = controller.draws().filter { $0.virtual && $0.imageID == 7 }
        XCTAssertEqual(afterRed.count, 1)
        let redUniqueID = afterRed[0].imageUniqueID

        controller.execute(command: transmitAndDisplay(id: 7, pngBase64: greenPNGBase64, virtual: true))
        let afterGreen = controller.draws().filter { $0.virtual && $0.imageID == 7 }
        XCTAssertEqual(afterGreen.count, 1, "retransmitting id 7 must not leave a stale placement behind")
        XCTAssertNotEqual(afterGreen[0].imageUniqueID, redUniqueID,
                          "the surviving virtual placement should reference the newest (green) image")
    }

    // Reuse the id but with different placement ids. Both virtual placements survive (they are
    // distinct placements), but retransmission must re-point the older one at the new bitmap so no
    // placement of image 7 still draws red.
    func testRetransmitSameIdDifferentPlacementIdsRepointsOldPlacement() {
        let controller = makeController()

        controller.execute(command: transmitAndDisplay(id: 7, pngBase64: redPNGBase64, virtual: true, placementId: 1))
        let afterRed = controller.draws().filter { $0.virtual && $0.imageID == 7 }
        XCTAssertEqual(afterRed.count, 1)
        let redUniqueID = afterRed[0].imageUniqueID

        controller.execute(command: transmitAndDisplay(id: 7, pngBase64: greenPNGBase64, virtual: true, placementId: 2))
        let afterGreen = controller.draws().filter { $0.virtual && $0.imageID == 7 }
        XCTAssertEqual(afterGreen.count, 2, "distinct placement ids create distinct placements")
        XCTAssertFalse(afterGreen.contains { $0.imageUniqueID == redUniqueID },
                       "no surviving placement of image 7 should still reference the old (red) bitmap")
    }

    // Non-virtual placements are snapshots drawn at a fixed position and must NOT be retroactively
    // rewritten by a retransmit. A program that reuses one id for a sequence of pictures keeps each
    // earlier picture instead of collapsing its scrollback to the newest bitmap.
    func testRetransmitDoesNotRewriteNonVirtualPlacements() {
        let controller = makeController()

        controller.execute(command: transmitAndDisplay(id: 9, pngBase64: redPNGBase64, virtual: false))
        let afterRed = controller.draws().filter { $0.imageID == 9 }
        XCTAssertEqual(afterRed.count, 1)
        let redUniqueID = afterRed[0].imageUniqueID

        controller.execute(command: transmitAndDisplay(id: 9, pngBase64: greenPNGBase64, virtual: false))
        let afterGreen = controller.draws().filter { $0.imageID == 9 }
        XCTAssertTrue(afterGreen.contains { $0.imageUniqueID == redUniqueID },
                      "an earlier non-virtual placement must keep its original bitmap after a retransmit")
        XCTAssertTrue(afterGreen.contains { $0.imageUniqueID != redUniqueID },
                      "the new display should add a placement with the new bitmap")
    }

    // Placement ids are unique per image, not globally. A non-virtual placement of image 3 with
    // placement id 5 must not shadow a virtual placement of image 7 that also uses placement id 5.
    // A placeholder cell encoding imageID=7, placementID=5 must resolve to image 7.
    func testPlacementIdIsScopedPerImage() {
        let controller = makeController()

        controller.execute(command: transmitAndDisplay(id: 3, pngBase64: redPNGBase64, virtual: false, placementId: 5))
        controller.execute(command: transmitAndDisplay(id: 7, pngBase64: greenPNGBase64, virtual: true, placementId: 5))

        let draws = controller.draws()
        let found = iTermFindKittyImageDrawForVirtualPlaceholder(draws, 5, 7)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.imageID, 7,
                       "placement id 5 of image 3 must not shadow placement id 5 of image 7")
    }

    // Displaying a second image with a placement id already used by a different image must not
    // delete the first image's placement (the non-virtual display path).
    func testNonVirtualDisplayDoesNotDeleteOtherImagesPlacement() {
        let controller = makeController()

        controller.execute(command: transmitAndDisplay(id: 3, pngBase64: redPNGBase64, virtual: false, placementId: 5))
        controller.execute(command: transmitAndDisplay(id: 7, pngBase64: greenPNGBase64, virtual: false, placementId: 5))

        let draws = controller.draws()
        XCTAssertTrue(draws.contains { $0.imageID == 3 && $0.placementID == 5 },
                      "displaying image 7 with placement id 5 must not delete image 3's placement id 5")
        XCTAssertTrue(draws.contains { $0.imageID == 7 && $0.placementID == 5 })
    }

    // A relative placement whose parent pair equals its own pair forms a cycle: parents resolve
    // newest-wins, so once appended it would be its own parent (and pixelOrigin would recurse
    // forever). It must be rejected, not created.
    func testRelativePlacementToOwnPairIsRejectedAsCycle() {
        let controller = makeController()

        // Two p=0 placements of image 3.
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=3,q=2;\(redPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=3,q=2;\(redPNGBase64)")!)
        let before = controller.draws().filter { $0.imageID == 3 && $0.placementID == 0 }.count

        // A placement of image 3, p=0, relative to (3,0) — its own pair. Must be rejected as a cycle.
        controller.execute(command: KittyImageCommand("a=p,i=3,p=0,P=3,Q=0,q=2")!)
        let after = controller.draws().filter { $0.imageID == 3 && $0.placementID == 0 }.count

        XCTAssertEqual(after, before,
                       "a relative placement to its own (imageId, placementId) pair must be rejected as a cycle")
    }

    // A relative placement may legally reuse its parent's placement id under a different image.
    // Cycle detection keyed on placement id alone would reject it with ECYCLE; keying on the
    // (imageId, placementId) pair must allow it.
    func testRelativePlacementReusingParentPlacementIdIsCreated() {
        let controller = makeController()

        // Parent: image 3, placement id 5, at the cursor.
        controller.execute(command: transmitAndDisplay(id: 3, pngBase64: redPNGBase64, virtual: false, placementId: 5))
        // Transmit image 7, then display it as a placement with id 5 that is relative to the parent
        // (image 3, placement 5). Same placement id (5) but a different image, so it is not a cycle.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=7,q=2;\(greenPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=p,i=7,p=5,P=3,Q=5,q=2")!)

        let draws = controller.draws()
        XCTAssertTrue(draws.contains { $0.imageID == 7 && $0.placementID == 5 },
                      "a relative placement reusing its parent's placement id under a different image must be created")
    }

    // Deleting a parent placement must delete its relative children too, so a child cannot linger
    // orphaned and then resurrect when a new placement later reuses the parent's (imageId,
    // placementId) key.
    func testDeletingParentRemovesRelativeChildSoItCannotResurrect() {
        let controller = makeController()

        // Parent: image 3, placement id 5, at the cursor.
        controller.execute(command: transmitAndDisplay(id: 3, pngBase64: redPNGBase64, virtual: false, placementId: 5))
        // Child: image 7, placement id 6, relative to parent (image 3, placement 5).
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=7,q=2;\(greenPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=p,i=7,p=6,P=3,Q=5,q=2")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 7 && $0.placementID == 6 },
                      "the relative child should be visible while its parent exists")

        // Delete the parent placement (image 3, placement 5).
        controller.execute(command: KittyImageCommand("a=d,d=i,i=3,p=5,q=2")!)
        // Re-create a new, unrelated placement with the same key (image 3, placement 5).
        controller.execute(command: KittyImageCommand("a=p,i=3,p=5,q=2")!)

        XCTAssertFalse(controller.draws().contains { $0.imageID == 7 && $0.placementID == 6 },
                       "deleting the parent must remove the child; it must not resurrect onto a new parent")
    }

    // A truly id-less image (no i and no I) is stored under an internal key with metadata.identifier
    // == 0. Its placements must still be addressable by the delete paths, which work in terms of the
    // storage key, not metadata.identifier.
    func testDeleteRemovesIdlessImagePlacement() {
        let controller = makeController()

        // Transmit with neither an id nor an image number, then display the last image at placement 3.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,q=2;\(redPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=p,p=3,q=2")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 0 && $0.placementID == 3 },
                      "the id-less image's placement should be displayed")

        // Delete it (d=n resolves the last image by its number 0 and removes placement 3).
        controller.execute(command: KittyImageCommand("a=d,d=n,I=0,p=3,q=2")!)
        XCTAssertFalse(controller.draws().contains { $0.imageID == 0 && $0.placementID == 3 },
                       "deleting must remove the id-less image's placement")
    }

    // When an image is evicted from the cache its placements must be dropped, so a later
    // transmission that reuses the id cannot resurrect them with an unrelated bitmap.
    func testEvictedImageDropsPlacementsAndDoesNotResurrect() {
        // Budget holds one 64x64 image (16384 bytes) but not two, so each new image evicts the prior.
        let controller = makeController(imageCacheBudget: 20000)

        // Program A: transmit and display image id 5.
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=5,p=1,q=2;\(redPNGBase64)")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 5 && $0.placementID == 1 })

        // Transmit a different image (id 6); this evicts id 5 and must drop A's placement.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=6,q=2;\(greenPNGBase64)")!)
        XCTAssertFalse(controller.draws().contains { $0.imageID == 5 },
                       "an evicted image's placements must be dropped")

        // Program B reuses id 5. The dropped placement must not resurrect at A's old position.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=5,q=2;\(greenPNGBase64)")!)
        XCTAssertFalse(controller.draws().contains { $0.imageID == 5 && $0.placementID == 1 },
                       "reusing an evicted id must not resurrect the old placement")
    }

    // Evicting an image must not delete a relative child of a different, still-resident image.
    // Eviction is internal memory pressure, not a user delete, so its removal must not cascade.
    func testEvictionDoesNotDeleteRelativeChildOfResidentImage() {
        let controller = makeController(imageCacheBudget: 40000)  // holds two 64x64 images, not three

        // Parent: image 3, placement 5. Child: image 7, placement 6, relative to (3,5).
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=3,p=5,q=2;\(redPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=7,p=6,P=3,Q=5,q=2;\(greenPNGBase64)")!)
        XCTAssertTrue(controller.hasPlacement(imageID: 7, placementID: 6))

        // Transmit a third image; this evicts image 3 (the oldest), removing its placement.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=8,q=2;\(greenPNGBase64)")!)
        XCTAssertFalse(controller.hasPlacement(imageID: 3, placementID: 5),
                       "the evicted image's own placement should be removed")
        // Image 7 is still resident, so its placement must not be cascade-deleted by the eviction.
        XCTAssertTrue(controller.hasPlacement(imageID: 7, placementID: 6),
                      "evicting image 3 must not delete a relative child of the still-resident image 7")
    }

    // Id-less images (no i, no I) share one internal slot, but each transmission is a distinct image.
    // Evicting a later id-less image must not remove the still-drawable placement of an earlier one.
    func testEvictingIdlessImageKeepsOtherIdlessPlacements() {
        let controller = makeController(imageCacheBudget: 40000)

        // Display id-less image A at placement 1.
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,p=1,q=2;\(redPNGBase64)")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 0 && $0.placementID == 1 })

        // Transmit a second id-less image B (replaces the last-image slot; A's bitmap stays alive).
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,q=2;\(greenPNGBase64)")!)
        // Fill the cache so the last-image slot (now B) is evicted.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=9,q=2;\(greenPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=10,q=2;\(greenPNGBase64)")!)

        XCTAssertTrue(controller.draws().contains { $0.imageID == 0 && $0.placementID == 1 },
                      "evicting a later id-less image must not remove an earlier id-less image's live placement")
    }

    // d=i,i=0 addresses id-less images. It must remove their placements (regression guard).
    func testDeleteByImageIdZeroRemovesIdlessPlacement() {
        let controller = makeController()

        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,p=1,q=2;\(redPNGBase64)")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 0 && $0.placementID == 1 })

        controller.execute(command: KittyImageCommand("a=d,d=i,i=0,q=2")!)
        XCTAssertFalse(controller.draws().contains { $0.imageID == 0 && $0.placementID == 1 },
                       "d=i,i=0 must remove id-less image placements")
    }

    // d=i,i=0 targets only the current id-less image (the one in the shared slot), not every id-less
    // image ever displayed. Mirrors the eviction guard.
    func testDeleteByImageIdZeroKeepsOtherIdlessPlacements() {
        let controller = makeController()

        // Display id-less image A at placement 1, then transmit a second id-less image B (which now
        // occupies the last-image slot; A's placement stays alive).
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,p=1,q=2;\(redPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,q=2;\(greenPNGBase64)")!)

        // d=i,i=0 addresses the current id-less image (B), which has no placement, so A must survive.
        controller.execute(command: KittyImageCommand("a=d,d=i,i=0,q=2")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 0 && $0.placementID == 1 },
                      "d=i,i=0 must not delete an earlier id-less image's placement")
    }

    // A single transmission that both evicts a placement and re-points another must post exactly one
    // placements-changed notification, not one per step.
    func testTransmitCoalescesEvictionAndRepointIntoOneNotification() {
        let (controller, delegate) = makeControllerWithDelegate(imageCacheBudget: 20000)

        // Two small (32x32) images with placements.
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=5,p=1,q=2;\(green32PNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=6,p=2,q=2;\(green32PNGBase64)")!)
        let base = delegate.placementsDidChangeCount

        // Retransmit id 5 as a larger 64x64 bitmap. Re-inserting id 5 pushes the cache over budget and
        // evicts id 6 (dropping its placement), and it also re-points id 5's placement. One transmit,
        // one notification.
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=5,q=2;\(redPNGBase64)")!)
        XCTAssertEqual(delegate.placementsDidChangeCount - base, 1,
                       "eviction and re-point within one transmit must coalesce to a single notification")
    }

    // (imageId, placementId) is not unique: two non-virtual placements of one image with the default
    // placement id 0 coexist. Deleting one must not cascade-delete a relative child that is actually
    // positioned relative to the other, still-present placement.
    func testDeletingOneOfTwoAmbiguousParentsKeepsChild() {
        let controller = makeController()

        // Two non-virtual p=0 placements of image 3, distinguished only by z-index. The child
        // resolves to the most recently created parent (z=2).
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=3,z=1,q=2;\(redPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=3,z=2,q=2;\(redPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=t,f=100,t=d,i=7,q=2;\(greenPNGBase64)")!)
        controller.execute(command: KittyImageCommand("a=p,i=7,p=9,P=3,Q=0,q=2")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 7 && $0.placementID == 9 },
                      "the relative child should exist")

        // Delete only the older parent (z=1). The child is positioned relative to the newer one, so
        // it must survive.
        controller.execute(command: KittyImageCommand("a=d,d=z,z=1,q=2")!)
        XCTAssertTrue(controller.draws().contains { $0.imageID == 7 && $0.placementID == 9 },
                      "deleting one of two ambiguous parents must not delete a child bound to the other")
    }

    // A Unicode placeholder must resolve only to virtual placements. A non-virtual placement of the
    // same image sized with c/r has a nonzero placement size and would otherwise be picked up by the
    // image-id fallback for the common default placement id of 0.
    func testPlaceholderFinderIgnoresNonVirtualPlacement() {
        let controller = makeController()

        // A non-virtual placement of image 7, sized with c/r (nonzero placement size), placement 0.
        controller.execute(command: KittyImageCommand("a=T,f=100,t=d,i=7,c=4,r=2,q=2;\(redPNGBase64)")!)

        // No virtual placement of image 7 exists, so a placeholder for image 7 must resolve to
        // nothing rather than the non-virtual placement.
        XCTAssertNil(iTermFindKittyImageDrawForVirtualPlaceholder(controller.draws(), 0, 7),
                     "a Unicode placeholder must not resolve to a non-virtual placement")
    }
}

private final class FakeKittyImageControllerDelegate: NSObject, KittyImageControllerDelegate {
    var placementsDidChangeCount = 0
    func kittyImageControllerReport(message: String) {}
    func kittyImageControllerPlacementsDidChange() {
        placementsDidChangeCount += 1
    }
    func kittyImageControllerCursorCoord() -> VT100GridAbsCoord {
        return VT100GridAbsCoord(x: 0, y: 0)
    }
    func kittyImageControllerMoveCursor(dx: Int, dy: Int) {}
    func kittyImageControllerCellSize() -> NSSize {
        return NSSize(width: 10, height: 20)
    }
    func kittyImageControllerScreenAbsLine() -> Int64 {
        return 0
    }
}
