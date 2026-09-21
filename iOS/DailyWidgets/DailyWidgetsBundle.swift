import WidgetKit
import SwiftUI

@main
struct DailyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CombinedWidget()
        BubblesWidget()
        SmokesWidget()
        MoneyWidget()
        SleepWidget()
        TagdosWidget()
        StressWidget()
    }
}
