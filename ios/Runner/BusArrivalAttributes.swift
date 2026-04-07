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

extension BusArrivalAttributes.ContentState {
  var hasEtaMessage: Bool {
    guard let etaMessage else {
      return false
    }
    return !etaMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var etaTimerInterval: ClosedRange<Date>? {
    guard !hasEtaMessage, let etaSeconds, etaSeconds > 0 else {
      return nil
    }

    return updatedAt...updatedAt.addingTimeInterval(TimeInterval(etaSeconds))
  }

  var etaShowsHours: Bool {
    guard let etaSeconds else {
      return false
    }
    return etaSeconds >= 3600
  }
}
