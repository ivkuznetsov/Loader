//
//  FailToast.swift
//

import SwiftUI
@_exported import Loader

#if os(iOS)

public struct FailToast: View {
    
    private let fail: Loader.Operation.Fail
    @State private var isPresented = false
    
    public init(fail: Loader.Operation.Fail) {
        self.fail = fail
    }
    
    public var body: some View {
        VStack {
            Text(fail.error.localizedDescription)
                .foregroundColor(Color.white)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .padding(.all, 15)
                .background(content: {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.regularMaterial)
                        .environment(\.colorScheme, .dark)
                })
                .padding(.all, 15)
            Spacer()
        }.scaleEffect(isPresented ? 1 : 0.9)
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : -50)
            .onAppear(perform: {
                withAnimation(.easeOut) {
                    isPresented = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    fail.dismiss()
                }
            })
    }
}

#endif
