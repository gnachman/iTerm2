//
//  HorizontalFileListView.swift
//  iTerm2
//
//  Created by George Nachman on 6/2/25.
//

import Cocoa

@objc class HorizontalFileListView: NSView {
    var files: [String] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.collectionView.reloadData()

                // Force layout update
                self.collectionView.needsLayout = true
                self.collectionView.layoutSubtreeIfNeeded()

                // Update scroll view content size
                self.scrollView.needsLayout = true
                self.scrollView.layoutSubtreeIfNeeded()

                // Update intrinsic size and parent layout
                self.invalidateIntrinsicContentSize()
                self.needsLayout = true

                // Additional layout pass after a brief delay if needed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self.collectionView.layoutSubtreeIfNeeded()
                }
            }
        }
    }

    private let scrollView: NSScrollView
    private let collectionView: NSCollectionView
    private let flowLayout: NSCollectionViewFlowLayout

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        // Create flow layout
        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: 80, height: 100)
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        // Create collection view
        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.backgroundColors = [NSColor.clear]

        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

        super.init(frame: frameRect)

        setupView()
        setupCollectionView()
    }

    required init?(coder: NSCoder) {
        // Create flow layout
        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: 80, height: 100)
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        // Create collection view
        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.backgroundColors = [NSColor.clear]

        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

        super.init(coder: coder)

        setupView()
        setupCollectionView()
    }

    // MARK: - Setup

    private func setupView() {
        addSubview(scrollView)

        // Auto Layout
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupCollectionView() {
        // Register the item class
        collectionView.register(FileItemView.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("FileItem"))

        // Set data source and delegate
        collectionView.dataSource = self
        collectionView.delegate = self

        // Ensure the collection view is ready
        collectionView.reloadData()
        collectionView.needsLayout = true
    }

    // MARK: - Public Methods

    // MARK: - Intrinsic Content Size

    override var intrinsicContentSize: NSSize {
        let itemWidth = flowLayout.itemSize.width
        let spacing = flowLayout.minimumLineSpacing
        let sectionInsets = flowLayout.sectionInset

        let totalItemsWidth = CGFloat(files.count) * itemWidth
        let totalSpacing = CGFloat(max(0, files.count - 1)) * spacing
        let totalWidth = totalItemsWidth + totalSpacing + sectionInsets.left + sectionInsets.right

        let height = flowLayout.itemSize.height + sectionInsets.top + sectionInsets.bottom

        return NSSize(width: min(totalWidth, 600), height: height) // Cap max width at 600pt
    }
}

// MARK: - NSCollectionViewDataSource

extension HorizontalFileListView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return files.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("FileItem"), for: indexPath) as! FileItemView
        let filePath = files[indexPath.item]
        item.configure(with: filePath)
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension HorizontalFileListView: NSCollectionViewDelegate {
    // Add any delegate methods as needed
}

// MARK: - File Item View

class FileItemView: NSCollectionViewItem {
    private let iconImageView: NSImageView
    private let nameLabel: NSTextField
    private let containerView: NSView

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        iconImageView = NSImageView()
        nameLabel = NSTextField()
        containerView = NSView()

        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupViews()
    }

    required init?(coder: NSCoder) {
        iconImageView = NSImageView()
        nameLabel = NSTextField()
        containerView = NSView()

        super.init(coder: coder)

        setupViews()
    }

    override func loadView() {
        view = containerView
    }

    private func setupViews() {
        // Configure icon image view
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.imageAlignment = .alignCenter

        // Configure name label
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = NSColor.clear
        nameLabel.alignment = .center
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2

        // Add subviews
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)

        // Auto Layout
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Icon constraints
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 5),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            // Label constraints
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -5)
        ])
    }

    func configure(with filePath: String) {
        // Get file name without path
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        nameLabel.stringValue = fileName

        // Get file icon from system
        let fileURL = URL(fileURLWithPath: filePath)
        let icon = NSWorkspace.shared.icon(forFile: filePath)
        iconImageView.image = icon
    }
}
