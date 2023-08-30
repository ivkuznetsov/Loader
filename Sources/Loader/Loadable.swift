//
//  Loadable.swift
//  

import Foundation

public typealias LoadingState = Loadable<Void>

public extension LoadingState.State {
    
    static var stop: LoadingState.State { .ready(nil) }
}

public final class Loadable<T>: ObservableObject {
    
    public enum State: Equatable {
        case ready(T?)
        case loading
        case failed(Error, retry: (()->())? = nil)
        
        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.ready(let value1), .ready(let value2)):
                if let value1 = value1 as? AnyHashable, let value2 = value2 as? AnyHashable {
                    return value1 == value2
                }
                return true
            case (.loading, .loading): return true
            case (.failed(let error1, _), .failed(let error2, _)): return error1.localizedDescription == error2.localizedDescription
            default: return false
            }
        }
    }
    
    @Published public private(set) var state: State = .ready(nil)
    
    @MainActor
    public func update(_ state: State) {
        if self.state != state {
            self.state = state
        }
    }
    
    @MainActor
    public var value: T? {
        get {
            if case .ready(let t) = state {
                return t
            }
            return nil
        }
        set {
            update(.ready(newValue))
        }
    }
    
    public init() { }
    
    private var task: Task<Void, Error>?
    
    public func cancelLoading() {
        task?.cancel()
        task = nil
    }
    
    public func load(_ closure: @escaping () async throws ->T?) {
        task = Task {
            await update(.loading)
            do {
                await update(.ready(try await closure()))
            } catch {
                await update(.failed(error, retry: { [weak self] in
                    self?.load(closure)
                }))
            }
        }
    }
}
