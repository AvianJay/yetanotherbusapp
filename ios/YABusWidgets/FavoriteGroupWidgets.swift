import AppIntents
import Compression
import Foundation
import SwiftUI
import WidgetKit

enum FavoriteWidgetSharedStore {
  static let appGroupIdentifier = "group.tw.avianjay.taiwanbus.flutter"
  static let favoriteGroupsKey = "favorite_groups_json"

  static func loadFavoriteGroups() -> [String: [FavoriteWidgetStop]] {
    guard
      let payload = loadFavoriteGroupsPayload()
    else {
      return [:]
    }

    return payload.reduce(into: [String: [FavoriteWidgetStop]]()) { result, entry in
      let groupName = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !groupName.isEmpty else {
        return
      }

      guard let rawStops = entry.value as? [Any] else {
        result[groupName] = []
        return
      }

      result[groupName] = rawStops.compactMap { rawStop in
        guard let stopMap = rawStop as? [String: Any] else {
          return nil
        }

        let provider = (stopMap["provider"] as? String ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let routeKey = integerValue(from: stopMap["routeKey"])
        let pathId = integerValue(from: stopMap["pathId"])
        let stopId = integerValue(from: stopMap["stopId"])
        guard !provider.isEmpty, routeKey > 0, pathId >= 0, stopId >= 0 else {
          return nil
        }

        return FavoriteWidgetStop(
          provider: provider,
          routeKey: routeKey,
          pathId: pathId,
          stopId: stopId,
          routeName: (stopMap["routeName"] as? String)?.nilIfBlank,
          stopName: (stopMap["stopName"] as? String)?.nilIfBlank
        )
      }
    }
  }

  static func loadFavoriteGroupNames() -> [String] {
    guard let payload = loadFavoriteGroupsPayload() else {
      return []
    }

    return payload.keys
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted()
  }

  private static func loadFavoriteGroupsPayload() -> [String: Any]? {
    guard
      let defaults = UserDefaults(suiteName: appGroupIdentifier),
      let raw = defaults.string(forKey: favoriteGroupsKey),
      let data = raw.data(using: .utf8)
    else {
      return nil
    }

    do {
      return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    } catch {
      return nil
    }
  }

  private static func integerValue(from value: Any?) -> Int {
    switch value {
    case let number as NSNumber:
      return number.intValue
    case let number as Int:
      return number
    case let text as String:
      return Int(text) ?? 0
    default:
      return 0
    }
  }
}

struct FavoriteWidgetStop: Decodable, Hashable {
  let provider: String
  let routeKey: Int
  let pathId: Int
  let stopId: Int
  let routeName: String?
  let stopName: String?
}

struct FavoriteWidgetItem: Identifiable, Hashable {
  let id: String
  let routeName: String
  let stopName: String
  let etaText: String
  let noteText: String
  let routeURL: URL?
}

struct FavoriteGroupEntry: TimelineEntry {
  let date: Date
  let groupName: String
  let items: [FavoriteWidgetItem]
  let statusMessage: String?
  let lastUpdated: Date?
  let groupURL: URL?
}

private struct FavoriteWidgetLiveStop: Hashable {
  let sec: Int?
  let msg: String?
  let vehicleId: String?
}

struct FavoriteGroupEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "\u{6211}\u{7684}\u{6700}\u{611b}\u{7fa4}\u{7d44}"
  )
  static let defaultQuery = FavoriteGroupQuery()

  let id: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(id)")
  }
}

struct FavoriteGroupQuery: EntityQuery {
  func entities(
    for identifiers: [FavoriteGroupEntity.ID]
  ) async throws -> [FavoriteGroupEntity] {
    let availableNames = Set(FavoriteWidgetSharedStore.loadFavoriteGroupNames())
    return identifiers.compactMap { identifier in
      guard availableNames.contains(identifier) else {
        return nil
      }
      return FavoriteGroupEntity(id: identifier)
    }
  }

  func suggestedEntities() async throws -> [FavoriteGroupEntity] {
    FavoriteWidgetSharedStore.loadFavoriteGroupNames().map { name in
      FavoriteGroupEntity(id: name)
    }
  }

  func defaultResult() async -> FavoriteGroupEntity? {
    FavoriteWidgetSharedStore.loadFavoriteGroupNames().first.map { name in
      FavoriteGroupEntity(id: name)
    }
  }
}

extension FavoriteGroupQuery: EntityStringQuery {
  func entities(matching string: String) async throws -> [FavoriteGroupEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let names = FavoriteWidgetSharedStore.loadFavoriteGroupNames()
    let filteredNames: [String]
    if query.isEmpty {
      filteredNames = names
    } else {
      filteredNames = names.filter { name in
        name.lowercased().contains(query)
      }
    }
    return filteredNames.map { name in
      FavoriteGroupEntity(id: name)
    }
  }
}

struct FavoriteGroupConfigurationIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource =
    "\u{6211}\u{7684}\u{6700}\u{611b}\u{7fa4}\u{7d44}"
  static var description = IntentDescription(
    "\u{986f}\u{793a}\u{55ae}\u{4e00}\u{6700}\u{611b}\u{7fa4}\u{7d44}\u{7684}\u{5230}\u{7ad9}\u{6642}\u{9593}\u{3002}"
  )

  @Parameter(title: "\u{7fa4}\u{7d44}")
  var group: FavoriteGroupEntity?
}

struct FavoriteGroupTimelineProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> FavoriteGroupEntry {
    FavoriteGroupEntry(
      date: .now,
      groupName: "我的最愛",
      items: [
        FavoriteWidgetItem(
          id: "sample-1",
          routeName: "307",
          stopName: "臺北車站",
          etaText: "3分",
          noteText: "YABus",
          routeURL: nil
        ),
        FavoriteWidgetItem(
          id: "sample-2",
          routeName: "綠3",
          stopName: "中山醫學大學",
          etaText: "8分",
          noteText: "YABus",
          routeURL: nil
        ),
      ],
      statusMessage: nil,
      lastUpdated: .now,
      groupURL: nil
    )
  }

  func snapshot(
    for configuration: FavoriteGroupConfigurationIntent,
    in context: Context
  ) async -> FavoriteGroupEntry {
    await FavoriteGroupEntryLoader.load(configuration: configuration)
  }

  func timeline(
    for configuration: FavoriteGroupConfigurationIntent,
    in context: Context
  ) async -> Timeline<FavoriteGroupEntry> {
    let entry = await FavoriteGroupEntryLoader.load(configuration: configuration)
    let refreshMinutes = entry.items.isEmpty ? 15 : 5
    let nextRefresh =
      Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date())
      ?? Date().addingTimeInterval(Double(refreshMinutes) * 60)
    return Timeline(entries: [entry], policy: .after(nextRefresh))
  }
}

private enum FavoriteGroupEntryLoader {
  static func load(configuration: FavoriteGroupConfigurationIntent) async -> FavoriteGroupEntry {
    let groups = FavoriteWidgetSharedStore.loadFavoriteGroups()
    guard !groups.isEmpty else {
      return FavoriteGroupEntry(
        date: .now,
        groupName: "我的最愛",
        items: [],
        statusMessage: "請先在 App 內加入我的最愛。",
        lastUpdated: nil,
        groupURL: nil
      )
    }

    let sortedNames = groups.keys.sorted()
    let requestedName = configuration.group?.id
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedName = requestedName.flatMap { groups[$0] == nil ? nil : $0 } ?? sortedNames[0]

    let favorites = groups[selectedName] ?? []
    guard !favorites.isEmpty else {
      return FavoriteGroupEntry(
        date: .now,
        groupName: selectedName,
        items: [],
        statusMessage: "這個群組目前還沒有儲存站牌。",
        lastUpdated: nil,
        groupURL: FavoriteWidgetDeepLink.group(named: selectedName)
      )
    }

    let fetchResult = await FavoriteWidgetRouteFetcher.loadItems(for: favorites)
    return FavoriteGroupEntry(
      date: .now,
      groupName: selectedName,
      items: fetchResult.items,
      statusMessage: fetchResult.didFetchLiveData ? nil : "目前無法更新。",
      lastUpdated: fetchResult.didFetchLiveData ? Date() : nil,
      groupURL: FavoriteWidgetDeepLink.group(named: selectedName)
    )
  }
}

private enum FavoriteWidgetRouteFetcher {
  static func loadItems(
    for favorites: [FavoriteWidgetStop]
  ) async -> (items: [FavoriteWidgetItem], didFetchLiveData: Bool) {
    var liveStopsByRoute = [String: [Int: FavoriteWidgetLiveStop]]()
    var successfulFetchCount = 0
    let uniqueRoutes = Dictionary(
      favorites.map { (routeRequestKey(for: $0), $0) },
      uniquingKeysWith: { left, _ in left }
    )

    await withTaskGroup(of: (String, [Int: FavoriteWidgetLiveStop], Bool).self) { group in
      for (requestKey, favorite) in uniqueRoutes {
        group.addTask {
          let result = await fetchLiveStops(routeKey: favorite.routeKey)
          return (requestKey, result.liveStops, result.success)
        }
      }

      for await (requestKey, liveStops, success) in group {
        liveStopsByRoute[requestKey] = liveStops
        if success {
          successfulFetchCount += 1
        }
      }
    }

    let items = favorites.map { favorite in
      let liveStop = liveStopsByRoute[routeRequestKey(for: favorite)]?[favorite.stopId]
      return FavoriteWidgetItem(
        id: "\(favorite.provider):\(favorite.routeKey):\(favorite.pathId):\(favorite.stopId)",
        routeName: favorite.routeName?.nilIfBlank ?? "路線 \(favorite.routeKey)",
        stopName: favorite.stopName?.nilIfBlank ?? "站牌 \(favorite.stopId)",
        etaText: formatETA(liveStop),
        noteText: liveStop?.vehicleId?.nilIfBlank ?? favorite.provider.uppercased(),
        routeURL: FavoriteWidgetDeepLink.route(
          provider: favorite.provider,
          routeKey: favorite.routeKey,
          pathId: favorite.pathId,
          stopId: favorite.stopId
        )
      )
    }

    return (items, successfulFetchCount > 0)
  }

  private static func fetchLiveStops(
    routeKey: Int
  ) async -> (success: Bool, liveStops: [Int: FavoriteWidgetLiveStop]) {
    guard let url = URL(string: "https://busserver.bus.yahoo.com/api/route/\(routeKey)") else {
      return (false, [:])
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.cachePolicy = .reloadIgnoringLocalCacheData

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        return (false, [:])
      }

      guard let xmlData = decodeXMLData(data) else {
        return (false, [:])
      }

      return (true, RouteLiveStopXMLParser.parse(xmlData))
    } catch {
      return (false, [:])
    }
  }

  private static func decodeXMLData(_ data: Data) -> Data? {
    if looksLikeXML(data) {
      return data
    }

    if let inflated = decompressZlib(data), looksLikeXML(inflated) {
      return inflated
    }

    if
      let text = String(data: data, encoding: .utf8),
      text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
    {
      return Data(text.utf8)
    }

    return nil
  }

  private static func looksLikeXML(_ data: Data) -> Bool {
    guard let text = String(data: Data(data.prefix(32)), encoding: .utf8) else {
      return false
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
  }

  private static func decompressZlib(_ data: Data) -> Data? {
    if data.isEmpty {
      return data
    }

    let bufferSize = 64 * 1024
    var output = Data()
    var dummyDestinationByte: UInt8 = 0
    var dummySourceByte: UInt8 = 0

    return withUnsafeMutablePointer(to: &dummyDestinationByte) { dummyDstPtr in
      withUnsafePointer(to: &dummySourceByte) { dummySrcPtr in
        var stream = compression_stream(
          dst_ptr: dummyDstPtr,
          dst_size: 0,
          src_ptr: dummySrcPtr,
          src_size: 0,
          state: nil
        )
        let status = compression_stream_init(
          &stream,
          COMPRESSION_STREAM_DECODE,
          COMPRESSION_ZLIB
        )
        guard status != COMPRESSION_STATUS_ERROR else {
          return nil
        }
        defer {
          compression_stream_destroy(&stream)
        }

        return data.withUnsafeBytes { sourceBuffer -> Data? in
          guard let sourceBaseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return nil
          }

          let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
          defer {
            destinationBuffer.deallocate()
          }

          stream.src_ptr = sourceBaseAddress
          stream.src_size = data.count

          while true {
            stream.dst_ptr = destinationBuffer
            stream.dst_size = bufferSize

            let processStatus = compression_stream_process(
              &stream,
              Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            )
            let writtenBytes = bufferSize - stream.dst_size
            if writtenBytes > 0 {
              output.append(destinationBuffer, count: writtenBytes)
            }

            switch processStatus {
            case COMPRESSION_STATUS_OK:
              continue
            case COMPRESSION_STATUS_END:
              return output
            default:
              return nil
            }
          }
        }
      }
    }
  }

  private static func routeRequestKey(for favorite: FavoriteWidgetStop) -> String {
    "\(favorite.provider):\(favorite.routeKey)"
  }

  private static func formatETA(_ liveStop: FavoriteWidgetLiveStop?) -> String {
    guard let liveStop else {
      return "--"
    }

    if let message = liveStop.msg?.nilIfBlank {
      return message
    }

    guard let seconds = liveStop.sec else {
      return "--"
    }
    if seconds <= 0 {
      return "進站中"
    }
    if seconds < 60 {
      return "1分內"
    }
    return "\(seconds / 60)分"
  }
}

private final class RouteLiveStopXMLParser: NSObject, XMLParserDelegate {
  private var currentStopID: Int?
  private var liveStops = [Int: FavoriteWidgetLiveStop]()

  static func parse(_ data: Data) -> [Int: FavoriteWidgetLiveStop] {
    let delegate = RouteLiveStopXMLParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.parse()
    return delegate.liveStops
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    if elementName == "e" {
      guard let stopID = Int(attributeDict["id"] ?? "") else {
        currentStopID = nil
        return
      }

      currentStopID = stopID
      liveStops[stopID] = FavoriteWidgetLiveStop(
        sec: Int(attributeDict["sec"] ?? ""),
        msg: attributeDict["msg"]?.nilIfBlank,
        vehicleId: nil
      )
      return
    }

    if elementName == "b", let currentStopID {
      let vehicleID = attributeDict["id"]?.nilIfBlank
      if let existing = liveStops[currentStopID] {
        liveStops[currentStopID] = FavoriteWidgetLiveStop(
          sec: existing.sec,
          msg: existing.msg,
          vehicleId: existing.vehicleId ?? vehicleID
        )
      }
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if elementName == "e" {
      currentStopID = nil
    }
  }
}

private enum FavoriteWidgetDeepLink {
  static func group(named groupName: String) -> URL? {
    var components = URLComponents()
    components.scheme = "yabus"
    components.host = "favorites"
    components.queryItems = [URLQueryItem(name: "groupName", value: groupName)]
    return components.url
  }

  static func route(
    provider: String,
    routeKey: Int,
    pathId: Int,
    stopId: Int
  ) -> URL? {
    var components = URLComponents()
    components.scheme = "yabus"
    components.host = "route"
    components.queryItems = [
      URLQueryItem(name: "provider", value: provider),
      URLQueryItem(name: "routeKey", value: String(routeKey)),
      URLQueryItem(name: "pathId", value: String(pathId)),
      URLQueryItem(name: "stopId", value: String(stopId)),
    ]
    return components.url
  }
}

struct FavoriteGroupWidget: Widget {
  private let kind = "FavoriteGroupWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: FavoriteGroupConfigurationIntent.self,
      provider: FavoriteGroupTimelineProvider()
    ) { entry in
      FavoriteGroupWidgetView(entry: entry)
    }
    .configurationDisplayName("我的最愛站牌")
    .description("在主畫面或鎖定畫面查看最愛站牌的到站時間。")
    .supportedFamilies([
      .systemSmall,
      .systemMedium,
      .systemLarge,
      .accessoryInline,
      .accessoryRectangular,
    ])
  }
}

private struct FavoriteGroupWidgetView: View {
  @Environment(\.widgetFamily) private var family

  let entry: FavoriteGroupEntry

  @ViewBuilder
  var body: some View {
    switch family {
    case .accessoryInline:
      inlineView
    case .accessoryRectangular:
      rectangularView
    default:
      systemWidgetView
    }
  }

  private var systemWidgetView: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.groupName)
            .font(.headline)
            .lineLimit(1)
          if let statusMessage = entry.statusMessage {
            Text(statusMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 8)

        if let lastUpdated = entry.lastUpdated {
          Text(lastUpdated, style: .time)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      if entry.items.isEmpty {
        Spacer(minLength: 0)
        Text(entry.statusMessage ?? "沒有資料")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(entry.items.prefix(maxVisibleItems))) { item in
            if let routeURL = item.routeURL {
              Link(destination: routeURL) {
                rowView(for: item)
              }
              .buttonStyle(.plain)
            } else {
              rowView(for: item)
            }
          }
        }
      }
    }
    .widgetURL(entry.groupURL)
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [
          Color(red: 0.08, green: 0.11, blue: 0.17),
          Color(red: 0.13, green: 0.17, blue: 0.24),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }

  private var rectangularView: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.groupName)
        .font(.caption)
        .fontWeight(.semibold)
        .lineLimit(1)

      if let firstItem = entry.items.first {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(firstItem.routeName)
              .font(.caption)
              .fontWeight(.semibold)
              .lineLimit(1)
            Text(firstItem.stopName)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          Text(firstItem.etaText)
            .font(.headline)
            .fontWeight(.bold)
            .lineLimit(1)
        }
      } else {
        Text(entry.statusMessage ?? "沒有資料")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      if let lastUpdated = entry.lastUpdated {
        Text(lastUpdated, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .widgetURL(entry.groupURL)
  }

  private var inlineView: some View {
    let text: String = {
      guard let firstItem = entry.items.first else {
        return "YABus"
      }
      return "\(firstItem.routeName) \(firstItem.etaText)"
    }()

    return Text(text)
      .widgetURL(entry.groupURL)
  }

  private var maxVisibleItems: Int {
    switch family {
    case .systemSmall:
      return 2
    case .systemLarge:
      return 6
    default:
      return 4
    }
  }

  @ViewBuilder
  private func rowView(for item: FavoriteWidgetItem) -> some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.routeName)
          .font(.subheadline)
          .fontWeight(.semibold)
          .lineLimit(1)
        Text(item.stopName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        Text(item.etaText)
          .font(.headline)
          .fontWeight(.bold)
          .lineLimit(1)
        Text(item.noteText)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
