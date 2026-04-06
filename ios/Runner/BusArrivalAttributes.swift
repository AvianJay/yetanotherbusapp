import ActivityKit
import Foundation

struct BusArrivalAttributes: ActivityAttributes {
  let routeName: String
  let pathName: String
  let routeKey: Int
  let provider: String
  let pathId: Int

  struct ContentState: Codable, Hashable {
    let displayStopId: Int
    let displayStopName: String
    let modeLabel: String?
    let statusText: String?
    let etaSeconds: Int?
    let etaMessage: String?
    let vehicleId: String?
    let progressValue: Int?
    let progressTotal: Int?
    let updatedAt: Date
  }
}
