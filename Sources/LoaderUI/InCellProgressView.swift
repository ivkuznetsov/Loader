//
//  InCellProgressView.swift
//

import Foundation
import SwiftUI

private struct InCellProgressViewRepresentable: UIViewRepresentable {
    
    let tintColor: UIColor
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
        uiView.color = tintColor
        uiView.startAnimating()
    }
}

public struct InCellProgressView: View {
    
    public enum Style {
        case big
        case small
    }
    
    private let tintColor: UIColor
    private let style: Style
    @State private var updater: Bool = true
    
    public init(tintColor: UIColor = .label, style: Style = .small) {
        self.style = style
        self.tintColor = tintColor
    }
    
    public var body: some View {
        InCellProgressViewRepresentable(tintColor: tintColor, updater: $updater, style: style).onAppear {
            updater.toggle()
        }
    }
}
