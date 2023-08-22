//
//  LoadingContainer.swift
//

import SwiftUI
import Combine
import Loader

#if os(iOS)

public struct LoadingContainer<Content: View>: View {
    
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
    
    @State private var loaders: [Loader]
    @State private var operations: [Loader.Operation.Presentation : Loader.Operation] = [:]
    @State private var fails: [Loader.Operation.Presentation.Fail : Loader.Operation.Fail] = [:]
    
    private let content: Content
    private let customization: Customization
    
    public init(_ loaders: [Loader],
                customization: Customization = .init(),
                content: ()->Content) {
        self._loaders = .init(wrappedValue: loaders)
        self.content = content()
        self.customization = customization
    }
    
    public init(_ loader: Loader,
                customization: Customization = .init(),
                content: ()->Content) {
        self._loaders = .init(wrappedValue: [loader])
        self.content = content()
        self.customization = customization
    }
    
    @MainActor
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
    
    public var body: some View {
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
        }.alert(isPresented: Binding(get: { fails[.modal] != nil  }, set: { _ in fails[.modal]?.dismiss() }),
                error: fails[.modal]?.error.asLocalizedError,
                actions: {
            Button("OK", action: { })
            if let retry = fails[.modal]?.retry {
                Button("Retry", action: retry)
            }
        }).onReceive(Publishers.MergeMany(loaders.map { $0.objectWillChange }), perform: { _ in
            DispatchQueue.main.async {
                reload()
            }
        }).onAppear {
            reload()
        }.environmentObject(loaders[0])
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
