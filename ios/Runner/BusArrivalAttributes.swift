import ActivityKit
import Foundation

struct BusArrivalAttributes: ActivityAttributes {
  let routeName: String
  let pathName: String
  let stopName: String
  let routeKey: Int
  let provider: String
  let pathId: Int
  let stopId: Int

  struct ContentState: Codable, Hashable {
    let etaSeconds: Int?
    let etaMessage: String?
    let vehicleId: String?
    let nextStopName: String?
    let updatedAt: Date
  }
}
