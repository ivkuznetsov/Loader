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
    @State var isVisible: Bool = false
    
    var hideLoading: Bool {
        if state.paging?.atTheEnd == true { return true }
        
        let hasItems = (state.paging?.itemsCount ?? 0) > 0
        
        if loadingState.state == .loading && state.refreshing != nil && hasItems {
            return true
        }
        
        if loadingState.state != .stop && state.paging?.initialLoading == .opaque() && !hasItems {
            return true
        }
        return false
    }
    
    public var body: some View {
        ZStack {
            if hideLoading {
                Color.clear
            } else {
                switch loadingState.state {
                case .stop: Color.clear
                case .failed(_, _): Button("Retry") { state.retry() }
                case .loading: InCellProgressView()
                }
            }
        }.frame(height: 30).frame(maxWidth: .infinity).background {
            GeometryReader {
                updateIsVisible(proxy: $0)
            }
        }.listRowSeparator(.hidden)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
    
    private func updateIsVisible(proxy: GeometryProxy) -> some View {
        state.isLoadingVisible = isVisible && state.containerFrame.intersects(proxy.frame(in: .global))
        return Color.clear
    }
}
