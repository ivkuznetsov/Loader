//
//  InCellProgressView.swift
//

import Foundation
import SwiftUI

private struct InCellProgressViewRepresentable: UIViewRepresentable {
    
    @Binding var updater: Bool
    let style: InCellProgressView.Style
    
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView()
        indicator.startAnimating()
        indicator.hidesWhenStopped = false
        indicator.style = style == .big ? .large : .medium
        return indicator
    }
    
    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        _ = updater
        uiView.startAnimating()
    }
}

public struct InCellProgressView: View {
    
    public enum Style {
        case big
        case small
    }
    
    private let style: Style
    @State private var updater: Bool = true
    
    public init(style: Style = .small) {
        self.style = style
    }
    
    public var body: some View {
        InCellProgressViewRepresentable(updater: $updater, style: style).onAppear {
            updater.toggle()
        }
    }
}
