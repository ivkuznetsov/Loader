//
//  Paging.swift
//  

#if os(iOS)
import UIKit
#else
import AppKit
#endif
import Combine
import SwiftUI

public protocol PagingLoader {
    associatedtype DataSource: PagingDataSource
    
    var initialLoading: Loader.Operation.Presentation { get }
    
    var dataSource: DataSource { get }
    
    var loader: Loader { get }
    
    var loadingState: LoadingState { get }
    
    func load(offset: AnyHashable?, userInitiated: Bool)
}

public typealias ObservablePagingLoader = PagingLoader & ObservableObject

public extension PagingLoader {
    
    @MainActor
    func initalRefresh() {
        if loadingState.state != .loading && dataSource.content.items.isEmpty {
            refresh(userInitiated: false)
        }
    }
    
    func refresh(userInitiated: Bool = true) {
        load(offset: nil, userInitiated: userInitiated)
    }
    
    @MainActor
    func loadMore(userInitiated: Bool = false) {
        if (loadingState.state != .loading && dataSource.content.next != nil) || userInitiated {
            load(offset: dataSource.content.next, userInitiated: userInitiated)
        }
    }
    
    var atTheEnd: Bool { dataSource.content.items.count > 0 && dataSource.content.next == nil }
    
    var itemsCount: Int { dataSource.content.items.count }
}

public protocol PagingDataSource {
    associatedtype Item: Hashable
    
    var content: Page<Item> { get }
    
    func update(content: Page<Item>)
    
    func load(offset: AnyHashable?) async throws
}

public extension PagingDataSource {
    
    var anyContent: Page<AnyHashable> {
        .init(items: content.items, next: content.next)
    }
}

public enum Paging<Item: Hashable> { }

extension Paging {
    
    public struct Cache {
        let save: ([Item])->()
        let load: ()->[Item]
        
        public init(save: @escaping ([Item]) -> (), load: @escaping () -> [Item]) {
            self.save = save
            self.load = load
        }
    }
    
    public final class Manager<DataSource: PagingDataSource & ObservableObject>: ObservablePagingLoader {
    
        public let initialLoading: Loader.Operation.Presentation
        private let uid = UUID().uuidString
        
        public let loader: Loader
        public let loadingState = LoadingState()
        public let dataSource: DataSource
        private var observer: AnyCancellable?
        
        public init(initialLoading: Loader.Operation.Presentation = .opaque(),
                    dataSource: DataSource,
                    loader: Loader = .init()) {
            self.initialLoading = initialLoading
            self.dataSource = dataSource
            self.loader = loader
            
            observer = dataSource.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        
        @MainActor
        public func load(offset: AnyHashable?, userInitiated: Bool) {
            loader.run(userInitiated ? .none(fail: .modal) : (dataSource.content.items.isEmpty ? initialLoading : .none(fail: offset == nil ? .nonblocking : .none)),
                       id: uid) { [weak self] _ in
                do {
                    self?.loadingState.state = .loading
                    try await self?.dataSource.load(offset: offset)
                    self?.loadingState.state = .stop
                } catch {
                    if Loader.isSuppressed(error) {
                        self?.loadingState.state = .stop
                    } else {
                        self?.loadingState.state = .failed(error)
                    }
                    throw error
                }
            }
        }
        
        @MainActor
        public func reset() {
            loader.cancelOperation(uid)
            dataSource.update(content: .init())
        }
    }
}

public enum Direction {
    case bottom
    case top
}

public extension Paging.Manager where DataSource == Paging.DataSource {
    
    convenience init(initialLoading: Loader.Operation.Presentation = .opaque(), loader: Loader = .init()) {
        self.init(initialLoading: initialLoading, dataSource: .init(direction: .bottom), loader: loader)
    }
}

extension Paging {
    public typealias CommonManager = Manager<DataSource>
    
    public final class DataSource: PagingDataSource & ObservableObject {
        
        private let direction: Direction
        private let cache: Cache?
        @Published public private(set) var content = Page<Item>()
        
        public var loadPage: ((_ offset: AnyHashable?) async throws -> Page<Item>)!
        
        public init(direction: Direction, cache: Cache? = nil) {
            self.direction = direction
            self.cache = cache
            
            if let items = cache?.load() {
                content = Page(items: items)
            }
        }
        
        @MainActor
        public func update(content: Page<Item>) {
            self.content = content
        }
        
        public func load(offset: AnyHashable?) async throws {
            let result = try await loadPage(offset)
            
            if offset == nil {
                if content != result {
                    cache?.save(result.items)
                    await update(content: result)
                }
            } else {
                await append(result)
            }
        }
        
        private func append(_ content: Page<Item>) async {
            let itemsToAdd = direction == .top ? content.items.reversed() : content.items
            var array = direction == .top ? self.content.items.reversed() : self.content.items
            var set = Set(array)
            var allItemsAreTheSame = true // backend returned the same items for the next page, prevent infinit loading
            
            itemsToAdd.forEach {
                if !set.contains($0) {
                    set.insert($0)
                    array.append($0)
                    allItemsAreTheSame = false
                }
            }
            await update(content: .init(items: direction == .top ? array.reversed() : array,
                                        next: allItemsAreTheSame ? nil : content.next))
        }
    }
    
    public typealias CustomManager = Manager<CustomDataSource>
    
    public final class CustomDataSource: PagingDataSource & ObservableObject {
        
        public var content: Page<Item> { self.get() }
        private let get: () -> Page<Item>
        private let load: (_ offset: AnyHashable?) async throws ->()
        private var observer: AnyCancellable?
        
        public init<State: ObservableObject>(state: State,
                                             get: @escaping (State)->Page<Item>,
                                             load: @escaping (_ offset: AnyHashable?, State) async throws ->()) {
            self.load = { try await load($0, state) }
            self.get = { get(state) }
            
            observer = state.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        
        public func update(content: Page<Item>) { }
        
        public func load(offset: AnyHashable?) async throws {
            try await load(offset)
        }
    }
}
