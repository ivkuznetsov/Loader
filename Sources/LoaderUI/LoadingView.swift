//
//  LoadingView.swift
//

import SwiftUI
@_exported import Loader

#if os(iOS)

public struct LoadingView: View {
    
    private struct CircularProgressView: View {
        
        let progress: Double
        
        var body: some View {
            ZStack {
                Circle().stroke(Color(.label).opacity(0.1), style: .init(lineWidth: 3))
                Circle()
                    .trim(from: 0, to: progress)
                    .rotation(.degrees(-90))
                    .stroke(Color(.label), style: .init(lineWidth: 3, lineCap: .round))
            }.frame(width: 50, height: 50)
                .animation(.easeOut, value: progress)
        }
    }
    
    @ObservedObject private var operation: Loader.Operation
    private let backgroundColor: Color
    
    public init(operation: Loader.Operation, backgroundColor: Color) {
        self.operation = operation
        self.backgroundColor = backgroundColor
    }
    
    public init(operation: Loader.Operation) {
        self.init(operation: operation, backgroundColor: Color(.systemBackground))
    }
    
    public var body: some View {
        ZStack {
            backgroundColor
                .opacity(operation.presentation == .opaque() ? 1 : 0.7)
                .ignoresSafeArea()
            
            if operation.progress > 0 {
                CircularProgressView(progress: operation.progress)
            } else {
                InCellProgressView(style: .big)
            }
        }
    }
}

#endif
