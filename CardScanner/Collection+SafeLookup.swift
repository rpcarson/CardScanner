//
//  Collection+SafeLookup.swift
//  CardScanner
//
//  Created by Reed Carson on 5/18/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import Foundation

extension Collection {
    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
