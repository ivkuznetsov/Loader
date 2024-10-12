//
//  Loadable.swift
//  

import Foundation
import Combine

public typealias LoadingState = Loadable<Void>

@MainActor
public final class Loadable<T>: ObservableObject {
    
    public enum State: Equatable {
        case stop
        case loading
        case failed(Error, retry: (()->())? = nil)
        
        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.stop, .stop): return true
            case (.loading, .loading): return true
            case (.failed(let error1, _), .failed(let error2, _)): return error1.localizedDescription == error2.localizedDescription
            default: return false
            }
        }
    }
    
    @Published public var state: State = .stop
    @Published public var value: T?
    
    public nonisolated init() { }
    
    public init(value: T) {
        self.value = value
    }
    
    private var task: (id: UUID, task: Task<T?, Error>)?
    
    public func cancelLoading() {
        task?.task.cancel()
        task = nil
    }
    
    private func update(_ state: State, id: UUID) {
        if task?.id == id, self.state != state {
            self.state = state
        }
    }
    
    @discardableResult
    public func load(_ closure: @escaping () async throws ->T?) async throws -> T? {
        cancelLoading()
        let id = UUID()
        task = (id, Task {
            update(.loading, id: id)
            do {
                let result = try await closure()
                value = result
                update(.stop, id: id)
                return result
            } catch {
                update(.failed(error, retry: { [weak self] in
                    Task { try await self?.load(closure) }
                }), id: id)
                throw error
            }
        })
        return try await task?.task.value
    }
    
    deinit {
        task?.task.cancel()
    }
}
