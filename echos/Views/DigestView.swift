//
//  DigestView.swift
//  echos
//
//  Что я пропустил: пересказ непрочитанного, составленный на телефоне.
//
//  Пункты появляются по мере того, как модель их пишет, — ждать весь
//  ответ незачем, главное идёт первым.
//

import OSLog
import SwiftUI
import Translation

struct DigestView: View {

    @State var viewModel: DigestViewModel

    /// Человек выбрал готовый ответ: текст и сообщение, на которое он.
    /// Ответ идёт в поле ввода, а не в переписку: модель может ошибиться,
    /// отправляет человек.
    var onReply: (String, UUID?) -> Void = { _, _ in }

    /// Показать сообщение, из которого вопрос, в ленте.
    var onShowMessage: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    /// Что скачать. Пока `nil`, `.translationTask` ничего не делает; как
    /// только задано — система спрашивает человека и качает языки.
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            List {
                content
                Section {
                } footer: {
                    Text(footnote)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Пропущенное")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .task {
            await viewModel.startIfNeeded()
        }
        // Замыкание — вне главного актора: сессия не Sendable, а
        // `prepareTranslation` в нём не живёт. Модель экрана захвачена
        // явно — она на главном акторе, и к ней возвращаемся через await.
        .translationTask(download) { @Sendable [viewModel] session in
            do {
                // Системный запрос «скачать языки?». Отказ — ошибка.
                try await session.prepareTranslation()
            } catch is CancellationError {
                return  // экран закрыли
            } catch {
                Logger.digest.error("prepareTranslation failed: \(error, privacy: .public)")
                await viewModel.downloadFailed()
                return
            }
            await viewModel.waitForLanguages()
        }
    }

    private var footnote: String {
        var text = "Пересказ составлен на этом телефоне. Переписка никуда не отправлялась."
        if let pivot = viewModel.translatedVia {
            text += " Модель не знает языка переписки, поэтому она переведена на \(pivot) язык, а пересказ — обратно; перевод тоже сделан на телефоне."
        }
        return text + " Модель может ошибаться — сверяйтесь с сообщениями."
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .starting:
            progress("Читаю \(viewModel.messageCount) сообщений от \(viewModel.peerName)…")
        case let .needsDownload(language):
            Section {
                Text("""
                    Модель на устройстве не знает языка переписки (\(language)). Пересказ получится через \
                    перевод на телефоне, но для него нужны языковые файлы.
                    """)
                Button("Скачать языки") {
                    // Повторное нажатие после отказа: та же конфигурация задачу
                    // не перезапустит — её надо объявить недействительной.
                    viewModel.beginDownload()
                    if download != nil {
                        download?.invalidate()
                    } else if let pair = viewModel.pendingDownload {
                        download = TranslationSession.Configuration(source: pair.source, target: pair.target)
                    }
                }
            }
        case let .downloading(language):
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Система скачивает языки для перевода (\(language) и язык модели). Пересказ начнётся сам, как только они будут готовы.")
                        .foregroundStyle(Color.inkMuted)
                }
            } footer: {
                Text("""
                    Загрузка идёт в системе и продолжится, даже если закрыть этот экран. Если она стоит на \
                    месте — проверьте её в Настройки → Приложения → Перевод → Языки: там видно, качается ли \
                    она вообще.
                    """)
            }
        case .translating:
            progress("Перевожу переписку для модели…")
        case .composing:
            progress("Пишу пересказ…")
        case .translatingBack:
            progress("Перевожу пересказ обратно…")
        case let .reading(part, total):
            progress("Переписка длинная, читаю частями: \(part) из \(total)…")
        case let .writing(digest):
            // Ответы — только в готовом: недописанный вариант можно было
            // бы нажать на полуслове.
            sections(of: digest, withReplies: false)
            progress("Пишу…")
        case let .done(digest):
            sections(of: digest, withReplies: true)
        case let .failed(message):
            Section {
                Label(message, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(Color.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func sections(of digest: Digest, withReplies: Bool) -> some View {
        items("Главное", digest.points)
        if !digest.questions.isEmpty {
            Section("Ждут ответа") {
                ForEach(Array(digest.questions.enumerated()), id: \.offset) { _, question in
                    if viewModel.isAnswered(question) {
                        // Отвеченное остаётся в списке, но гаснет: видно,
                        // что сделано и что ещё нет.
                        Label(question.text, systemImage: "checkmark")
                            .foregroundStyle(Color.inkMuted)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            questionText(question)
                            if withReplies, !question.replies.isEmpty {
                                replies(question.replies, to: question)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        items("Договорились", digest.plans)
    }

    /// Вопрос со ссылкой на сообщение — нажимается: показать, где спросили.
    @ViewBuilder
    private func questionText(_ question: DigestQuestion) -> some View {
        if let id = question.messageID {
            Button {
                onShowMessage(id)
                dismiss()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(question.text)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(question.text)
        }
    }

    private func replies(_ replies: [String], to question: DigestQuestion) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    Button(reply) {
                        onReply(reply, question.messageID)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    // Золото — «своё»: это мои будущие сообщения.
                    .tint(Color.own)
                    .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private func items(_ title: String, _ items: [String]) -> some View {
        // Пустое не показывается: «ждут ответа — ничего» — шум.
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                }
            }
        }
    }

    private func progress(_ text: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(text).foregroundStyle(Color.inkMuted)
            }
        }
    }
}
