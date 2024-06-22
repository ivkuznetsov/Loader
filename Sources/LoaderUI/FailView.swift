//
//  FailView.swift
//

import SwiftUI
@_exported import Loader

#if os(iOS)

public struct FailView: View {
    
    private let fail: Loader.Operation.Fail
    private let backgroundColor: Color
    
    public init(fail: Loader.Operation.Fail, backgroundColor: Color = Color(.systemBackground)) {
        self.fail = fail
        self.backgroundColor = backgroundColor
    }
    
    public var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            VStack(spacing: 0) {
                Text(fail.error.localizedDescription)
                    .font(.system(size: 14))
                    .foregroundColor(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.all, 30)
                    .frame(maxWidth: 400)
                
                if let retry = fail.retry {
                    Button("Retry", action: retry)
                }
            }
        }
    }
}

#endif
