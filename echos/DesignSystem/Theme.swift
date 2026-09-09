//
//  Theme.swift
//  echos
//
//  Семантические токены: не «зелёный», а «связь есть».
//
//  Смысл слоя в том, что цвет в коде экрана не появляется никогда. Захотели
//  сменить всю палитру — правится Palette, экраны не трогаются вовсе.
//
//  Роли назначены так, чтобы цвет нёс информацию, а не украшал:
//
//    своё      золото     твои сообщения и штрихи
//    чужое     лиловый    входящее
//    живое     зелень     собеседник на связи
//    потеряно  охра       связь оборвалась
//    действие  синий      единственная яркая точка на экране
//

import SwiftUI
import UIKit

extension Color {

    // MARK: - Поверхности

    static let surface = Color(hex: Palette.sumi)
    static let surfaceRaised = Color(hex: Palette.sumiRaised)
    static let hairline = Color(hex: Palette.hairline)

    // MARK: - Текст

    static let ink = Color(hex: Palette.washi)
    static let inkMuted = Color(hex: Palette.ash)

    // MARK: - Роли

    static let own = Color(hex: Palette.brightGold)
    static let other = Color(hex: Palette.pastelLilac)
    static let alive = Color(hex: Palette.aventurine)
    static let lost = Color(hex: Palette.redOchre)
    static let action = Color(hex: Palette.blue072)
}

extension UIColor {

    // MARK: - Поверхности

    static let surface = UIColor(hex: Palette.sumi)
    static let surfaceRaised = UIColor(hex: Palette.sumiRaised)
    static let hairline = UIColor(hex: Palette.hairline)

    // MARK: - Текст

    static let ink = UIColor(hex: Palette.washi)
    static let inkMuted = UIColor(hex: Palette.ash)

    // MARK: - Роли

    static let own = UIColor(hex: Palette.brightGold)
    static let other = UIColor(hex: Palette.pastelLilac)
    static let alive = UIColor(hex: Palette.aventurine)
    static let lost = UIColor(hex: Palette.redOchre)
    static let action = UIColor(hex: Palette.blue072)
}
