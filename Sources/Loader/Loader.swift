//
//  Loader.swift
//

import Foundation
import Combine

#if os(iOS)
import UIKit
#endif

@MainActor
public final class Loader: ObservableObject {
    
    @MainActor
    public final class Operation: Hashable, ObservableObject {
        
        public enum Presentation: Hashable, Sendable {
            
            public enum Fail: Hashable, Sendable {
                
                // cover screen with opaque fail view
                case opaque
                
                // shows alert preventing interaction with the screen
                case modal
                
                // shows error in toast
                case nonblocking
                
                // suppress fails
                case none
            }
            
            // cover screen with opaque loading view
            case opaque(Fail = .opaque)
            
            // fullscreen semitransparent overlay loading with alert error
            case modal(details: String = "", cancellable: Bool = true, fail: Fail = .modal)
            
            // shows loading bar at the top of the screen without blocking the content, error is shown as label at the top for couple of seconds
            case nonblocking(fail: Fail = .nonblocking)
            
            case custom(update: @MainActor @Sendable (_ isLoading: Bool)->(), fail: Fail = .modal)
            
            case none(fail: Fail = .none)
            
            public var id: String {
                switch self {
                case .opaque: return "opaque"
                case .modal(_, _, _): return "modal"
                case .nonblocking: return "nonblocking"
                case .custom(_, _): return "custom"
                case .none: return "none"
                }
            }
            
            public var fail: Fail {
                switch self {
                case .opaque(let fail),
                     .modal(_, _, let fail),
                     .nonblocking(let fail),
                     .custom(_, let fail),
                     .none(let fail):
                    return fail
                }
            }
            
            public static func == (lhs: Presentation, rhs: Presentation) -> Bool { lhs.id == rhs.id }
            
            public func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        
        public struct Fail: Sendable {
            public let id = UUID()
            public let error: Error
            public let presentation: Presentation
            public let retry: (@Sendable @MainActor ()->())?
            public let dismiss: @Sendable @MainActor ()->()
        }
        
        @Published public private(set) var progress: Double = 0
        public let presentation: Presentation
        
        fileprivate let id: String
        public fileprivate(set) var cancel: (()->())?
        
        #if os(iOS)
        private let backgroundTaskId: UIBackgroundTaskIdentifier?
        #endif
        
        @MainActor init(id: String, presentation: Presentation) {
            self.id = id
            self.presentation = presentation
            
            #if os(iOS)
            var endTask: (()->())?
            backgroundTaskId = UIApplication.shared.beginBackgroundTask { endTask?() }
            endTask = { [weak self] in self?.endTask() }
            
            #endif
        }
        
        #if os(iOS)
        private nonisolated func endTask() {
            if let task = backgroundTaskId {
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(task)
                }
            }
        }
        #endif
        
        fileprivate nonisolated func update(progress: Double) {
            Task { @MainActor in
                self.progress = progress
            }
        }
        
        public nonisolated func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        public nonisolated static func == (lhs: Loader.Operation, rhs: Loader.Operation) -> Bool { lhs.hashValue == rhs.hashValue }
        
        deinit {
            cancel?()
            #if os(iOS)
            endTask()
            #endif
        }
    }
    
    public nonisolated init() { }
    
    deinit {
        print("Loader deinit")
    }
    
    @Published public private(set) var processing: [String:Operation] = [:]
    @Published public private(set) var fails: [String:Operation.Fail] = [:]
    
    private var observers: [String:AnyCancellable] = [:]
    
    // don't handle Fail for such errors in the UI
    public static var suppressError: ((Error)->Bool)?
    
    public var supplyRetry: ((Error)->Bool)?
    public static var supplyRetry: ((Error)->Bool) = { _ in true }
    
    public static func isSuppressed(_ error: Error) -> Bool {
        (error as NSError).code == NSURLErrorCancelled ||
        error is CancellationError ||
        Self.suppressError?(error) == true
    }
    
    public func run(_ presentation: Operation.Presentation,
                    cancelOnExit: Bool = true,
                    id: String? = nil,
                    _ action: @escaping (_ progress: @Sendable @escaping (Double)->()) async throws -> ()) {
        
        let operation = create(id: id, presentation: presentation)
        
        let complete: (Error?)->() = { [weak self, weak operation] error in
            guard let wSelf = self, let operation,
                  wSelf.processing[operation.id] === operation else { return }
            
            if let error {
                let showsRetry = wSelf.supplyRetry?(error) ?? Self.supplyRetry(error)
                let retryBlock: @Sendable @MainActor ()->() = { self?.run(presentation, id: operation.id, action) }
                
                wSelf.fails[operation.id] = Operation.Fail(error: error,
                                                           presentation: presentation,
                                                           retry: showsRetry ? retryBlock : nil,
                                                           dismiss: { self?.fails[operation.id] = nil })
            }
            wSelf.complete(id: operation.id)
        }
        
        let task = Task { @MainActor [operation] in
            do {
                try await action { operation.update(progress: $0) }
                complete(nil)
            } catch {
                complete(error)
            }
        }
        
        operation.cancel = {
            if cancelOnExit { task.cancel() }
        }
        processing[operation.id] = operation
    }
    
    private func create(id: String?, presentation: Operation.Presentation) -> Operation {
        let id = id ?? UUID().uuidString
        let operation = Operation(id: id, presentation: presentation)
        if case .custom(let update, _) = presentation { update(true) }
        processing[id]?.cancel?()
        processing[id] = nil
        fails[id] = nil
        return operation
    }
    
    private func complete(id: String) {
        if let operation = processing[id] {
            if case .custom(let update, _) = operation.presentation { update(false) }
            processing[id] = nil
        }
    }
    
    public func cancelOperations() {
        processing.forEach { $0.value.cancel?() }
    }
    
    public func cancelOperation(_ id: String) {
        processing[id]?.cancel?()
    }
    
    public func removeObserving(id: String) {
        observers[id] = nil
    }
    
    public func observe<T>(_ loadable: Loadable<T>, _ presentation: @escaping (T?)->Operation.Presentation, id: String? = nil) {
        let id = id ?? UUID().uuidString
        
        observers[id] = loadable.$state.receive(on: DispatchQueue.main).sink { [weak self, weak loadable] value in
            guard let wSelf = self else { return }
            
            switch value {
            case .loading:
                wSelf.processing[id] = wSelf.create(id: id, presentation: presentation(loadable?.value))
            case .stop:
                wSelf.fails[id] = nil
                wSelf.complete(id: id)
            case .failed(let error, let retry):
                wSelf.fails[id] = Operation.Fail(error: error,
                                                 presentation: presentation(loadable?.value),
                                                 retry: retry,
                                                 dismiss: { self?.fails[id] = nil })
                wSelf.complete(id: id)
            }
        }
    }
}
