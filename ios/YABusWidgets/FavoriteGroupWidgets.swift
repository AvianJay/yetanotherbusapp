import AppIntents
import Foundation
import SwiftUI
import WidgetKit

enum FavoriteWidgetSharedStore {
  static let appGroupIdentifier = "group.tw.avianjay.taiwanbus.flutter"
  static let favoriteGroupsKey = "favorite_groups_json"
  static let favoriteGroupsFileName = "favorite_groups.json"

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
        let destinationStopId = optionalIntegerValue(from: stopMap["destinationStopId"])
        let destinationPathId = destinationStopId == nil
          ? nil
          : (optionalIntegerValue(from: stopMap["destinationPathId"]) ?? pathId)
        guard !provider.isEmpty, routeKey > 0, pathId >= 0, stopId >= 0 else {
          return nil
        }

        return FavoriteWidgetStop(
          provider: provider,
          routeKey: routeKey,
          pathId: pathId,
          stopId: stopId,
          routeId: (stopMap["routeId"] as? String)?.nilIfBlank,
          routeName: (stopMap["routeName"] as? String)?.nilIfBlank,
          stopName: (stopMap["stopName"] as? String)?.nilIfBlank,
          destinationPathId: destinationPathId,
          destinationStopId: destinationStopId,
          destinationStopName: (stopMap["destinationStopName"] as? String)?.nilIfBlank
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
    let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )
    if let containerURL {
      let fileURL = containerURL.appendingPathComponent(favoriteGroupsFileName)
      let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
      if
        fileExists,
        let data = try? Data(contentsOf: fileURL)
      {
        if
          let object = try? JSONSerialization.jsonObject(with: data),
          let payload = object as? [String: Any]
        {
          NSLog(
            "FavoriteWidgetSharedStore loaded payload from shared file. groups=%d, bytes=%d",
            payload.count,
            data.count
          )
          return payload
        } else {
          NSLog(
            "FavoriteWidgetSharedStore failed to parse shared file JSON. bytes=%d",
            data.count
          )
        }
      } else {
        NSLog(
          "FavoriteWidgetSharedStore shared file missing. exists=%@",
          fileExists ? "true" : "false"
        )
      }
    } else {
      NSLog(
        "FavoriteWidgetSharedStore container URL nil for %@",
        appGroupIdentifier
      )
    }

    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
      NSLog(
        "FavoriteWidgetSharedStore UserDefaults suite nil for %@",
        appGroupIdentifier
      )
      return nil
    }
    guard
      let raw = defaults.string(forKey: favoriteGroupsKey),
      let data = raw.data(using: .utf8)
    else {
      NSLog(
        "FavoriteWidgetSharedStore UserDefaults missing key %@",
        favoriteGroupsKey
      )
      return nil
    }

    do {
      let object = try JSONSerialization.jsonObject(with: data)
      if let payload = object as? [String: Any] {
        NSLog(
          "FavoriteWidgetSharedStore loaded payload from UserDefaults. groups=%d",
          payload.count
        )
        return payload
      }
      NSLog("FavoriteWidgetSharedStore UserDefaults JSON not top-level dict.")
      return nil
    } catch {
      NSLog(
        "FavoriteWidgetSharedStore UserDefaults JSON parse error: %@",
        error.localizedDescription
      )
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

  private static func optionalIntegerValue(from value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
      return number.intValue
    case let number as Int:
      return number
    case let text as String:
      return Int(text)
    default:
      return nil
    }
  }
}

struct FavoriteWidgetStop: Decodable, Hashable {
  let provider: String
  let routeKey: Int
  let pathId: Int
  let stopId: Int
  let routeId: String?
  let routeName: String?
  let stopName: String?
  let destinationPathId: Int?
  let destinationStopId: Int?
  let destinationStopName: String?
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

private extension FavoriteWidgetSharedStore {
  static func loadFavoriteGroupEntities() -> [FavoriteGroupEntity] {
    loadFavoriteGroupNames().map { name in
      FavoriteGroupEntity(id: name)
    }
  }
}

struct FavoriteGroupQuery: EntityQuery, EnumerableEntityQuery {
  func allEntities() async throws -> [FavoriteGroupEntity] {
    let entities = FavoriteWidgetSharedStore.loadFavoriteGroupEntities()
    NSLog("FavoriteGroupQuery.allEntities returned %d", entities.count)
    return entities
  }

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
    let entities = FavoriteWidgetSharedStore.loadFavoriteGroupEntities()
    NSLog("FavoriteGroupQuery.suggestedEntities returned %d", entities.count)
    return entities
  }

  func defaultResult() async -> FavoriteGroupEntity? {
    FavoriteWidgetSharedStore.loadFavoriteGroupEntities().first
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
          let result = await fetchLiveStops(favorite: favorite)
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
          stopId: favorite.stopId,
          destinationPathId: favorite.destinationPathId,
          destinationStopId: favorite.destinationStopId
        )
      )
    }

    return (items, successfulFetchCount > 0)
  }

  private static func fetchLiveStops(
    favorite: FavoriteWidgetStop
  ) async -> (success: Bool, liveStops: [Int: FavoriteWidgetLiveStop]) {
    guard let routeID = favorite.routeId?.nilIfBlank else {
      return (false, [:])
    }

    guard
      let encodedRouteID = routeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
      let url = URL(string: "https://bus.avianjay.sbs/api/v1/routes/\(encodedRouteID)/realtime")
    else {
      return (false, [:])
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Mozilla/5.0 (YABus iOS Widget)", forHTTPHeaderField: "User-Agent")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        return (false, [:])
      }

      guard
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let liveStops = parseLiveStops(
          from: object,
          preferredPathID: favorite.pathId
        )
      else {
        return (false, [:])
      }

      return (true, liveStops)
    } catch {
      return (false, [:])
    }
  }

  private static func parseLiveStops(
    from root: [String: Any],
    preferredPathID: Int
  ) -> [Int: FavoriteWidgetLiveStop]? {
    guard let rawPaths = root["paths"] as? [Any] else {
      return nil
    }
    let pathObjects = rawPaths.compactMap { $0 as? [String: Any] }
    var result = [Int: FavoriteWidgetLiveStop]()

    func appendPath(_ pathObject: [String: Any]) {
      guard let rawStops = pathObject["stops"] as? [Any] else {
        return
      }
      for rawStop in rawStops {
        guard let stopObject = rawStop as? [String: Any] else {
          continue
        }
        let stopID = parseStopID(stopObject["stopid"])
        guard stopID > 0 else {
          continue
        }
        let message = (stopObject["message"] as? String)?.nilIfBlank
        let sec = intValue(from: stopObject["eta"])
        let vehicleID = firstVehicleID(from: stopObject["buses"] as? [Any])
        result[stopID] = FavoriteWidgetLiveStop(
          sec: sec,
          msg: message,
          vehicleId: vehicleID
        )
      }
    }

    var matchedPath = false
    for pathObject in pathObjects {
      if intValue(from: pathObject["pathid"]) == preferredPathID {
        matchedPath = true
        appendPath(pathObject)
      }
    }

    if !matchedPath {
      for pathObject in pathObjects {
        appendPath(pathObject)
      }
    }

    return result
  }

  private static func parseStopID(_ value: Any?) -> Int {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let number = value as? Int {
      return number
    }
    let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let parsed = Int(text) {
      return parsed
    }
    var hash = 17
    for scalar in text.unicodeScalars {
      hash = (hash * 31 + Int(scalar.value)) & 0x7fffffff
    }
    return hash
  }

  private static func intValue(from value: Any?) -> Int? {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let number = value as? Int {
      return number
    }
    if let text = value as? String {
      return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
  }

  private static func firstVehicleID(from buses: [Any]?) -> String? {
    guard let buses else {
      return nil
    }
    for rawBus in buses {
      guard let bus = rawBus as? [String: Any] else {
        continue
      }
      if let id = (bus["id"] as? String)?.nilIfBlank {
        return id
      }
      if let id = (bus["vehicle_id"] as? String)?.nilIfBlank {
        return id
      }
      if let id = (bus["plate"] as? String)?.nilIfBlank {
        return id
      }
    }
    return nil
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
    stopId: Int,
    destinationPathId: Int?,
    destinationStopId: Int?
  ) -> URL? {
    var components = URLComponents()
    components.scheme = "yabus"
    components.host = "route"
    var queryItems = [
      URLQueryItem(name: "provider", value: provider),
      URLQueryItem(name: "routeKey", value: String(routeKey)),
      URLQueryItem(name: "pathId", value: String(pathId)),
      URLQueryItem(name: "stopId", value: String(stopId)),
    ]
    if let destinationPathId {
      queryItems.append(
        URLQueryItem(name: "destinationPathId", value: String(destinationPathId))
      )
    }
    if let destinationStopId {
      queryItems.append(
        URLQueryItem(name: "destinationStopId", value: String(destinationStopId))
      )
    }
    components.queryItems = queryItems
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
