//
//  DailyWatchWidgetExtensionBundle.swift
//  DailyWatchWidgetExtension
//
//  Created by Mihai Ionescu on 25.02.2026.
//

import WidgetKit
import SwiftUI

@main
struct DailyWatchWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        DailyWatchWidgetExtension()
        DailyWatchWidgetExtensionControl()
    }
}
