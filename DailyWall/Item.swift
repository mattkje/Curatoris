//
//  Item.swift
//  DailyWall
//
//  Created by Matti Kjellstadli on 06/03/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
