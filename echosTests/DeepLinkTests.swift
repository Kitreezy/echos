//
//  DeepLinkTests.swift
//  echosTests
//
//  Unit: разбор маршрутов echos:// — что открываем, а что молча пропускаем.
//

import Foundation
import Testing
@testable import echos

struct DeepLinkTests {

    private func link(_ string: String) -> DeepLink? {
        URL(string: string).flatMap(DeepLink.init(url:))
    }

    @Test func chatLink_parses() {
        #expect(link("echos://chat/93f440ee4f07d563") == .chat(address: "93f440ee4f07d563"))
    }

    /// Схема и хост по RFC регистронезависимы: ссылка, написанная с капса,
    /// — та же ссылка. Адрес приводим к нижнему регистру сами.
    @Test func uppercasedLink_parses() {
        #expect(link("ECHOS://CHAT/93F440EE4F07D563") == .chat(address: "93f440ee4f07d563"))
    }

    @Test func foreignScheme_isIgnored() {
        #expect(link("https://example.com/chat/93f440ee4f07d563") == nil)
    }

    @Test func unknownRoute_isIgnored() {
        #expect(link("echos://settings") == nil)
        #expect(link("echos://wall/93f440ee4f07d563") == nil)
    }

    @Test func missingAddress_isIgnored() {
        #expect(link("echos://chat") == nil)
        #expect(link("echos://chat/") == nil)
    }

    /// Вложенные маршруты и параметры не несём: сегодня это мусор,
    /// а завтра — поведение, которое никто не заказывал.
    @Test func extraParts_areIgnored() {
        #expect(link("echos://chat/93f440ee4f07d563/edit") == nil)
        #expect(link("echos://chat/93f440ee4f07d563?focus=1") == nil)
        #expect(link("echos://chat/93f440ee4f07d563#top") == nil)
    }
}
