//
//  TailFindController.swift
//  iTerm2
//
//  Created by George Nachman on 1/11/25.
//

@objc(iTermTailFindControllerDelegate)
protocol TailFindControllerDelegate: AnyObject {
    func tailFindControllerBelongsToVisibleTab() -> Bool
    func tailFindControllerFindOnPageHelper() -> iTermFindOnPageHelper
    func tailFindControllerRemoveSearchResults(inRange: VT100GridAbsCoordRange)
    func tailFindControllerAdd(searchResult: SearchResult)
    func tailFindControllerDoesNeedDisplay()
    func tailFindControllerDidFinish(atLocation: LineBufferPosition?)
    func tailFindControllerMainSearchEngine() -> iTermSearchEngine
    func tailFindControllerPositionForTailSearchOfMainSearchEngine() -> LineBufferPosition
}

@objc(iTermTailFindController)
class TailFindController: NSObject {
    private var timer: Timer?
    @objc weak var delegate: TailFindControllerDelegate?
    private var searchEngine: iTermSearchEngine
    // A one-shot tail find runs even though the find view is invisible. Once it's done searching,
    // it doesn't restart itself until the user does cmd-g again. See issue 9964.
    private var performingOneShotTailFind = false

    @objc(initWithDataSource:syncDistributor:)
    init(dataSource: iTermSearchEngineDataSource,
         syncDistributor: SyncDistributor) {
        searchEngine = iTermSearchEngine(dataSource: dataSource, syncDistributor: syncDistributor)
    }

    deinit {
        timer?.invalidate()
    }

    @objc
    func startTailFindIfVisible() {
        guard timer == nil else {
            return
        }
        guard let delegate, delegate.tailFindControllerBelongsToVisibleTab() else {
            return
        }
        beginContinuousTailFind()
    }

    @objc
    func beginOneShotTailFind() {
        DLog("beginOneShotTailFind");
        guard timer == nil, !performingOneShotTailFind else {
            return
        }
        performingOneShotTailFind = false
        if !beginTailFindImpl() {
            performingOneShotTailFind = false
        }
    }

    @objc
    func contentDidChange() {
        guard timer == nil else { return }

        DLog("Session contents changed. Begin tail find.");
        DispatchQueue.main.async { [weak self] in
            self?.startTailFindIfVisible()
        }
    }

    @objc
    func stopTailFind() {
        DLog("stop tail find");
        searchEngine.cancel()
        timer?.invalidate()
        timer = nil
    }

    @objc
    func stopContinuousTailFind() {
        guard timer != nil && !performingOneShotTailFind else {
            return
        }
        stopTailFind()
    }

    @objc
    func reset() {
        DLog("Reset tail find")
        timer?.invalidate()
        timer = nil
        searchEngine.updateSnapshot()
        startTailFindIfVisible()
    }
}

extension TailFindController {
    // Look for the next chunk of results.
    private func continueTailFind() {
        guard let delegate else { return }
        DLog("Continue tail find")
        let results = NSMutableArray()
        var rangeSearched = VT100GridAbsCoordRangeMake(-1, -1, -1, -1)
        var ignore: NSRange = NSRange(location: 0, length: 0)

        let more = searchEngine.continueFindAllResults(results,
                                                       rangeOut: &ignore,
                                                       absLineRange: delegate.tailFindControllerFindOnPageHelper().absLineRange,
                                                       rangeSearched: &rangeSearched)
        DLog("Continue tail find found \(results.count) results, last is \(String(describing: results.lastObject)), more=\(more)")
        if VT100GridAbsCoordRangeIsValid(rangeSearched) {
            delegate.tailFindControllerRemoveSearchResults(inRange: rangeSearched)
        }
        for r in results {
            delegate.tailFindControllerAdd(searchResult: r as! SearchResult)
        }
        if results.count > 0 {
            delegate.tailFindControllerDoesNeedDisplay()
        }
        if more {
            DLog("Reschedule timer")
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
                    self?.continueTailFind()
                }
            }
        } else {
            DLog("Tail find is done")
            // Update the saved position to just before the screen
            delegate.tailFindControllerDidFinish(atLocation: searchEngine.lastLocationSearched)
            timer?.invalidate()
            timer = nil
            performingOneShotTailFind = false
        }
    }

    private func beginContinuousTailFind() {
        DLog("beginContinuousTailFind");
        performingOneShotTailFind = false
        _ = beginTailFindImpl()
    }

    private func beginTailFindImpl() -> Bool {
        DLog("beginTailFindImpl");
        guard let delegate else {
            return false
        }
        let mainSearchEngine = delegate.tailFindControllerMainSearchEngine()
        guard mainSearchEngine.hasRequest else {
            return false
        }
        DLog("Begin tail find")
        // Set the starting position to the block & offset that the backward search
        // began at. Do a forward search from that location.
        let candidate = delegate.tailFindControllerPositionForTailSearchOfMainSearchEngine()
        let start: LineBufferPosition
        if let mainStart = mainSearchEngine.lastStartPosition, mainStart.compare(candidate) != .orderedDescending {
            start = mainStart
        } else {
            start = candidate
        }
        DLog("Begin tail find starting at \(start). Last position is \(candidate).")
        searchEngine.setFind(mainSearchEngine.query!,
                             forwardDirection: true,
                             mode: mainSearchEngine.mode,
                             startingAtX: 0,
                             startingAtY: 0,
                             withOffset: 0,
                             multipleResults: true,
                             absLineRange: delegate.tailFindControllerFindOnPageHelper().absLineRange,
                             forceMainScreen: false,
                             startPosition: start)
        continueTailFind()
        return true
    }

}
