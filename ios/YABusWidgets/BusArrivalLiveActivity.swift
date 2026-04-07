import ActivityKit
import SwiftUI
import WidgetKit

struct BusArrivalLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BusArrivalAttributes.self) { context in
      lockScreenView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          expandedLeading(context: context)
        }
        DynamicIslandExpandedRegion(.trailing) {
          expandedTrailing(context: context)
        }
        DynamicIslandExpandedRegion(.bottom) {
          expandedBottom(context: context)
        }
      } compactLeading: {
        compactLeadingView(context: context)
      } compactTrailing: {
        compactTrailingView(context: context)
      } minimal: {
        minimalView(context: context)
      }
    }
  }

  @ViewBuilder
  private func compactLeadingView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "bus.fill")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.cyan)
      Text(context.attributes.routeName)
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }

  @ViewBuilder
  private func compactTrailingView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    countdownText(
      context.state,
      style: .compact,
      font: .system(size: 14, weight: .bold, design: .rounded)
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
  private func expandedLeading(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        routeBadge(context.attributes.routeName)
        Text(context.attributes.pathName)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if let modeLabel = trimmedText(context.state.modeLabel) {
        modePill(modeLabel)
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
      progressBar(context.state)

      HStack {
        if let statusText = trimmedText(context.state.statusText) {
          Text(statusText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Text(context.state.updatedAt, style: .time)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(Color(white: 0.5))
      }
    }
  }

  @ViewBuilder
  private func lockScreenView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          routeBadge(context.attributes.routeName)
          Text(context.attributes.pathName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        if let modeLabel = trimmedText(context.state.modeLabel) {
          modePill(modeLabel)
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

        progressBar(context.state)
          .padding(.top, 2)
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
  private func routeBadge(_ name: String) -> some View {
    Text(name)
      .font(.system(size: 14, weight: .heavy, design: .rounded))
      .foregroundStyle(.white)
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
  private func modePill(_ label: String) -> some View {
    Text(label)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white.opacity(0.92))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(Color.white.opacity(0.14))
      )
  }

  @ViewBuilder
  private func progressBar(_ state: BusArrivalAttributes.ContentState) -> some View {
    let progress = progressFraction(state)
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(Color(white: 0.2))
          .frame(height: 5)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(
            LinearGradient(
              colors: [etaColor(state), etaColor(state).opacity(0.6)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: geometry.size.width * progress, height: 5)
      }
    }
    .frame(height: 5)
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

  private func progressFraction(_ state: BusArrivalAttributes.ContentState) -> CGFloat {
    if let total = state.progressTotal, total > 0 {
      let value = min(max(state.progressValue ?? 0, 0), total)
      return CGFloat(Double(value) / Double(total))
    }
    return etaProgress(state)
  }

  private func etaProgress(_ state: BusArrivalAttributes.ContentState) -> CGFloat {
    guard let sec = state.etaSeconds else {
      return 0
    }
    if sec <= 0 {
      return 1.0
    }
    let maxSeconds: Double = 600
    return min(CGFloat(1.0 - Double(sec) / maxSeconds), 1.0)
  }
}

private enum CountdownStyle {
  case compact
  case minimal
  case expanded
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
