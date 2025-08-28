//
//  iTermHistogramVisualizationView.swift
//  iTerm2
//
//  Created by George Nachman on 8/27/25.
//

import SwiftUI
import AppKit
import Charts

@available(macOS 13, *)
@objc
class iTermHistogramVisualizationView: NSView {
    @objc(initWithHistogram:)
    init?(_ histogram: iTermHistogram) {
        super.init(frame: .zero)

        guard let chart = iTermHistogramBarChart(histogram) else {
            return nil
        }
        let hostingView = NSHostingView(rootView: chart)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set compression resistance to prevent the view from being compressed smaller than its content
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        // Set hugging priority lower so it can expand if there's extra space
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        addSubview(hostingView)

        // Set up constraints to fill the parent view
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}


@available(macOS 13, *)
struct iTermHistogramBarChart: View {
    let buckets: [(x: Double, y: Int, range: Range<Double>)]
    let meanValue: Double
    @State private var selectedX: Double?

    init?(_ histogram: iTermHistogram) {
        buckets = histogram.bucketData().map { dict in
            let lowerBound = dict["lowerBound"] as! Double
            let upperBound = dict["upperBound"] as! Double
            let count = dict["count"] as! Int
            return (x: (lowerBound + upperBound) / 2.0,
                    y: count,
                    range: lowerBound..<upperBound)
        }
        if buckets.isEmpty {
            return nil
        }
        meanValue = histogram.mean
    }

    var body: some View {
        VStack {
            Group {
                if #available(macOS 14, *) {
                    Chart {
                        chartContent
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let selectedX = selectedX,
                               let bucket = buckets.first(where: { $0.x == selectedX }) {
                                let xPosition = proxy.position(forX: bucket.x) ?? 0
                                let chartMidpoint = geometry.size.width / 2
                                
                                HStack {
                                    if xPosition < chartMidpoint {
                                        Spacer()
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Duration: \(bucket.range.lowerBound, specifier: "%.1f")µs–\(bucket.range.upperBound, specifier: "%.1f")µs")
                                        Text("Count: \(bucket.y)")
                                    }
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .foregroundColor(Color(NSColor.labelColor))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color(NSColor.labelColor).opacity(0.5), lineWidth: 1)
                                    )
                                    if xPosition >= chartMidpoint {
                                        Spacer()
                                    }
                                }
                                .padding(8)
                                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            }
                        }
                    }
                    .chartXSelection(value: Binding(
                        get: { selectedX },
                        set: { newValue in
                            if let newValue = newValue {
                                // Find closest bucket
                                selectedX = buckets.min(by: { abs($0.x - newValue) < abs($1.x - newValue) })?.x
                            } else {
                                selectedX = nil
                            }
                        }
                    ))
                } else {
                    Chart {
                        chartContent
                    }
                }
            }
            .padding(.top, 12)
            .chartXAxis {
                AxisMarks() { value in
                    AxisTick()
                    AxisGridLine()
                    AxisValueLabel {
                        if let µs = value.as(Double.self) {
                            Text("\(µs, specifier: "%.0f")µs")
                        }
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private var chartContent: some ChartContent {
        ForEach(buckets, id: \.x) { bucket in
            RectangleMark(
                xStart: .value("Start", bucket.range.lowerBound),
                xEnd: .value("End", bucket.range.upperBound),
                yStart: .value("Count", 0),
                yEnd: .value("Count", bucket.y)
            )
            .foregroundStyle(selectedX == bucket.x ? .purple : .blue)
        }
        RuleMark(x: .value("Mean", meanValue))
            .foregroundStyle(.red.opacity(0.75))
            .lineStyle(StrokeStyle(lineWidth: 2))
    }
}
