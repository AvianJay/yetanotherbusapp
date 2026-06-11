import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct BusArrivalLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BusArrivalAttributes.self) { context in
      LockScreenActivityView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          expandedLeading(context: context)
            .dynamicIsland(verticalPlacement: .belowIfTooWide)
            .padding(.leading, 8)
        }
        DynamicIslandExpandedRegion(.trailing) {
          expandedTrailing(context: context)
            .padding(.trailing, 8)
        }
        DynamicIslandExpandedRegion(.bottom) {
          expandedBottom(context: context)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
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
    HStack(spacing: 4) {
      Circle()
        .fill(Color.white.opacity(0.92))
        .frame(width: 4.5, height: 4.5)
      Text(compactRouteName(context.attributes.routeName))
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
      Capsule(style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              etaColor(context.state),
              etaColor(context.state).opacity(0.78),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    )
    .overlay(
      Capsule(style: .continuous)
        .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
    )
    .frame(maxWidth: 58, alignment: .leading)
  }

  @ViewBuilder
  private func compactTrailingView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    countdownText(
      context.state,
      style: .compact,
      font: .system(size: 13, weight: .bold, design: .rounded)
    )
    .foregroundStyle(etaColor(context.state))
    .lineLimit(1)
    .minimumScaleFactor(0.45)
    .monospacedDigit()
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
      Capsule(style: .continuous)
        .fill(etaColor(context.state).opacity(0.14))
    )
    .overlay(
      Capsule(style: .continuous)
        .stroke(etaColor(context.state).opacity(0.28), lineWidth: 0.6)
    )
    .frame(minWidth: 58, alignment: .trailing)
  }

  @ViewBuilder
  private func minimalView(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    ZStack {
      Circle()
        .fill(etaColor(context.state).opacity(0.18))
      Circle()
        .stroke(etaColor(context.state).opacity(0.4), lineWidth: 1.2)
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
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        routeBadge(context.attributes.routeName, surface: .dynamicIsland)
        VStack(alignment: .leading, spacing: 4) {
          Text(context.attributes.pathName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)

          if let modeLabel = trimmedText(context.state.modeLabel) {
            modePill(modeLabel, surface: .dynamicIsland)
          }
        }
      }

      HStack(spacing: 5) {
        Image(systemName: "mappin.circle.fill")
          .font(.system(size: 13))
          .foregroundStyle(.cyan)
        Text(displayStopName(context.state))
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Color.white.opacity(0.08))
      )
    }
  }

  @ViewBuilder
  private func expandedTrailing(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(alignment: .trailing, spacing: 6) {
      VStack(alignment: .trailing, spacing: 2) {
        Text("到站")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(etaColor(context.state).opacity(0.9))

        countdownText(
          context.state,
          style: .expanded,
          font: .system(size: 24, weight: .bold, design: .rounded)
        )
        .foregroundStyle(etaColor(context.state))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .monospacedDigit()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(etaColor(context.state).opacity(0.14))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(etaColor(context.state).opacity(0.28), lineWidth: 0.7)
      )

      if let vehicleId = trimmedText(context.state.vehicleId) {
        HStack(spacing: 3) {
          Image(systemName: "bus")
            .font(.system(size: 10))
          Text(vehicleId)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          Capsule(style: .continuous)
            .fill(Color.white.opacity(0.08))
        )
      }
    }
  }

  @ViewBuilder
  private func expandedBottom(
    context: ActivityViewContext<BusArrivalAttributes>
  ) -> some View {
    VStack(spacing: 8) {
      stopLineView(context.state, surface: .dynamicIsland)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.08))
        )

      HStack {
        if let statusText = trimmedText(context.state.statusText) {
          Text(statusText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .truncationMode(.tail)
        }
        Spacer(minLength: 6)
        HStack(spacing: 3) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 9, weight: .semibold))
          Text(context.state.updatedAt, style: .relative)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Color(white: 0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          Capsule(style: .continuous)
            .fill(Color.white.opacity(0.06))
        )
        .layoutPriority(1)
      }
      .padding(.horizontal, 2)
    }
  }

  // lockScreenView 已移至 LockScreenActivityView struct（見下方）

  @ViewBuilder
  private func routeBadge(
    _ name: String,
    surface: ActivitySurface
  ) -> some View {
    Text(name)
      .font(.system(size: 14, weight: .heavy, design: .rounded))
      .foregroundStyle(routeBadgeTextColor(surface: surface))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(red: 0.0, green: 0.7, blue: 0.8), Color(red: 0.0, green: 0.55, blue: 0.75)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
      )
  }

  @ViewBuilder
  private func modePill(_ label: String, surface: ActivitySurface, colorScheme: ColorScheme = .dark) -> some View {
    Text(label)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(modePillTextColor(surface: surface, colorScheme: colorScheme))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(modePillBackgroundColor(surface: surface, colorScheme: colorScheme))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke((surface == .dynamicIsland ? Color.white : lockScreenPrimaryTextColor(colorScheme: colorScheme)).opacity(0.1), lineWidth: 0.6)
      )
  }

  @ViewBuilder
  private func stopLineView(
    _ state: BusArrivalAttributes.ContentState,
    surface: ActivitySurface,
    colorScheme: ColorScheme = .dark
  ) -> some View {
    if let stopLine = stopLineData(state) {
      // Markers and labels share the same equal-width columns so each dot
      // lines up exactly above its stop name.
      VStack(spacing: 5) {
        HStack(spacing: 0) {
          ForEach(stopLine.stopNames.indices, id: \.self) { index in
            ZStack {
              HStack(spacing: 0) {
                stopConnectorSegment(
                  visible: index > 0,
                  intensity: stopConnectorOpacity(
                    currentStopIndex: stopLine.currentStopIndex,
                    connectorIndex: index - 1
                  ),
                  surface: surface,
                  colorScheme: colorScheme
                )
                stopConnectorSegment(
                  visible: index < stopLine.stopNames.count - 1,
                  intensity: stopConnectorOpacity(
                    currentStopIndex: stopLine.currentStopIndex,
                    connectorIndex: index
                  ),
                  surface: surface,
                  colorScheme: colorScheme
                )
              }
              stopMarker(
                isCurrent: index == stopLine.currentStopIndex,
                isHighlighted: index == stopLine.highlightedStopIndex,
                surface: surface,
                colorScheme: colorScheme
              )
            }
            .frame(maxWidth: .infinity)
          }
        }
        .frame(height: 20)

        HStack(alignment: .top, spacing: 0) {
          ForEach(stopLine.stopNames.indices, id: \.self) { index in
            stopLineLabel(
              stopLine.stopNames[index],
              isCurrent: index == stopLine.currentStopIndex,
              isHighlighted: index == stopLine.highlightedStopIndex,
              surface: surface,
              colorScheme: colorScheme
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
            surface: surface,
            colorScheme: colorScheme
          )
          Spacer(minLength: 0)
        }
      } else {
        VStack(spacing: 5) {
          HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
              ZStack {
                HStack(spacing: 0) {
                  stopConnectorSegment(
                    visible: index > 0,
                    intensity: index == 1 ? 0.4 : 0.22,
                    surface: surface,
                    colorScheme: colorScheme
                  )
                  stopConnectorSegment(
                    visible: index < 2,
                    intensity: index == 0 ? 0.4 : 0.22,
                    surface: surface,
                    colorScheme: colorScheme
                  )
                }
                stopMarker(
                  isCurrent: index == 1,
                  isHighlighted: index == 1,
                  surface: surface,
                  colorScheme: colorScheme
                )
              }
              .frame(maxWidth: .infinity)
            }
          }
          .frame(height: 20)

          HStack(alignment: .top, spacing: 0) {
            stopLineLabel(
              previousStopName ?? "起點",
              isCurrent: false,
              isHighlighted: false,
              surface: surface,
              colorScheme: colorScheme
            )
            stopLineLabel(
              currentStopName,
              isCurrent: true,
              isHighlighted: true,
              surface: surface,
              colorScheme: colorScheme
            )
            stopLineLabel(
              nextStopName ?? "終點",
              isCurrent: false,
              isHighlighted: false,
              surface: surface,
              colorScheme: colorScheme
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
    surface: ActivitySurface,
    colorScheme: ColorScheme = .dark
  ) -> some View {
    if isCurrent {
      ZStack {
        if isHighlighted {
          Circle()
            .stroke(stopMarkerRingColor(surface: surface, colorScheme: colorScheme), lineWidth: 2)
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
        .fill(stopMarkerColor(surface: surface, colorScheme: colorScheme))
        .frame(width: 8, height: 8)
    }
  }

  @ViewBuilder
  private func stopConnectorSegment(
    visible: Bool,
    intensity: Double,
    surface: ActivitySurface,
    colorScheme: ColorScheme = .dark
  ) -> some View {
    Rectangle()
      .fill(
        visible
          ? stopConnectorColor(surface: surface, intensity: intensity, colorScheme: colorScheme)
          : Color.clear
      )
      .frame(maxWidth: .infinity)
      .frame(height: 2)
  }

  @ViewBuilder
  private func stopLineLabel(
    _ text: String,
    isCurrent: Bool,
    isHighlighted: Bool,
    surface: ActivitySurface,
    colorScheme: ColorScheme = .dark
  ) -> some View {
    Text(compactStopLineLabel(text))
      .font(
        .system(
          size: isCurrent ? 11 : 10,
          weight: isCurrent || isHighlighted ? .semibold : .medium
        )
      )
      .foregroundStyle(
        stopLineLabelColor(
          isCurrent: isCurrent,
          isHighlighted: isHighlighted,
          surface: surface,
          colorScheme: colorScheme
        )
      )
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
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
    surface: ActivitySurface,
    colorScheme: ColorScheme = .dark
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
      return lockScreenPrimaryTextColor(colorScheme: colorScheme)
    }
    if isHighlighted {
      return lockScreenHighlightTextColor(colorScheme: colorScheme)
    }
    return lockScreenSecondaryTextColor(colorScheme: colorScheme)
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
    // The badge always sits on the cyan gradient, so white keeps proper
    // contrast on every surface (`.primary` could resolve to near-black).
    .white
  }

  private func modePillTextColor(surface: ActivitySurface, colorScheme: ColorScheme) -> Color {
    if surface == .dynamicIsland {
      return .primary
    }
    return lockScreenPrimaryTextColor(colorScheme: colorScheme).opacity(0.92)
  }

  private func modePillBackgroundColor(surface: ActivitySurface, colorScheme: ColorScheme) -> Color {
    if surface == .dynamicIsland {
      return .secondary.opacity(0.18)
    }
    return lockScreenModePillBackgroundColor(colorScheme: colorScheme)
  }

  private func stopMarkerRingColor(surface: ActivitySurface, colorScheme: ColorScheme) -> Color {
    if surface == .dynamicIsland {
      return .primary.opacity(0.32)
    }
    return lockScreenPrimaryTextColor(colorScheme: colorScheme).opacity(0.75)
  }

  private func stopMarkerColor(surface: ActivitySurface, colorScheme: ColorScheme) -> Color {
    if surface == .dynamicIsland {
      return .secondary.opacity(0.45)
    }
    return lockScreenSecondaryTextColor(colorScheme: colorScheme).opacity(0.45)
  }

  private func stopConnectorColor(surface: ActivitySurface, intensity: Double, colorScheme: ColorScheme) -> Color {
    if surface == .dynamicIsland {
      return .primary.opacity(max(intensity * 0.55, 0.1))
    }
    return lockScreenSecondaryTextColor(colorScheme: colorScheme).opacity(max(intensity, 0.12))
  }

  private func lockScreenBackgroundTintColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return Color(red: 0.08, green: 0.11, blue: 0.17)
    }
    return Color(red: 0.95, green: 0.96, blue: 0.98)
  }

  private func lockScreenActionForegroundColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return .white
    }
    return Color(red: 0.11, green: 0.14, blue: 0.19)
  }

  private func lockScreenPrimaryTextColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return Color(white: 1).opacity(0.96)
    }
    return Color(red: 0.11, green: 0.14, blue: 0.19)
  }

  private func lockScreenSecondaryTextColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return Color(white: 0.82)
    }
    return Color(red: 0.39, green: 0.43, blue: 0.49)
  }

  private func lockScreenHighlightTextColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return Color(red: 0.55, green: 0.9, blue: 0.98)
    }
    return Color(red: 0.0, green: 0.5, blue: 0.62)
  }

  private func lockScreenTimestampTextColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return Color(white: 0.55)
    }
    return Color(red: 0.56, green: 0.59, blue: 0.64)
  }

  private func lockScreenModePillBackgroundColor(colorScheme: ColorScheme) -> Color {
    if colorScheme == .dark {
      return Color(white: 1).opacity(0.14)
    }
    return Color(red: 0.16, green: 0.22, blue: 0.31).opacity(0.1)
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

// MARK: - Lock Screen / Notification Center Live Activity View

private struct LockScreenActivityView: View {
  let context: ActivityViewContext<BusArrivalAttributes>

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(lsCardFillColor)
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(lsCardStrokeColor, lineWidth: 1)

      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 10) {
            lsRouteBadge(context.attributes.routeName)

            VStack(alignment: .leading, spacing: 5) {
              Text(context.attributes.pathName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lsSecondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)

              if let modeLabel = lsTrimmed(context.state.modeLabel) {
                lsModePill(modeLabel)
              }
            }
          }

          HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
              .font(.system(size: 14))
              .foregroundStyle(lsHighlightTextColor)
            Text(lsDisplayStopName(context.state))
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(lsPrimaryTextColor)
              .lineLimit(1)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(lsSectionFillColor)
          )

          if let statusText = lsTrimmed(context.state.statusText) {
            Text(statusText)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(lsSecondaryTextColor)
              .lineLimit(2)
              .minimumScaleFactor(0.85)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          lsStopLineView(context.state)
            .padding(.top, 2)
        }

        VStack(alignment: .trailing, spacing: 8) {
          VStack(alignment: .trailing, spacing: 2) {
            Text("到站")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(lsEtaColor(context.state).opacity(0.9))

            lsCountdownText(
              context.state,
              font: .system(size: 30, weight: .bold, design: .rounded)
            )
            .foregroundStyle(lsEtaColor(context.state))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .monospacedDigit()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(lsEtaPanelFillColor)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(lsEtaPanelStrokeColor, lineWidth: 1)
          )

          if let vehicleId = lsTrimmed(context.state.vehicleId) {
            HStack(spacing: 4) {
              Image(systemName: "bus.fill")
                .font(.system(size: 10))
              Text(vehicleId)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
            }
            .foregroundStyle(lsSecondaryTextColor)
          }

          HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 8, weight: .semibold))
            Text(context.state.updatedAt, style: .relative)
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .lineLimit(1)
          }
          .foregroundStyle(lsTimestampTextColor)
        }
        .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .widgetURL(
      BusArrivalDeepLink.route(
        provider: context.attributes.provider,
        routeKey: context.attributes.routeKey,
        pathId: context.attributes.pathId,
        stopId: context.state.displayStopId
      )
    )
    .activityBackgroundTint(lsBackgroundTintColor)
    .activitySystemActionForegroundColor(lsActionForegroundColor)
  }

  // MARK: Colours (resolved via @Environment colorScheme)

  private var lsBackgroundTintColor: Color {
    colorScheme == .dark
      ? Color(red: 0.08, green: 0.11, blue: 0.17)
      : Color(red: 0.95, green: 0.96, blue: 0.98)
  }

  private var lsActionForegroundColor: Color {
    colorScheme == .dark
      ? .white
      : Color(red: 0.11, green: 0.14, blue: 0.19)
  }

  private var lsPrimaryTextColor: Color {
    colorScheme == .dark
      ? Color(white: 1).opacity(0.96)
      : Color(red: 0.11, green: 0.14, blue: 0.19)
  }

  private var lsSecondaryTextColor: Color {
    colorScheme == .dark
      ? Color(white: 0.82)
      : Color(red: 0.39, green: 0.43, blue: 0.49)
  }

  private var lsHighlightTextColor: Color {
    colorScheme == .dark
      ? Color(red: 0.55, green: 0.9, blue: 0.98)
      : Color(red: 0.0, green: 0.5, blue: 0.62)
  }

  private var lsTimestampTextColor: Color {
    colorScheme == .dark
      ? Color(white: 0.55)
      : Color(red: 0.56, green: 0.59, blue: 0.64)
  }

  private var lsModePillBackgroundColor: Color {
    colorScheme == .dark
      ? Color(white: 1).opacity(0.14)
      : Color(red: 0.16, green: 0.22, blue: 0.31).opacity(0.1)
  }

  private var lsCardFillColor: Color {
    colorScheme == .dark
      ? Color(red: 0.12, green: 0.16, blue: 0.24).opacity(0.96)
      : Color.white.opacity(0.94)
  }

  private var lsCardStrokeColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.08)
      : Color(red: 0.16, green: 0.22, blue: 0.31).opacity(0.08)
  }

  private var lsSectionFillColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.08)
      : Color(red: 0.16, green: 0.22, blue: 0.31).opacity(0.06)
  }

  private var lsEtaPanelFillColor: Color {
    lsEtaColor(context.state).opacity(colorScheme == .dark ? 0.16 : 0.12)
  }

  private var lsEtaPanelStrokeColor: Color {
    lsEtaColor(context.state).opacity(colorScheme == .dark ? 0.34 : 0.22)
  }

  // MARK: Helpers

  private func lsTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }

  private func lsDisplayStopName(_ state: BusArrivalAttributes.ContentState) -> String {
    lsTrimmed(state.displayStopName) ?? "背景乘車提醒"
  }

  private func lsEtaColor(_ state: BusArrivalAttributes.ContentState) -> Color {
    if lsTrimmed(state.etaMessage) != nil { return Color(red: 0.0, green: 0.7, blue: 0.65) }
    guard let sec = state.etaSeconds else { return Color(white: 0.5) }
    if sec <= 0 { return Color(red: 0.9, green: 0.22, blue: 0.21) }
    if sec < 60  { return Color(red: 0.9, green: 0.3, blue: 0.25) }
    if sec < 180 { return Color(red: 0.94, green: 0.42, blue: 0.0) }
    return Color(red: 0.0, green: 0.74, blue: 0.83)
  }

  // MARK: Sub-views

  @ViewBuilder
  private func lsRouteBadge(_ name: String) -> some View {
    Text(name)
      .font(.system(size: 14, weight: .heavy, design: .rounded))
      .foregroundStyle(Color.white)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(red: 0.0, green: 0.7, blue: 0.8), Color(red: 0.0, green: 0.55, blue: 0.75)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
      )
  }

  @ViewBuilder
  private func lsModePill(_ label: String) -> some View {
    Text(label)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(lsPrimaryTextColor.opacity(0.92))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(lsModePillBackgroundColor)
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(lsPrimaryTextColor.opacity(0.08), lineWidth: 0.6)
      )
  }

  @ViewBuilder
  private func lsCountdownText(
    _ state: BusArrivalAttributes.ContentState,
    font: Font
  ) -> some View {
    if let msg = lsTrimmed(state.etaMessage) {
      Text(msg)
        .font(font)
    } else if let timerInterval = state.etaTimerInterval {
      Text(
        timerInterval: timerInterval,
        pauseTime: nil,
        countsDown: true,
        showsHours: state.etaShowsHours
      )
      .font(font)
    } else if let sec = state.etaSeconds, sec <= 0 {
      Text("進站中")
        .font(font)
    } else {
      Text("--")
        .font(font)
    }
  }

  @ViewBuilder
  private func lsStopLineView(_ state: BusArrivalAttributes.ContentState) -> some View {
    if !state.lineStopNames.isEmpty {
      let count = state.lineStopNames.count
      let currentIdx = (state.lineCurrentStopIndex.map { $0 >= 0 && $0 < count ? $0 : 0 }) ?? 0
      let highlightIdx = state.lineHighlightedStopIndex.flatMap { $0 >= 0 && $0 < count ? $0 : nil }

      // Markers and labels share the same equal-width columns so each dot
      // lines up exactly above its stop name.
      VStack(spacing: 5) {
        HStack(spacing: 0) {
          ForEach(state.lineStopNames.indices, id: \.self) { index in
            ZStack {
              HStack(spacing: 0) {
                lsStopConnectorSegment(
                  visible: index > 0,
                  intensity: index - 1 < currentIdx ? 0.46 : 0.18
                )
                lsStopConnectorSegment(
                  visible: index < count - 1,
                  intensity: index < currentIdx ? 0.46 : 0.18
                )
              }
              lsStopMarker(isCurrent: index == currentIdx, isHighlighted: index == highlightIdx)
            }
            .frame(maxWidth: .infinity)
          }
        }
        .frame(height: 20)

        HStack(alignment: .top, spacing: 0) {
          ForEach(state.lineStopNames.indices, id: \.self) { index in
            lsStopLabel(
              state.lineStopNames[index],
              isCurrent: index == currentIdx,
              isHighlighted: index == highlightIdx
            )
          }
        }
      }
    } else {
      let prev = lsTrimmed(state.previousStopName)
      let next = lsTrimmed(state.nextStopName)
      let current = lsDisplayStopName(state)

      if prev == nil && next == nil {
        HStack {
          Spacer(minLength: 0)
          lsStopLabel(current, isCurrent: true, isHighlighted: true)
          Spacer(minLength: 0)
        }
      } else {
        VStack(spacing: 5) {
          HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
              ZStack {
                HStack(spacing: 0) {
                  lsStopConnectorSegment(
                    visible: index > 0,
                    intensity: index == 1 ? 0.4 : 0.22
                  )
                  lsStopConnectorSegment(
                    visible: index < 2,
                    intensity: index == 0 ? 0.4 : 0.22
                  )
                }
                lsStopMarker(isCurrent: index == 1, isHighlighted: index == 1)
              }
              .frame(maxWidth: .infinity)
            }
          }
          .frame(height: 20)

          HStack(alignment: .top, spacing: 0) {
            lsStopLabel(prev ?? "起點", isCurrent: false, isHighlighted: false)
            lsStopLabel(current, isCurrent: true, isHighlighted: true)
            lsStopLabel(next ?? "終點", isCurrent: false, isHighlighted: false)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func lsStopMarker(isCurrent: Bool, isHighlighted: Bool) -> some View {
    if isCurrent {
      ZStack {
        if isHighlighted {
          Circle()
            .stroke(lsPrimaryTextColor.opacity(0.75), lineWidth: 2)
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
        .background(Circle().fill(Color(red: 0.0, green: 0.74, blue: 0.83).opacity(0.18)))
        .frame(width: 12, height: 12)
    } else {
      Circle()
        .fill(lsSecondaryTextColor.opacity(0.45))
        .frame(width: 8, height: 8)
    }
  }

  @ViewBuilder
  private func lsStopConnectorSegment(visible: Bool, intensity: Double) -> some View {
    Rectangle()
      .fill(visible ? lsSecondaryTextColor.opacity(max(intensity, 0.12)) : Color.clear)
      .frame(maxWidth: .infinity)
      .frame(height: 2)
  }

  @ViewBuilder
  private func lsStopLabel(_ text: String, isCurrent: Bool, isHighlighted: Bool) -> some View {
    let label = lsCompactStopLabel(text)
    let color: Color = isCurrent ? lsPrimaryTextColor : (isHighlighted ? lsHighlightTextColor : lsSecondaryTextColor)
    Text(label)
      .font(.system(
        size: isCurrent ? 11 : 10,
        weight: isCurrent || isHighlighted ? .semibold : .medium
      ))
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private func lsCompactStopLabel(_ text: String) -> String {
    let trimmed = lsTrimmed(text) ?? text
    let separators = ["(", "（", " ", "/", "／", "-", "－"]
    var candidate = trimmed
    for sep in separators {
      if let range = candidate.range(of: sep) {
        candidate = String(candidate[..<range.lowerBound])
        break
      }
    }
    return candidate.count <= 4 ? candidate : String(candidate.prefix(4)) + "…"
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
