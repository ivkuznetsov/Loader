//
//  LoadingBar.swift
//

import SwiftUI
import Loader

#if os(iOS)

public struct LoadingBar: View {
    
    @ObservedObject private var operation: Loader.Operation
    
    public init(operation: Loader.Operation) {
        self.operation = operation
    }
    
    private struct InfiniteBar: View {
        
        @State private var startAnimation: Bool = false
        
        var body: some View {
            GeometryReader { proxy in
                Path {
                    $0.move(to: CGPoint(x: 0, y: 0.15))
                    $0.addLine(to: CGPoint(x: proxy.size.width, y: 0.15))
                }.stroke(Color(.label).opacity(0.1), style: .init(lineWidth: 3,
                                                                     lineCap: .round,
                                                                     dash: [5, 8],
                                                                     dashPhase: startAnimation ? -50 : 0))
                .animation(Animation.linear.repeatForever(autoreverses: false), value: startAnimation)
                .onAppear { startAnimation = true }
            }
        }
    }
    
    private struct ProgressBar: View {
        
        let progress: Double
        
        var body: some View {
            GeometryReader { proxy in
                Path {
                    $0.move(to: CGPoint(x: 0, y: 0.15))
                    $0.addLine(to: CGPoint(x: proxy.size.width, y: 0.15))
                }.trim(to: progress)
                    .stroke(.tint, style: .init(lineWidth: 3, lineCap: .round))
                    .animation(.easeOut, value: progress)
                        
            }
        }
    }
    
    public var body: some View {
        VStack {
            ZStack {
                Color.secondary.opacity(0.2)
                if operation.progress > 0 {
                    ProgressBar(progress: operation.progress)
                } else {
                    InfiniteBar()
                }
            }.frame(height: 3, alignment: .top)
            Spacer()
        }
    }
}

#endif
