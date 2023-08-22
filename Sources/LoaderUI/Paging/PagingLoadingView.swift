//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 22/08/2023.
//

import Foundation
import SwiftUI
import Loader

public struct PagingLoadingView: View {
    
    @ObservedObject var state: PagingContainerState
    @ObservedObject var loadingState: LoadingState
    
    public var body: some View {
        ZStack {
            switch loadingState.value {
            case .stop: Color.clear
            case .failed(_): Button("Retry") { state.retry() }
            case .loading:
                if state.refreshing == nil {
                    InCellProgressView()
                }
            }
        }.frame(height: state.paging?.atTheEnd == true ? 0 : 44).background {
            GeometryReader { updateIsVisible(proxy: $0) }
        }
    }
    
    private func updateIsVisible(proxy: GeometryProxy) -> some View {
        state.isLoadingVisible = state.containerFrame.intersects(proxy.frame(in: .global))
        return Color.clear
    }
}
