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

@MainActor
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
    
    func initalRefresh() {
        if loadingState.state != .loading && dataSource.content.items.isEmpty {
            refresh(userInitiated: false)
        }
    }
    
    func refresh(userInitiated: Bool = true) {
        load(offset: nil, userInitiated: userInitiated)
    }
    
    func loadMore(userInitiated: Bool = false) {
        if (loadingState.state != .loading && dataSource.content.next != nil) || userInitiated {
            load(offset: dataSource.content.next, userInitiated: userInitiated)
        }
    }
    
    var atTheEnd: Bool { dataSource.content.items.count > 0 && dataSource.content.next == nil }
    
    var itemsCount: Int { dataSource.content.items.count }
}

@MainActor
public protocol PagingDataSource {
    associatedtype Item: Hashable
    
    var content: Paging<Item>.Content { get }
    
    func update(content: Paging<Item>.Content)
    
    func load(offset: AnyHashable?) async throws
}

public extension PagingDataSource {
    
    var anyContent: Paging<AnyHashable>.Content {
        .init(items: content.items, next: content.next, latestChange: content.latestChange)
    }
}

public enum Paging<Item: Hashable> { }

extension Paging {
    
    public struct Cache {
        let save: ([Item]) async ->()
        let load: ()->[Item]
        
        public init(save: @escaping ([Item]) -> (), load: @escaping () -> [Item]) {
            self.save = save
            self.load = load
        }
    }
    
    @MainActor
    public final class Manager<DataSource: PagingDataSource & ObservableObject>: ObservablePagingLoader where DataSource.Item == Item {
        
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

public enum Change {
    case refreshed
    case loadedMore
    case other
}

extension Paging {
    
    public struct Content: Equatable {
        
        public let items: [Item]
        public let next: AnyHashable?
        public let latestChange: Change
        
        public init(items: [Item] = [], next: AnyHashable? = nil, latestChange: Change = .other) {
            self.items = items
            self.next = next
            self.latestChange = latestChange
        }
    }
    
    public typealias CommonManager = Manager<DataSource>
    
    @MainActor
    public final class DataSource: PagingDataSource & ObservableObject {
        
        private nonisolated let direction: Direction
        
        @Published public private(set) var content = Content()
        
        public var loadPage: (@MainActor (_ offset: AnyHashable?) async throws -> Page<Item>)!
        public var cache: Cache? {
            didSet {
                if let items = cache?.load() {
                    content = Content(items: items)
                }
            }
        }
        
        public init(direction: Direction) {
            self.direction = direction
        }
        
        public func update(content: Content) {
            self.content = content
        }
        
        public func load(offset: AnyHashable?) async throws {
            let result = try await loadPage(offset)
            let directedItems = direction == .bottom ? result.items : result.items.reversed()
            
            if offset == nil {
                if content.items != directedItems || content.next != result.next {
                    update(content: .init(items: directedItems, next: result.next, latestChange: .refreshed))
                    await cache?.save(directedItems)
                }
            } else {
                await append(.init(items: directedItems, next: result.next), currentContent: self.content.items)
            }
        }
        
        private nonisolated func append(_ content: Page<Item>, currentContent: [Item]) async {
            let itemsToAdd = direction == .top ? content.items.reversed() : content.items
            var array = direction == .top ? currentContent.reversed() : currentContent
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
                                        next: allItemsAreTheSame ? nil : content.next,
                                        latestChange: .loadedMore))
        }
    }
    
    public typealias CustomManager = Manager<CustomDataSource>
    
    @MainActor
    public final class CustomDataSource: PagingDataSource & ObservableObject {
        
        public var content: Paging<Item>.Content { self.get() }
        private let get: () -> Paging<Item>.Content
        private let load: @MainActor (_ offset: AnyHashable?) async throws ->()
        private var observer: AnyCancellable?
        
        public init<State: ObservableObject>(state: State,
                                             get: @escaping (State)->Paging<Item>.Content,
                                             load: @escaping @MainActor (_ offset: AnyHashable?, State) async throws ->()) {
            self.load = { try await load($0, state) }
            self.get = { get(state) }
            
            observer = state.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        
        public func update(content: Paging<Item>.Content) { }
        
        public func load(offset: AnyHashable?) async throws {
            try await load(offset)
        }
    }
}
