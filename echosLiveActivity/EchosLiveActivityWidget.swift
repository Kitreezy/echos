//
//  EchosLiveActivityWidget.swift
//  echosLiveActivity
//
//  Live Activity: статус связи и отправки на экране блокировки и в
//  Dynamic Island. Обновляется локально из приложения, без пушей.
//

import ActivityKit
import EchosLiveActivityKit
import SwiftUI
import WidgetKit

@main
struct EchosLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EchosLiveActivityAttributes.self) { context in
            EchosLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.peerName, systemImage: "person.fill")
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isEncrypted ? "lock.fill" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(context.state.isEncrypted ? .green : .secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.connectionText)
                            .font(.subheadline)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            if context.state.sendingCount > 0 {
                                Label("Отправляется \(context.state.sendingCount)",
                                      systemImage: "arrow.up.circle")
                                    .font(.caption)
                            }
                            if context.state.failedCount > 0 {
                                Label("Не отправлено \(context.state.failedCount)",
                                      systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "person.fill")
            } compactTrailing: {
                compactTrailingText(for: context.state)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.state.failedCount > 0
                      ? "exclamationmark.circle.fill"
                      : (context.state.isEncrypted ? "lock.fill" : "ellipsis"))
            }
        }
    }

    @ViewBuilder
    private func compactTrailingText(for state: EchosLiveActivityAttributes.ContentState) -> some View {
        if state.failedCount > 0 {
            Text("!\(state.failedCount)")
        } else if state.sendingCount > 0 {
            Text("\(state.sendingCount)")
        } else {
            Image(systemName: "checkmark")
        }
    }
}

private struct EchosLiveActivityLockScreenView: View {

    let context: ActivityViewContext<EchosLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: context.state.isEncrypted ? "lock.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(context.state.isEncrypted ? .green : .secondary)
                Text(context.state.peerName)
                    .font(.headline)
                Spacer()
            }

            Text(context.state.connectionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 14) {
                if context.state.sendingCount > 0 {
                    Label("Отправляется \(context.state.sendingCount)",
                          systemImage: "arrow.up.circle")
                        .font(.caption)
                }
                if context.state.failedCount > 0 {
                    Label("Не отправлено \(context.state.failedCount)",
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
    }
}
