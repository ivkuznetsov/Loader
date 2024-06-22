//
//  PagingContainer.swift
//

import Foundation
import SwiftUI
import Combine
@_exported import Loader

public struct PagingParameters<Item: Hashable> {
    
    public let content: Paging<Item>.Content
    public let loading: PagingLoadingView
    public let refresh: () async -> ()
}

public struct PagingContainer<Content: View>: View {
    
    @StateObject private var state = PagingContainerState()
    @ObservedObject private var paging: ObservableWrapper<any ObservablePagingLoader>
    
    private let makeContent: (Self)->Content
    
    public init<Paging: ObservablePagingLoader>(_ paging: Paging,
                                                content: @escaping (_ paramenters: PagingParameters<Paging.DataSource.Item>) -> Content) {
        self.paging = .init(paging)
        self.makeContent = { content($0.parameters(content: paging.dataSource.content)) }
    }
    
    public init(any paging: any ObservablePagingLoader,
                content: @escaping (_ features: PagingParameters<AnyHashable>) -> Content) {
        self.paging = .init(paging)
        self.makeContent = { content($0.parameters(content: paging.dataSource.anyContent)) }
    }
    
    private func updateContainerFrame(proxy: GeometryProxy) -> some View {
        state.containerFrame = proxy.frame(in: .global)
        return Color.clear
    }
    
    private func parameters<Item: Hashable>(content: Paging<Item>.Content) -> PagingParameters<Item> {
        .init(content: content,
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
        makeContent(self)
            .animation(state.oldItemsCount > 0 && paging.observed.itemsCount > 0 ? .easeOut : nil,
                       value: paging.observed.itemsCount)
            .onChange(of: paging.observed.itemsCount, perform: { state.oldItemsCount = $0 })
            .transaction { transaction in
                if paging.observed !== state.paging {
                    transaction.disablesAnimations = true
                    state.paging = paging.observed
                }
            }
            .background {
                GeometryReader { updateContainerFrame(proxy: $0) }
            }.onAppear {
                state.paging = paging.observed
            }.onDisappear(perform: {
                state.contentCache = nil
            }).onReceive(paging.objectWillChange) {
                state.contentCache = nil
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
