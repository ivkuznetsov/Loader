//
//  PagingContainerState.swift
//  
//
//  Created by Ilya Kuznetsov on 22/08/2023.
//

import Foundation
import Combine
import Loader
import SwiftUI

@MainActor
final class PagingContainerState: ObservableObject {
    
    var paging: (any ObservablePagingLoader)? {
        didSet {
            observer = paging?.loadingState.$state.sink { [weak self] value in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let wSelf = self, value == .stop, wSelf.isLoadingVisible {
                        wSelf.paging?.loadMore()
                    }
                }
            }
        }
    }
    private var observer: AnyCancellable?
    
    var contentCache: Any?
    
    var containerFrame: CGRect = .zero
    var isLoadingVisible: Bool = false {
        didSet {
            if isLoadingVisible && !oldValue {
                paging?.loadMore()
            }
        }
    }
    var refreshing: AnyCancellable?
    var oldItemsCount: Int = 0
    
    func retry() {
        paging?.loadMore(userInitiated: true)
    }
}
