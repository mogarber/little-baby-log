import SwiftUI
import WidgetKit

@main
struct LittleBabyLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        FeedingWidget()
        SleepWidget()
        QuickLogWidget()
        LockScreenWidget()
        TimerLiveActivityWidget()
    }
}
