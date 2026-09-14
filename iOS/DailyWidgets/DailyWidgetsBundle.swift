import WidgetKit
import SwiftUI

@main
struct DailyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubblesWidget()
        SmokesWidget()
        MoneyWidget()
    }
}
