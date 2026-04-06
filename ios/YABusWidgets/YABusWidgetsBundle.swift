import SwiftUI
import WidgetKit

@main
struct YABusWidgetsBundle: WidgetBundle {
  var body: some Widget {
    FavoriteGroupWidget()
    BusArrivalLiveActivity()
  }
}
