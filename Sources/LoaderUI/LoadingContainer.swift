//
//  LoadingContainer.swift
//

import SwiftUI
import Combine
@_exported import Loader

#if os(iOS)

public struct Customization {
    fileprivate let loadingView: (Loader.Operation) -> AnyView
    fileprivate let loadingBar: (Loader.Operation) -> AnyView
    fileprivate let failView: (Loader.Operation.Fail) -> AnyView
    fileprivate let failBar: (Loader.Operation.Fail) -> AnyView
    
    public init(loadingView: @escaping (Loader.Operation) -> AnyView = { AnyView(LoadingView(operation: $0)) },
                loadingBar: @escaping (Loader.Operation) -> AnyView = { AnyView(LoadingBar(operation: $0)) },
                failView: @escaping (Loader.Operation.Fail) -> AnyView = { AnyView(FailView(fail: $0)) },
                failBar: @escaping (Loader.Operation.Fail) -> AnyView = { AnyView(FailToast(fail: $0)) }) {
        self.loadingView = loadingView
        self.loadingBar = loadingBar
        self.failView = failView
        self.failBar = failBar
    }
}

private struct LoadingContainerModifier: ViewModifier {
    
    let loaders: [Loader]
    @State private var operations: [Loader.Operation.Presentation : Loader.Operation] = [:]
    @State private var fails: [Loader.Operation.Presentation.Fail : Loader.Operation.Fail] = [:]
    
    private let customization: Customization
    
    init(_ loaders: [Loader], customization: Customization) {
        self.loaders = loaders
        self.customization = customization
    }
    
    private func reload() {
        var operations: [Loader.Operation.Presentation : Loader.Operation] = [:]
        loaders.flatMap { $0.processing.values }.forEach {
            operations[$0.presentation] = $0
        }
        
        var fails: [Loader.Operation.Presentation.Fail : Loader.Operation.Fail] = [:]
        
        loaders.flatMap { $0.fails.values.filter { $0.presentation.fail != .none && !Loader.isSuppressed($0.error) } }.forEach {
            fails[$0.presentation.fail] = $0
        }
        
        if operations[.opaque()] == nil {
            withAnimation(.easeOut) {
                self.operations = operations
                self.fails = fails
            }
        } else {
            self.operations = operations
            self.fails = fails
        }
    }
    
    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if let fail = fails[.opaque] {
                    customization.failView(fail)
                }
                if let operation = operations[.nonblocking()] {
                    customization.loadingBar(operation)
                }
                if let fail = fails[.nonblocking] {
                    customization.failBar(fail)
                }
                if let operation = operations[.opaque()] {
                    customization.loadingView(operation)
                }
                if let operation = operations[.modal()] {
                    customization.loadingView(operation)
                }
            }
        }
        .alert(isPresented: Binding(get: {
            fails[.modal] != nil
        }, set: { _ in
            fails[.modal]?.dismiss()
            fails[.modal] = nil
        }),
               error: fails[.modal]?.error.asLocalizedError,
               actions: {
            Button("OK", action: { })
            if let retry = fails[.modal]?.retry {
                Button("Retry", action: retry)
            }
        })
        .onReceive(Publishers.MergeMany(loaders.map { $0.objectWillChange })) { _ in
            DispatchQueue.main.async { reload() }
        }
        .onAppear { reload() }
    }
}

public struct LoadingContainer<Content: View>: View {
    
    private let loaders: [Loader]
    private let customization: Customization
    private let content: ()->Content
    
    public init(_ loaders: [Loader],
                customization: Customization = .init(),
                @ViewBuilder content: @escaping ()->Content) {
        self.loaders = loaders
        self.content = content
        self.customization = customization
    }
    
    public init(_ loader: Loader,
                customization: Customization = .init(),
                @ViewBuilder content: @escaping ()->Content) {
        loaders = [loader]
        self.content = content
        self.customization = customization
    }
    
    public var body: some View {
        content().withLoading(loaders, customization: customization)
    }
}

public extension View {
    
    func withLoading(_ loader: Loader, customization: Customization = .init()) -> some View {
        withLoading([loader], customization: customization)
    }
    
    func withLoading(_ loaders: [Loader], customization: Customization = .init()) -> some View {
        modifier(LoadingContainerModifier(loaders, customization: customization))
    }
}

#endif

private struct ConvertedLocalizedError: LocalizedError {
    
    let error: Error
    
    var errorDescription: String? { error.localizedDescription }
}

private extension Error {
    
    var asLocalizedError: ConvertedLocalizedError { ConvertedLocalizedError(error: self) }
}
