//
//  PagingContainer.swift
//

import Foundation
import SwiftUI
import Combine
import Loader

public struct PagingParameters<Item: Hashable> {
    public let items: [Item]
    public let loading: PagingLoadingView
    public let refresh: () async -> ()
}

public struct PagingContainer<Content: View>: View {
    
    @StateObject private var state = PagingContainerState()
    @ObservedObject private var paging: ObservableWrapper<any ObservablePagingLoader>
    
    private let content: (Self)->Content
    
    public init<Paging: ObservablePagingLoader>(_ paging: Paging,
                                                content: @escaping (_ paramenters: PagingParameters<Paging.DataSource.Item>) -> Content) {
        self.paging = .init(paging)
        self.content = { content($0.parameters(items: paging.dataSource.content.items)) }
    }
    
    public init(any paging: any ObservablePagingLoader,
                content: @escaping (_ features: PagingParameters<AnyHashable>) -> Content) {
        self.paging = .init(paging)
        self.content = { content($0.parameters(items: paging.dataSource.anyContent.items)) }
    }
    
    private func updateContainerFrame(proxy: GeometryProxy) -> some View {
        state.containerFrame = proxy.frame(in: .global)
        return Color.clear
    }
    
    private func parameters<Item: Hashable>(items: [Item]) -> PagingParameters<Item> {
        .init(items: items,
              loading: .init(state: state, loadingState: paging.observed.loadingState),
              refresh: {
            await withCheckedContinuation { continuation in
                paging.observed.refresh(userInitiated: true)
                state.refreshing = paging.observed.loadingState.$state.dropFirst().sink(receiveValue: {
                    if $0 != .loading {
                        state.refreshing = nil
                        continuation.resume()
                    }
                })
            }
        })
    }
    
    public var body: some View {
        content(self)
            .transaction { transaction in
                if paging.observed !== state.paging {
                    transaction.disablesAnimations = true
                    state.paging = paging.observed
                }
            }
            .animation(.easeOut, value: paging.observed.itemsCount)
            .background {
                GeometryReader { updateContainerFrame(proxy: $0) }
            }.onAppear {
                state.paging = paging.observed
            }
    }
}

private final class ObservableWrapper<Value>: ObservableObject {
    
    public fileprivate(set) var observed: Value
    private var observer: AnyCancellable?
    
    public init(_ observable: Value) {
        self.observed = observable
        
        observer = (observable as? any ObservableObject)?.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }
}

extension ObservableObject {
    
    func sink(_ closure: @escaping ()->()) -> AnyCancellable {
        objectWillChange.sink { _ in closure() }
    }
}
