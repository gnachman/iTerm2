import AVKit
import AVFoundation
import Carbon
import Cocoa

class WindowClosingAVPlayerView: AVPlayerView {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            self.window?.orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

class VideoPlaybackWindowController: NSWindowController, NSMenuItemValidation {
    private var player: AVPlayer?
    private var playerView: AVPlayerView!
    private var scrubber: NSSlider!
    private var timestampLabel: NSTextField!
    private var playPauseButton: NSButton!
    private var playBackwardButton: NSButton!
    private var revealInFinderButton: NSButton!
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var videoURL: URL?
    private var transform: CGAffineTransform = .identity
    private var baseTransform: CGAffineTransform = .identity
    private var progressIndicator: NSProgressIndicator!

    init(videoSize: NSSize) {
        let controlsHeight: CGFloat = 60
        let windowWidth = videoSize.width
        let windowHeight = videoSize.height + controlsHeight
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instant Replay"
        window.center()
        
        super.init(window: window)
        
        setupUI()
        setupKeyHandling()
    }
    
    func setVideoURL(_ url: URL) {
        self.videoURL = url
        setupPlayer()
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }

    @objc(closeCurrentSession:)
    func closeCurrentSession(_ sender: Any) {
        window?.performClose(sender)
    }

    private func setupUI() {
        guard let window = window else { return }
        
        let contentView = NSView()
        window.contentView = contentView
        
        playerView = WindowClosingAVPlayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .none
        playerView.isHidden = true
        contentView.addSubview(playerView)
        
        // Add pinch to zoom support
        let magnificationGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        playerView.addGestureRecognizer(magnificationGesture)
        
        // Progress indicator
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.startAnimation(nil)
        contentView.addSubview(progressIndicator)
        
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(visualEffectView)
        
        let controlsContainer = NSView()
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(controlsContainer)
        
        let separatorLine = iTermLayerBackedSolidColorView()
        separatorLine.color = NSColor.separatorColor
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separatorLine)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        playBackwardButton = NSButton()
        playBackwardButton.image = NSImage(systemSymbolName: SFSymbol.arrowtriangleBackwardFill.rawValue, accessibilityDescription: "Play Backward")?.withSymbolConfiguration(symbolConfig)
        playBackwardButton.bezelStyle = .shadowlessSquare
        playBackwardButton.isBordered = false
        playBackwardButton.target = self
        playBackwardButton.action = #selector(togglePlayBackward)
        playBackwardButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(playBackwardButton)
        
        playPauseButton = NSButton()
        playPauseButton.image = NSImage(systemSymbolName: SFSymbol.playFill.rawValue, accessibilityDescription: "Play")?.withSymbolConfiguration(symbolConfig)
        playPauseButton.bezelStyle = .shadowlessSquare
        playPauseButton.isBordered = false
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(playPauseButton)
        
        scrubber = NSSlider()
        scrubber.minValue = 0
        scrubber.maxValue = 1
        scrubber.doubleValue = 0
        scrubber.target = self
        scrubber.action = #selector(scrubberChanged)
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(scrubber)
        
        timestampLabel = NSTextField()
        timestampLabel.isEditable = false
        timestampLabel.isBordered = false
        timestampLabel.backgroundColor = .clear
        timestampLabel.stringValue = "00:00 / 00:00"
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(timestampLabel)
        
        revealInFinderButton = NSButton()
        let smallerSymbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        revealInFinderButton.image = NSImage(systemSymbolName: SFSymbol.arrowUpRightSquare.rawValue, accessibilityDescription: "Reveal in Finder")?.withSymbolConfiguration(smallerSymbolConfig)
        revealInFinderButton.bezelStyle = .shadowlessSquare
        revealInFinderButton.isBordered = false
        revealInFinderButton.target = self
        revealInFinderButton.action = #selector(revealInFinder)
        revealInFinderButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(revealInFinderButton)
        
        // Disable controls initially
        setControlsEnabled(false)
        
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: -10),
            
            progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -30),
            
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            visualEffectView.heightAnchor.constraint(equalToConstant: 60),
            
            controlsContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 12),
            controlsContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -12),
            controlsContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -8),
            controlsContainer.heightAnchor.constraint(equalToConstant: 44),
            
            separatorLine.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 1.0),
            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
            
            playBackwardButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            playBackwardButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playBackwardButton.widthAnchor.constraint(equalToConstant: 44),
            playBackwardButton.heightAnchor.constraint(equalToConstant: 44),
            
            playPauseButton.leadingAnchor.constraint(equalTo: playBackwardButton.trailingAnchor, constant: 8),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 44),
            playPauseButton.heightAnchor.constraint(equalToConstant: 44),
            
            scrubber.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 16),
            scrubber.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            scrubber.trailingAnchor.constraint(equalTo: timestampLabel.leadingAnchor, constant: -12),
            
            timestampLabel.trailingAnchor.constraint(equalTo: revealInFinderButton.leadingAnchor, constant: -12),
            timestampLabel.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            timestampLabel.widthAnchor.constraint(equalToConstant: 120),
            
            revealInFinderButton.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            revealInFinderButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            revealInFinderButton.widthAnchor.constraint(equalToConstant: 32),
            revealInFinderButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    private func setupPlayer() {
        guard let videoURL = videoURL else { return }
        
        let asset = AVAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        playerView.player = player
        
        // Observe player item status changes
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self?.progressIndicator.stopAnimation(nil)
                    self?.progressIndicator.isHidden = true
                    self?.playerView.isHidden = false
                    self?.setControlsEnabled(true)
                    self?.updateDurationDisplay()
                    self?.seekToLastFrame()
                }
            }
        }
        
        // Observe when playback reaches the end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
            DispatchQueue.main.async {
                self?.updateScrubberRange()
                self?.updateDurationDisplay()
                self?.setupTimeObserver()
            }
        }
    }
    
    private func setControlsEnabled(_ enabled: Bool) {
        playPauseButton.isEnabled = enabled
        playBackwardButton.isEnabled = enabled
        scrubber.isEnabled = enabled
        revealInFinderButton.isEnabled = enabled && videoURL != nil
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateUI(currentTime: time)
        }
    }


    private func setupKeyHandling() {
        window?.acceptsMouseMovedEvents = true
    }
    
    private func getVideoDuration() -> Double? {
        guard let playerItem = player?.currentItem else { return nil }
        let duration = playerItem.duration
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds.isFinite && durationSeconds > 0 else { return nil }
        
        return durationSeconds
    }
    
    private func updateScrubberRange() {
        if let duration = getVideoDuration() {
            scrubber.maxValue = duration
        }
    }
    
    private func updateUI(currentTime: CMTime) {
        let currentSeconds = CMTimeGetSeconds(currentTime)
        let durationSeconds = CMTimeGetSeconds(player?.currentItem?.duration ?? CMTime.zero)
        
        if currentSeconds.isFinite && durationSeconds.isFinite && durationSeconds > 0 {
            // Update scrubber range if needed (duration becomes available later)
            if let duration = getVideoDuration(), scrubber.maxValue != duration {
                scrubber.maxValue = duration
            }
            
            // Show the actual current time without clamping
            scrubber.doubleValue = currentSeconds
            
            let currentTimeString = formatTime(currentSeconds)
            let durationString = formatTime(durationSeconds)
            timestampLabel.stringValue = "\(currentTimeString) / \(durationString)"
        }
        
        if let player = player {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            
            // Update forward play/pause button
            let forwardSymbolName = player.rate > 0 ? SFSymbol.pauseFill.rawValue : SFSymbol.playFill.rawValue
            playPauseButton.image = NSImage(systemSymbolName: forwardSymbolName, accessibilityDescription: player.rate > 0 ? "Pause" : "Play")?.withSymbolConfiguration(symbolConfig)
            
            // Update backward play button
            let backwardSymbolName = player.rate < 0 ? SFSymbol.pauseFill.rawValue : SFSymbol.arrowtriangleBackwardFill.rawValue
            playBackwardButton.image = NSImage(systemSymbolName: backwardSymbolName, accessibilityDescription: player.rate < 0 ? "Pause" : "Play Backward")?.withSymbolConfiguration(symbolConfig)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    @objc private func togglePlayPause() {
        guard let player = player else { return }
        
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }
    
    @objc private func togglePlayBackward() {
        guard let player = player else { return }
        
        if player.rate < 0 {
            // Already playing backward, pause
            player.pause()
        } else {
            // Start playing backward
            player.rate = -1.0
        }
    }
    
    
    @objc private func scrubberChanged() {
        guard let duration = player?.currentItem?.duration else { return }
        let durationSeconds = CMTimeGetSeconds(duration)
        let seekSeconds = min(scrubber.doubleValue, durationSeconds)
        let time = CMTime(seconds: seekSeconds, preferredTimescale: 600)
        player?.seek(to: time)
    }
    
    @objc private func revealInFinder() {
        guard let videoURL = videoURL else { return }
        NSWorkspace.shared.selectFile(videoURL.path, inFileViewerRootedAtPath: "")
    }
    
    @objc private func playerDidFinishPlaying() {
        // When playback reaches the end, update button states
        if let player = player {
            updateUI(currentTime: player.currentTime())
        }
    }
    
    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard let playerView = playerView,
              let layer = playerView.layer else { return }

        if gesture.state == .began {
            baseTransform = transform
            layer.anchorPoint = .zero
            layer.transform = transform.transform3D
        } else if gesture.state == .changed {
            let gestureTransform = baseTransform.concatenating(gesture.affineTransform)
            if gestureTransform.horizontalScale >= 1.0 {
                transform = gestureTransform
            } else {
                transform = .identity
            }
            layer.transform = transform.transform3D
        } else if gesture.state == .ended || gesture.state == .cancelled {
            if abs(transform.horizontalScale - 1.0) < 0.15 && transform.translationMagnitude < 100.0 {
                transform = .identity
                layer.transform = transform.transform3D
            }
        }
    }
    
    private func updateDurationDisplay() {
        guard let playerItem = player?.currentItem else { return }
        let duration = playerItem.duration
        let durationSeconds = CMTimeGetSeconds(duration)
        
        if durationSeconds.isFinite && durationSeconds > 0 {
            let durationString = formatTime(durationSeconds)
            timestampLabel.stringValue = "00:00 / \(durationString)"
            
            // Set scrubber range to full video duration
            if let duration = getVideoDuration() {
                scrubber.maxValue = duration
            }
        }
    }
    
    private func seekToLastFrame() {
        guard let player, let playerItem = player.currentItem else {
            return
        }

        player.seek(to: playerItem.duration,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.positiveInfinity) { [weak self] _ in
            DispatchQueue.main.async {
                self?.player?.preroll(atRate: 0.0, completionHandler: nil)
            }
        }
    }
}

extension NSMagnificationGestureRecognizer {
    var affineTransform: CGAffineTransform {
        guard let view = self.view else { return .identity }

        let scale = 1.0 + magnification
        let location = self.location(in: view)

        // Create transform that scales around the gesture location
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: location.x, y: location.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -location.x, y: -location.y)

        return transform
    }
}

extension CGAffineTransform {
    var transform3D: CATransform3D {
        return CATransform3D(
            m11: CGFloat(a), m12: CGFloat(b), m13: 0, m14: 0,
            m21: CGFloat(c), m22: CGFloat(d), m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: CGFloat(tx), m42: CGFloat(ty), m43: 0, m44: 1
        )
    }

    var horizontalScale: CGFloat {
        a
    }

    var verticalScale: CGFloat {
        d
    }

    var translation: CGPoint {
        return CGPoint(x: tx, y: ty)
    }
    
    var translationMagnitude: CGFloat {
        return sqrt(tx * tx + ty * ty)
    }
}
