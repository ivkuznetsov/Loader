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
    
    public final class Operation: Hashable, ObservableObject {
        
        public enum Presentation: Hashable {
            
            public enum Fail: Hashable {
                
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
            
            case none(fail: Fail = .none)
            
            public var id: String {
                switch self {
                case .opaque: return "opaque"
                case .modal(_, _, _): return "modal"
                case .nonblocking: return "nonblocking"
                case .none: return "none"
                }
            }
            
            public var fail: Fail {
                switch self {
                case .opaque(let fail),
                     .modal(_, _, let fail),
                     .nonblocking(let fail),
                     .none(let fail):
                    return fail
                }
            }
            
            public static func == (lhs: Presentation, rhs: Presentation) -> Bool { lhs.id == rhs.id }
            
            public func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        
        public struct Fail {
            public let id = UUID()
            public let error: Error
            public let presentation: Presentation
            public let retry: (()->())?
            public let dismiss: ()->()
        }
        
        @Published public private(set) var progress: Double = 0
        public let presentation: Presentation
        
        fileprivate let id: String
        public fileprivate(set) var cancel: (()->())!
        
        #if os(iOS)
        private var backgroundTaskId: UIBackgroundTaskIdentifier?
        #endif
        
        @MainActor init(id: String, presentation: Presentation) {
            self.id = id
            self.presentation = presentation
            
            #if os(iOS)
            backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endTask()
            }
            #endif
        }
        
        #if os(iOS)
        private func endTask() {
            if let task = backgroundTaskId {
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(task)
                }
            }
        }
        #endif
        
        fileprivate func update(progress: Double) {
            Task { @MainActor [weak self] in
                self?.progress = progress
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        public static func == (lhs: Loader.Operation, rhs: Loader.Operation) -> Bool { lhs.hashValue == rhs.hashValue }
        
        deinit {
            cancel()
            #if os(iOS)
            endTask()
            #endif
        }
    }
    
    public nonisolated init() {}
    
    @Published public private(set) var processing: [String:Operation] = [:]
    @Published public private(set) var fails: [String:Operation.Fail] = [:]
    
    // don't handle Fail for such errors in the UI
    public static var suppressError: ((Error)->Bool)?
    
    public static func isSuppressed(_ error: Error) -> Bool {
        (error as NSError).code == NSURLErrorCancelled ||
        error is CancellationError ||
        Self.suppressError?(error) == true
    }
    
    public func run(_ presentation: Operation.Presentation,
                    id: String? = nil,
                    _ action: @escaping (_ progress: @escaping (Double)->()) async throws -> ()) {
        
        let id = id ?? UUID().uuidString
        let operation = Operation(id: id, presentation: presentation)
        
        processing[id]?.cancel()
        processing[id] = nil
        fails[id] = nil
        
        let task = Task.detached { [weak self, weak operation] in
            do {
                try await action { operation?.update(progress: $0) }
            } catch {
                Task { @MainActor [weak self, weak operation] in
                    if let operation = operation,
                       let wSelf = self,
                       wSelf.processing[id] === operation {
                        
                        wSelf.fails[id] = Operation.Fail(error: error,
                                                         presentation: presentation,
                                                         retry: { self?.run(presentation, id: id, action) },
                                                         dismiss: { self?.fails[id] = nil })
                    }
                }
            }
            
            Task { @MainActor [weak self, weak operation] in
                if let wSelf = self,
                   let operation = operation,
                   wSelf.processing[id] === operation {
                    wSelf.processing[id] = nil
                }
            }
        }
        operation.cancel = { task.cancel() }
        processing[id] = operation
    }
    
    public func cancelOperations() {
        processing.forEach { $0.value.cancel() }
    }
    
    public func cancelOperation(_ id: String) {
        processing[id]?.cancel()
    }
}