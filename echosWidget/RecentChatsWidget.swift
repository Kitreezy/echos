//
//  RecentChatsWidget.swift
//  echosWidget
//
//  Виджет последних чатов. Данные — снапшот из общего контейнера,
//  который пишет приложение; временная шкала — одна запись до
//  следующего reloadTimelines от приложения. Тап ведёт в чат по ссылке
//  echos://chat/<адрес> — той же, что открывает Spotlight и пуши-заменители.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Конфигурация

/// Что показывать: все последние разговоры или только с непрочитанным.
enum ChatsFilter: String, AppEnum, CaseIterable {
    case all
    case unread

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Что показывать")
    }

    static var caseDisplayRepresentations: [ChatsFilter: DisplayRepresentation] {
        [
            .all: "Последние разговоры",
            .unread: "Только непрочитанные"
        ]
    }
}

struct RecentChatsConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Последние чаты" }
    static var description: IntentDescription? {
        IntentDescription("Показывает последние разговоры echos. Нажатие открывает чат.")
    }

    @Parameter(title: "Показывать", default: .all)
    var filter: ChatsFilter

    init() {}

    init(filter: ChatsFilter) {
        self.filter = filter
    }
}

// MARK: - Timeline

struct ChatsEntry: TimelineEntry {
    let date: Date
    let configuration: RecentChatsConfigurationIntent
    let chats: [WidgetChat]
    /// Плейсхолдер галереи — данные нарисованные, не настоящие.
    let isPreview: Bool
}

struct ChatsProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> ChatsEntry {
        ChatsEntry(date: .now,
                   configuration: RecentChatsConfigurationIntent(),
                   chats: WidgetSnapshotLoader.samples,
                   isPreview: true)
    }

    func snapshot(for configuration: RecentChatsConfigurationIntent,
                  in context: Context) async -> ChatsEntry {
        makeEntry(for: configuration, at: .now, preview: context.isPreview)
    }

    func timeline(for configuration: RecentChatsConfigurationIntent,
                  in context: Context) async -> Timeline<ChatsEntry> {
        let entry = makeEntry(for: configuration, at: .now, preview: context.isPreview)
        // Снапшот меняется, только когда приложение его переписывает, —
        // следующая запись неизвестна. Просим систему заглянуть к нам
        // снова через полчаса; точнее всё равно приложение само звонит
        // через WidgetCenter.reloadTimelines после записи.
        let next = Date.now.addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(for configuration: RecentChatsConfigurationIntent,
                           at date: Date,
                           preview: Bool) -> ChatsEntry {
        let all = WidgetSnapshotLoader.load() ?? []
        let chats = configuration.filter == .unread
            ? all.filter { $0.unreadCount > 0 }
            : all
        return ChatsEntry(date: date,
                          configuration: configuration,
                          chats: preview ? (chats.isEmpty ? WidgetSnapshotLoader.samples : chats) : chats,
                          isPreview: preview)
    }
}

// MARK: - Виджет

struct RecentChatsWidget: Widget {

    let kind = "RecentChats"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: RecentChatsConfigurationIntent.self,
                               provider: ChatsProvider()) { entry in
            RecentChatsView(entry: entry)
                .containerBackground(Color.sumi, for: .widget)
        }
        .configurationDisplayName("Последние чаты")
        .description("Последние разговоры. Нажатие открывает чат.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct echosWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentChatsWidget()
    }
}

// MARK: - Представление

private struct RecentChatsView: View {

    @Environment(\.widgetFamily) private var family
    let entry: ChatsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            small
        default:
            medium
        }
    }

    /// Маленький: последний разговор целиком, тап — в чат.
    @ViewBuilder
    private var small: some View {
        if let chat = entry.chats.first {
            ChatRow(chat: chat)
                .widgetURL(chat.deepLink)
        } else {
            EmptyChatsView()
                .widgetURL(URL(string: "echos://")!)
        }
    }

    /// Средний: до четырёх разговоров, тап по строке — в свой чат.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.chats.isEmpty {
                EmptyChatsView()
            } else {
                ForEach(Array(entry.chats.prefix(4).enumerated()), id: \.element) { index, chat in
                    Link(destination: chat.deepLink) {
                        ChatRow(chat: chat)
                    }
                    if index < entry.chats.prefix(4).count - 1 {
                        Divider()
                            .overlay(Color.ash.opacity(0.4))
                            .padding(.leading, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ChatRow: View {

    let chat: WidgetChat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(chat.peerName)
                    .font(.headline)
                    .foregroundStyle(Color.washi)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(Color.ash)
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.sumi)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.gold))
                }
            }
            Text(chat.preview.isEmpty ? String(localized: "Нет сообщений") : chat.preview)
                .font(.subheadline)
                .foregroundStyle(Color.ash)
                .lineLimit(2)
        }
        .padding(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var time: String {
        Date(timeIntervalSince1970: chat.timestamp)
            .formatted(date: .omitted, time: .shortened)
    }
}

private struct EmptyChatsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("echos")
                .font(.headline)
                .foregroundStyle(Color.washi)
            Text("Разговоров пока нет.\nОткройте приложение, чтобы начать.")
                .font(.caption)
                .foregroundStyle(Color.ash)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Палитра

/// Те же токены, что в приложении (DesignSystem/Palette), продублированные:
/// виджет не видит модуль приложения, а тянуть пакет ради пяти констант
/// незачем. Менять вместе с Palette.
private extension Color {
    static let sumi = Color(hex: 0x0B0B0B)
    static let washi = Color(hex: 0xEDEAE3)
    static let ash = Color(hex: 0x8A8780)
    static let gold = Color(hex: 0xD2A44B)

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
