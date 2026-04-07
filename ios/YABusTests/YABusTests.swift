import Flutter
import UIKit
import XCTest

@testable import YABus

class YABusTests: XCTestCase {

  func testExample() {
    // If you add code to the YABus application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testBusArrivalAttributesEncoding() throws {
    let attributes = BusArrivalAttributes(
      routeName: "307",
      pathName: "往板橋",
      routeKey: 307,
      provider: "twn",
      pathId: 0
    )

    XCTAssertEqual(attributes.routeName, "307")
    XCTAssertEqual(attributes.pathName, "往板橋")
    XCTAssertEqual(attributes.routeKey, 307)
    XCTAssertEqual(attributes.provider, "twn")
    XCTAssertEqual(attributes.pathId, 0)
  }

  func testContentStateRoundTrip() throws {
    let state = BusArrivalAttributes.ContentState(
      displayStopId: 100,
      displayStopName: "臺北車站",
      previousStopName: "善導寺",
      nextStopName: "西門町",
      lineStopNames: ["善導寺", "臺北車站", "西門町"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 2,
      modeLabel: "尚未上車",
      statusText: "往板橋 · 上車站 臺北車站",
      etaSeconds: 125,
      etaMessage: nil,
      vehicleId: "EAL-5957",
      progressValue: 1,
      progressTotal: 5,
      updatedAt: Date(timeIntervalSince1970: 1700000000)
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(state)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(BusArrivalAttributes.ContentState.self, from: data)

    XCTAssertEqual(decoded.displayStopId, 100)
    XCTAssertEqual(decoded.displayStopName, "臺北車站")
    XCTAssertEqual(decoded.previousStopName, "善導寺")
    XCTAssertEqual(decoded.nextStopName, "西門町")
    XCTAssertEqual(decoded.lineStopNames, ["善導寺", "臺北車站", "西門町"])
    XCTAssertEqual(decoded.lineCurrentStopIndex, 1)
    XCTAssertEqual(decoded.lineHighlightedStopIndex, 2)
    XCTAssertEqual(decoded.modeLabel, "尚未上車")
    XCTAssertEqual(decoded.statusText, "往板橋 · 上車站 臺北車站")
    XCTAssertEqual(decoded.etaSeconds, 125)
    XCTAssertNil(decoded.etaMessage)
    XCTAssertEqual(decoded.vehicleId, "EAL-5957")
    XCTAssertEqual(decoded.progressValue, 1)
    XCTAssertEqual(decoded.progressTotal, 5)
    XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 1700000000))
  }

  func testContentStateWithMessage() throws {
    let state = BusArrivalAttributes.ContentState(
      displayStopId: 101,
      displayStopName: "西門町",
      previousStopName: "臺北車站",
      nextStopName: "龍山寺",
      lineStopNames: ["臺北車站", "西門町", "龍山寺"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 1,
      modeLabel: nil,
      statusText: "最近站牌 西門町",
      etaSeconds: nil,
      etaMessage: "即將進站",
      vehicleId: nil,
      progressValue: nil,
      progressTotal: nil,
      updatedAt: Date()
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(state)
    let decoded = try JSONDecoder().decode(BusArrivalAttributes.ContentState.self, from: data)

    XCTAssertEqual(decoded.displayStopId, 101)
    XCTAssertEqual(decoded.displayStopName, "西門町")
    XCTAssertEqual(decoded.previousStopName, "臺北車站")
    XCTAssertEqual(decoded.nextStopName, "龍山寺")
    XCTAssertEqual(decoded.lineStopNames, ["臺北車站", "西門町", "龍山寺"])
    XCTAssertEqual(decoded.lineCurrentStopIndex, 1)
    XCTAssertEqual(decoded.lineHighlightedStopIndex, 1)
    XCTAssertEqual(decoded.statusText, "最近站牌 西門町")
    XCTAssertNil(decoded.etaSeconds)
    XCTAssertEqual(decoded.etaMessage, "即將進站")
    XCTAssertNil(decoded.vehicleId)
    XCTAssertNil(decoded.progressValue)
    XCTAssertNil(decoded.progressTotal)
  }

  func testContentStateHashable() {
    let state1 = BusArrivalAttributes.ContentState(
      displayStopId: 102,
      displayStopName: "龍山寺",
      previousStopName: "西門町",
      nextStopName: "江子翠",
      lineStopNames: ["西門町", "龍山寺", "江子翠"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 2,
      modeLabel: "已上車",
      statusText: "已上車 · 最近站牌 西門町",
      etaSeconds: 60,
      etaMessage: nil,
      vehicleId: "ABC-1234",
      progressValue: 3,
      progressTotal: 7,
      updatedAt: Date(timeIntervalSince1970: 1700000000)
    )

    let state2 = BusArrivalAttributes.ContentState(
      displayStopId: 102,
      displayStopName: "龍山寺",
      previousStopName: "西門町",
      nextStopName: "江子翠",
      lineStopNames: ["西門町", "龍山寺", "江子翠"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 2,
      modeLabel: "已上車",
      statusText: "已上車 · 最近站牌 西門町",
      etaSeconds: 60,
      etaMessage: nil,
      vehicleId: "ABC-1234",
      progressValue: 3,
      progressTotal: 7,
      updatedAt: Date(timeIntervalSince1970: 1700000000)
    )

    XCTAssertEqual(state1, state2)
    XCTAssertEqual(state1.hashValue, state2.hashValue)
  }

  func testEtaTimerIntervalUsesUpdatedAtAndEtaSeconds() {
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let state = BusArrivalAttributes.ContentState(
      displayStopId: 102,
      displayStopName: "龍山寺",
      previousStopName: "西門町",
      nextStopName: "江子翠",
      lineStopNames: ["西門町", "龍山寺", "江子翠"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 2,
      modeLabel: "已上車",
      statusText: "已上車 · 最近站牌 西門町",
      etaSeconds: 125,
      etaMessage: nil,
      vehicleId: "ABC-1234",
      progressValue: 3,
      progressTotal: 7,
      updatedAt: updatedAt
    )

    XCTAssertEqual(state.etaTimerInterval?.lowerBound, updatedAt)
    XCTAssertEqual(
      state.etaTimerInterval?.upperBound,
      updatedAt.addingTimeInterval(125)
    )
    XCTAssertFalse(state.etaShowsHours)
  }

  func testEtaTimerIntervalIsDisabledWhenMessageIsPresent() {
    let state = BusArrivalAttributes.ContentState(
      displayStopId: 101,
      displayStopName: "西門町",
      previousStopName: "臺北車站",
      nextStopName: "龍山寺",
      lineStopNames: ["臺北車站", "西門町", "龍山寺"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 1,
      modeLabel: nil,
      statusText: "最近站牌 西門町",
      etaSeconds: 45,
      etaMessage: "即將進站",
      vehicleId: nil,
      progressValue: nil,
      progressTotal: nil,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertTrue(state.hasEtaMessage)
    XCTAssertNil(state.etaTimerInterval)
  }

  func testEtaShowsHoursForLongCountdowns() {
    let state = BusArrivalAttributes.ContentState(
      displayStopId: 103,
      displayStopName: "板橋公車站",
      previousStopName: "江子翠",
      nextStopName: "新埔",
      lineStopNames: ["江子翠", "板橋公車站", "新埔"],
      lineCurrentStopIndex: 1,
      lineHighlightedStopIndex: 2,
      modeLabel: "尚未上車",
      statusText: "公車還有 8 站",
      etaSeconds: 3_900,
      etaMessage: nil,
      vehicleId: nil,
      progressValue: 1,
      progressTotal: 10,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertTrue(state.etaShowsHours)
  }

  func testLiveActivityBridgeSingleton() {
    let bridge1 = LiveActivityBridge.shared
    let bridge2 = LiveActivityBridge.shared
    XCTAssertTrue(bridge1 === bridge2)
  }
}
