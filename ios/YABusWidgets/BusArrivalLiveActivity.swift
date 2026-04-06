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

  // MARK: - Compact Leading

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

  // MARK: - Compact Trailing

  @ViewBuilder
  private func compactTrailingView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    Text(formatETACompact(context.state))
      .font(.system(size: 14, weight: .bold, design: .rounded))
      .foregroundStyle(etaColor(context.state))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
  }

  // MARK: - Minimal

  @ViewBuilder
  private func minimalView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    ZStack {
      Circle()
        .fill(etaColor(context.state).opacity(0.25))
      Text(formatETAMinimal(context.state))
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(etaColor(context.state))
        .minimumScaleFactor(0.5)
    }
  }

  // MARK: - Expanded

  @ViewBuilder
  private func expandedLeading(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        routeBadge(context.attributes.routeName)
        Text(context.attributes.pathName)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      HStack(spacing: 5) {
        Image(systemName: "mappin.circle.fill")
          .font(.system(size: 14))
          .foregroundStyle(.cyan)
        Text(context.attributes.stopName)
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private func expandedTrailing(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(formatETAExpanded(context.state))
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundStyle(etaColor(context.state))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      if let vehicleId = context.state.vehicleId,
        !vehicleId.trimmingCharacters(in: .whitespaces).isEmpty
      {
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
      etaProgressBar(context.state)

      HStack {
        if let nextStop = context.state.nextStopName,
          !nextStop.trimmingCharacters(in: .whitespaces).isEmpty
        {
          HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
            Text("下一站 \(nextStop)")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer()
        Text(context.state.updatedAt, style: .time)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(Color(white: 0.5))
      }
    }
  }

  // MARK: - Lock Screen Banner

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

        HStack(spacing: 5) {
          Image(systemName: "mappin.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(.cyan)
          Text(context.attributes.stopName)
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)
        }

        if let nextStop = context.state.nextStopName,
          !nextStop.trimmingCharacters(in: .whitespaces).isEmpty
        {
          HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle")
              .font(.system(size: 11))
            Text("下一站 \(nextStop)")
              .font(.system(size: 12, weight: .medium))
              .lineLimit(1)
          }
          .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 4) {
        Text(formatETAExpanded(context.state))
          .font(.system(size: 32, weight: .bold, design: .rounded))
          .foregroundStyle(etaColor(context.state))
          .lineLimit(1)
          .minimumScaleFactor(0.5)

        if let vehicleId = context.state.vehicleId,
          !vehicleId.trimmingCharacters(in: .whitespaces).isEmpty
        {
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
        stopId: context.attributes.stopId
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

  // MARK: - Subviews

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
  private func etaProgressBar(_ state: BusArrivalAttributes.ContentState) -> some View {
    let progress = etaProgress(state)
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

  // MARK: - Formatting

  private func formatETACompact(_ state: BusArrivalAttributes.ContentState) -> String {
    if let msg = state.etaMessage?.trimmingCharacters(in: .whitespaces), !msg.isEmpty {
      if msg.count > 4 {
        return String(msg.prefix(4))
      }
      return msg
    }
    guard let sec = state.etaSeconds else {
      return "--"
    }
    if sec <= 0 {
      return "進站"
    }
    if sec < 60 {
      return "\(sec)秒"
    }
    return "\(sec / 60)分"
  }

  private func formatETAMinimal(_ state: BusArrivalAttributes.ContentState) -> String {
    if let msg = state.etaMessage?.trimmingCharacters(in: .whitespaces), !msg.isEmpty {
      return String(msg.prefix(2))
    }
    guard let sec = state.etaSeconds else {
      return "--"
    }
    if sec <= 0 {
      return "到"
    }
    if sec < 60 {
      return "\(sec)s"
    }
    return "\(sec / 60)m"
  }

  private func formatETAExpanded(_ state: BusArrivalAttributes.ContentState) -> String {
    if let msg = state.etaMessage?.trimmingCharacters(in: .whitespaces), !msg.isEmpty {
      return msg
    }
    guard let sec = state.etaSeconds else {
      return "--"
    }
    if sec <= 0 {
      return "進站中"
    }
    if sec < 60 {
      return "\(sec)秒"
    }
    let minutes = sec / 60
    let remainder = sec % 60
    if remainder == 0 {
      return "\(minutes)分"
    }
    return "\(minutes):\(String(format: "%02d", remainder))"
  }

  private func etaColor(_ state: BusArrivalAttributes.ContentState) -> Color {
    if let msg = state.etaMessage?.trimmingCharacters(in: .whitespaces), !msg.isEmpty {
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
