import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testBusArrivalAttributesEncoding() throws {
    let attributes = BusArrivalAttributes(
      routeName: "307",
      pathName: "往板橋",
      stopName: "臺北車站",
      routeKey: 307,
      provider: "twn",
      pathId: 0,
      stopId: 100
    )

    XCTAssertEqual(attributes.routeName, "307")
    XCTAssertEqual(attributes.pathName, "往板橋")
    XCTAssertEqual(attributes.stopName, "臺北車站")
    XCTAssertEqual(attributes.routeKey, 307)
    XCTAssertEqual(attributes.provider, "twn")
    XCTAssertEqual(attributes.pathId, 0)
    XCTAssertEqual(attributes.stopId, 100)
  }

  func testContentStateRoundTrip() throws {
    let state = BusArrivalAttributes.ContentState(
      etaSeconds: 125,
      etaMessage: nil,
      vehicleId: "EAL-5957",
      nextStopName: "西門町",
      updatedAt: Date(timeIntervalSince1970: 1700000000)
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(state)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(BusArrivalAttributes.ContentState.self, from: data)

    XCTAssertEqual(decoded.etaSeconds, 125)
    XCTAssertNil(decoded.etaMessage)
    XCTAssertEqual(decoded.vehicleId, "EAL-5957")
    XCTAssertEqual(decoded.nextStopName, "西門町")
    XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 1700000000))
  }

  func testContentStateWithMessage() throws {
    let state = BusArrivalAttributes.ContentState(
      etaSeconds: nil,
      etaMessage: "即將進站",
      vehicleId: nil,
      nextStopName: nil,
      updatedAt: Date()
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(state)
    let decoded = try JSONDecoder().decode(BusArrivalAttributes.ContentState.self, from: data)

    XCTAssertNil(decoded.etaSeconds)
    XCTAssertEqual(decoded.etaMessage, "即將進站")
    XCTAssertNil(decoded.vehicleId)
    XCTAssertNil(decoded.nextStopName)
  }

  func testContentStateHashable() {
    let state1 = BusArrivalAttributes.ContentState(
      etaSeconds: 60,
      etaMessage: nil,
      vehicleId: "ABC-1234",
      nextStopName: "站A",
      updatedAt: Date(timeIntervalSince1970: 1700000000)
    )

    let state2 = BusArrivalAttributes.ContentState(
      etaSeconds: 60,
      etaMessage: nil,
      vehicleId: "ABC-1234",
      nextStopName: "站A",
      updatedAt: Date(timeIntervalSince1970: 1700000000)
    )

    XCTAssertEqual(state1, state2)
    XCTAssertEqual(state1.hashValue, state2.hashValue)
  }

  func testLiveActivityBridgeSingleton() {
    let bridge1 = LiveActivityBridge.shared
    let bridge2 = LiveActivityBridge.shared
    XCTAssertTrue(bridge1 === bridge2)
  }
}
