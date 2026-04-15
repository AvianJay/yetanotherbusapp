import ActivityKit
import SwiftUI
import WidgetKit

struct BusArrivalLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BusArrivalAttributes.self) { context in
      lockScreenView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          expandedHeader(context: context)
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        DynamicIslandExpandedRegion(.bottom) {
          expandedBottom(context: context)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
      } compactLeading: {
        compactLeadingView(context: context)
      } compactTrailing: {
        compactTrailingView(context: context)
      } minimal: {
        minimalView(context: context)
      }
      .keylineTint(etaColor(context.state))
    }
  }

  @ViewBuilder
  private func compactLeadingView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    Text(compactRouteName(context.attributes.routeName))
      .font(.system(size: 13, weight: .heavy, design: .rounded))
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(etaColor(context.state).opacity(0.9))
      )
  }

  @ViewBuilder
  private func compactTrailingView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    countdownText(
      context.state,
      style: .compact,
      font: .system(size: 15, weight: .bold, design: .rounded)
    )
    .foregroundStyle(etaColor(context.state))
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .monospacedDigit()
  }

  @ViewBuilder
  private func minimalView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    ZStack {
      Circle()
        .fill(etaColor(context.state).opacity(0.25))
      countdownText(
        context.state,
        style: .minimal,
        font: .system(size: 11, weight: .heavy, design: .rounded)
      )
      .foregroundStyle(etaColor(context.state))
      .minimumScaleFactor(0.5)
      .monospacedDigit()
    }
  }

  @ViewBuilder
  private func expandedHeader(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      expandedLeading(context: context)
        .frame(maxWidth: .infinity, alignment: .leading)

      expandedTrailing(context: context)
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  @ViewBuilder
  private func expandedLeading(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        routeBadge(context.attributes.routeName, surface: .dynamicIsland)
        Text(context.attributes.pathName)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if let modeLabel = trimmedText(context.state.modeLabel) {
        modePill(modeLabel, surface: .dynamicIsland)
      }

      HStack(spacing: 5) {
        Image(systemName: "mappin.circle.fill")
          .font(.system(size: 14))
          .foregroundStyle(.cyan)
        Text(displayStopName(context.state))
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
      }

      if let statusText = trimmedText(context.state.statusText) {
        Text(statusText)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
  }

  @ViewBuilder
  private func expandedTrailing(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      countdownText(
        context.state,
        style: .expanded,
        font: .system(size: 28, weight: .bold, design: .rounded)
      )
      .foregroundStyle(etaColor(context.state))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .monospacedDigit()

      if let vehicleId = trimmedText(context.state.vehicleId) {
        HStack(spacing: 3) {
          Image(systemName: "bus")
            .font(.system(size: 10))
          Text(vehicleId)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func expandedBottom(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(spacing: 8) {
      stopLineView(context.state, surface: .dynamicIsland)

      HStack {
        if let statusText = trimmedText(context.state.statusText) {
          Text(statusText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer()
        Text(context.state.updatedAt, style: .time)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(Color(white: 0.5))
      }
      .padding(.horizontal, 2)
    }
  }

  @ViewBuilder
  private func lockScreenView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          routeBadge(context.attributes.routeName, surface: .lockScreen)
          Text(context.attributes.pathName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        if let modeLabel = trimmedText(context.state.modeLabel) {
          modePill(modeLabel, surface: .lockScreen)
        }

        HStack(spacing: 5) {
          Image(systemName: "mappin.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(.cyan)
          Text(displayStopName(context.state))
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)
        }

        if let statusText = trimmedText(context.state.statusText) {
          Text(statusText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        stopLineView(context.state, surface: .lockScreen)
          .padding(.top, 4)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 4) {
        countdownText(
          context.state,
          style: .expanded,
          font: .system(size: 32, weight: .bold, design: .rounded)
        )
        .foregroundStyle(etaColor(context.state))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .monospacedDigit()

        if let vehicleId = trimmedText(context.state.vehicleId) {
          HStack(spacing: 3) {
            Image(systemName: "bus")
              .font(.system(size: 10))
            Text(vehicleId)
              .font(.system(size: 11, weight: .medium, design: .monospaced))
          }
          .foregroundStyle(.secondary)
        }

        Text(context.state.updatedAt, style: .time)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(Color(white: 0.5))
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .widgetURL(
      BusArrivalDeepLink.route(
        provider: context.attributes.provider,
        routeKey: context.attributes.routeKey,
        pathId: context.attributes.pathId,
        stopId: context.state.displayStopId
      )
    )
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

  @ViewBuilder
  private func routeBadge(
    _ name: String,
    surface: ActivitySurface
  ) -> some View {
    Text(name)
      .font(.system(size: 14, weight: .heavy, design: .rounded))
      .foregroundStyle(routeBadgeTextColor(surface: surface))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(red: 0.0, green: 0.7, blue: 0.8), Color(red: 0.0, green: 0.55, blue: 0.75)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
  }

  @ViewBuilder
  private func modePill(_ label: String, surface: ActivitySurface) -> some View {
    Text(label)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(modePillTextColor(surface: surface))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(modePillBackgroundColor(surface: surface))
      )
  }

  @ViewBuilder
  private func stopLineView(
    _ state: BusArrivalAttributes.ContentState,
    surface: ActivitySurface
  ) -> some View {
    if let stopLine = stopLineData(state) {
      VStack(spacing: 6) {
        HStack(spacing: 0) {
          ForEach(stopLine.stopNames.indices, id: \.self) { index in
            stopMarker(
              isCurrent: index == stopLine.currentStopIndex,
              isHighlighted: index == stopLine.highlightedStopIndex,
              surface: surface
            )
            .frame(width: 18)

            if index < stopLine.stopNames.count - 1 {
              stopConnector(
                intensity: stopConnectorOpacity(
                  currentStopIndex: stopLine.currentStopIndex,
                  connectorIndex: index
                ),
                surface: surface
              )
            }
          }
        }

        HStack(alignment: .top, spacing: 6) {
          ForEach(stopLine.stopNames.indices, id: \.self) { index in
            stopLineLabel(
              stopLine.stopNames[index],
              isCurrent: index == stopLine.currentStopIndex,
              isHighlighted: index == stopLine.highlightedStopIndex,
              surface: surface
            )
          }
        }
      }
    } else {
      let previousStopName = trimmedText(state.previousStopName)
      let nextStopName = trimmedText(state.nextStopName)
      let currentStopName = displayStopName(state)

      if previousStopName == nil && nextStopName == nil {
        HStack {
          Spacer(minLength: 0)
          stopLineLabel(
            currentStopName,
            isCurrent: true,
            isHighlighted: true,
            surface: surface
          )
          Spacer(minLength: 0)
        }
      } else {
        VStack(spacing: 6) {
          HStack(spacing: 0) {
            stopMarker(isCurrent: false, isHighlighted: false, surface: surface)
              .frame(width: 18)
            stopConnector(intensity: 0.4, surface: surface)
            stopMarker(isCurrent: true, isHighlighted: true, surface: surface)
              .frame(width: 18)
            stopConnector(intensity: 0.22, surface: surface)
            stopMarker(isCurrent: false, isHighlighted: false, surface: surface)
              .frame(width: 18)
          }

          HStack(alignment: .center, spacing: 8) {
            stopLineLabel(
              previousStopName ?? "起點",
              isCurrent: false,
              isHighlighted: false,
              surface: surface
            )
            stopLineLabel(
              currentStopName,
              isCurrent: true,
              isHighlighted: true,
              surface: surface
            )
            stopLineLabel(
              nextStopName ?? "終點",
              isCurrent: false,
              isHighlighted: false,
              surface: surface
            )
          }
        }
      }
    }
  }

  @ViewBuilder
  private func stopMarker(
    isCurrent: Bool,
    isHighlighted: Bool,
    surface: ActivitySurface
  ) -> some View {
    if isCurrent {
      ZStack {
        if isHighlighted {
          Circle()
            .stroke(stopMarkerRingColor(surface: surface), lineWidth: 2)
            .frame(width: 20, height: 20)
        }
        Circle()
          .fill(Color(red: 0.0, green: 0.74, blue: 0.83))
          .frame(width: 16, height: 16)
        Image(systemName: "bus.fill")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.white)
      }
    } else if isHighlighted {
      Circle()
        .strokeBorder(Color(red: 0.0, green: 0.74, blue: 0.83), lineWidth: 2)
        .background(
          Circle()
            .fill(Color(red: 0.0, green: 0.74, blue: 0.83).opacity(0.18))
        )
        .frame(width: 12, height: 12)
    } else {
      Circle()
        .fill(stopMarkerColor(surface: surface))
        .frame(width: 8, height: 8)
    }
  }

  @ViewBuilder
  private func stopConnector(intensity: Double, surface: ActivitySurface) -> some View {
    Capsule(style: .continuous)
      .fill(stopConnectorColor(surface: surface, intensity: intensity))
      .frame(maxWidth: .infinity)
      .frame(height: 2)
      .padding(.horizontal, 4)
  }

  @ViewBuilder
  private func stopLineLabel(
    _ text: String,
    isCurrent: Bool,
    isHighlighted: Bool,
    surface: ActivitySurface
  ) -> some View {
    Text(compactStopLineLabel(text))
      .font(
        .system(
          size: isCurrent ? 10.5 : 9.5,
          weight: isCurrent || isHighlighted ? .semibold : .medium
        )
      )
      .foregroundStyle(
        stopLineLabelColor(
          isCurrent: isCurrent,
          isHighlighted: isHighlighted,
          surface: surface
        )
      )
      .lineLimit(2)
      .minimumScaleFactor(0.7)
      .lineSpacing(-1)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
  }

  private func stopLineData(
    _ state: BusArrivalAttributes.ContentState
  ) -> StopLineData? {
    guard !state.lineStopNames.isEmpty else {
      return nil
    }

    let currentStopIndex = normalizedStopLineIndex(
      state.lineCurrentStopIndex,
      count: state.lineStopNames.count
    ) ?? 0
    let highlightedStopIndex = normalizedStopLineIndex(
      state.lineHighlightedStopIndex,
      count: state.lineStopNames.count
    )

    return StopLineData(
      stopNames: state.lineStopNames,
      currentStopIndex: currentStopIndex,
      highlightedStopIndex: highlightedStopIndex
    )
  }

  private func normalizedStopLineIndex(
    _ index: Int?,
    count: Int
  ) -> Int? {
    guard let index, count > 0, index >= 0, index < count else {
      return nil
    }
    return index
  }

  private func stopConnectorOpacity(
    currentStopIndex: Int,
    connectorIndex: Int
  ) -> Double {
    return connectorIndex < currentStopIndex ? 0.46 : 0.18
  }

  private func stopLineLabelColor(
    isCurrent: Bool,
    isHighlighted: Bool,
    surface: ActivitySurface
  ) -> Color {
    if surface == .dynamicIsland {
      if isCurrent {
        return .primary
      }
      if isHighlighted {
        return Color(red: 0.0, green: 0.5, blue: 0.62)
      }
      return .secondary
    }

    if isCurrent {
      return .white
    }
    if isHighlighted {
      return Color(red: 0.55, green: 0.9, blue: 0.98)
    }
    return Color.white.opacity(0.68)
  }

  private func compactStopLineLabel(_ text: String) -> String {
    let trimmed = trimmedText(text) ?? text
    let separators = ["(", "（", " ", "/", "／", "-", "－"]
    var candidate = trimmed
    for separator in separators {
      if let range = candidate.range(of: separator) {
        candidate = String(candidate[..<range.lowerBound])
        break
      }
    }

    if candidate.count <= 4 {
      return candidate
    }

    return String(candidate.prefix(4)) + "…"
  }

  private func trimmedText(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func displayStopName(_ state: BusArrivalAttributes.ContentState) -> String {
    trimmedText(state.displayStopName) ?? "背景乘車提醒"
  }

  private func compactRouteName(_ text: String) -> String {
    let trimmed = trimmedText(text) ?? text
    if trimmed.count <= 4 {
      return trimmed
    }
    return String(trimmed.prefix(4))
  }

  private func routeBadgeTextColor(surface: ActivitySurface) -> Color {
    if surface == .dynamicIsland {
      return .primary
    }
    return .white
  }

  private func modePillTextColor(surface: ActivitySurface) -> Color {
    if surface == .dynamicIsland {
      return .primary
    }
    return .white.opacity(0.92)
  }

  private func modePillBackgroundColor(surface: ActivitySurface) -> Color {
    if surface == .dynamicIsland {
      return .secondary.opacity(0.18)
    }
    return Color.white.opacity(0.14)
  }

  private func stopMarkerRingColor(surface: ActivitySurface) -> Color {
    if surface == .dynamicIsland {
      return .primary.opacity(0.32)
    }
    return Color.white.opacity(0.75)
  }

  private func stopMarkerColor(surface: ActivitySurface) -> Color {
    if surface == .dynamicIsland {
      return .secondary.opacity(0.45)
    }
    return Color.white.opacity(0.38)
  }

  private func stopConnectorColor(surface: ActivitySurface, intensity: Double) -> Color {
    if surface == .dynamicIsland {
      return .primary.opacity(max(intensity * 0.55, 0.1))
    }
    return Color.white.opacity(intensity)
  }

  @ViewBuilder
  private func countdownText(
    _ state: BusArrivalAttributes.ContentState,
    style: CountdownStyle,
    font: Font
  ) -> some View {
    if let text = etaFallbackText(state, style: style) {
      Text(text)
        .font(font)
    } else if let timerInterval = state.etaTimerInterval {
      Text(
        timerInterval: timerInterval,
        pauseTime: nil,
        countsDown: true,
        showsHours: state.etaShowsHours
      )
      .font(font)
    } else {
      Text("--")
        .font(font)
    }
  }

  private func etaFallbackText(
    _ state: BusArrivalAttributes.ContentState,
    style: CountdownStyle
  ) -> String? {
    if let msg = trimmedText(state.etaMessage) {
      switch style {
      case .minimal:
        return String(msg.prefix(2))
      case .compact:
        return msg.count > 4 ? String(msg.prefix(4)) : msg
      case .expanded:
        return msg
      }
    }
    guard let sec = state.etaSeconds else {
      return nil
    }
    if sec <= 0 {
      switch style {
      case .minimal:
        return "到"
      case .compact:
        return "進站"
      case .expanded:
        return "進站中"
      }
    }

    return nil
  }

  private func etaColor(_ state: BusArrivalAttributes.ContentState) -> Color {
    if trimmedText(state.etaMessage) != nil {
      return Color(red: 0.0, green: 0.7, blue: 0.65)
    }
    guard let sec = state.etaSeconds else {
      return Color(white: 0.5)
    }
    if sec <= 0 {
      return Color(red: 0.9, green: 0.22, blue: 0.21)
    }
    if sec < 60 {
      return Color(red: 0.9, green: 0.3, blue: 0.25)
    }
    if sec < 180 {
      return Color(red: 0.94, green: 0.42, blue: 0.0)
    }
    return Color(red: 0.0, green: 0.74, blue: 0.83)
  }

}

private enum ActivitySurface {
  case dynamicIsland
  case lockScreen
}

private enum CountdownStyle {
  case compact
  case minimal
  case expanded
}

private struct StopLineData {
  let stopNames: [String]
  let currentStopIndex: Int
  let highlightedStopIndex: Int?
}

private enum BusArrivalDeepLink {
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
