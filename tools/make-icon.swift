#!/usr/bin/env swift
// 使い方: swift tools/make-icon.swift OUTPUT.png SIZE
// メニューバーの円グラフ (白い輪郭円 + 明るいグレーの扇形 + オレンジの経過線) をモチーフにした
// macOS 標準角丸正方形のアプリアイコン PNG を CoreGraphics で描画する。

import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 3,
      let size = Int(CommandLine.arguments[2]) else {
    FileHandle.standardError.write("usage: swift make-icon.swift OUTPUT.png SIZE\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = CommandLine.arguments[1]
let dimension = CGFloat(size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("failed to create CGContext\n".data(using: .utf8)!)
    exit(1)
}
context.setShouldAntialias(true)
context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// 背景は透明のまま。角丸正方形は外側に約10%の余白を空ける。
let squareSide = dimension * 0.8047
let squareOrigin = CGPoint(x: (dimension - squareSide) / 2, y: (dimension - squareSide) / 2)
let squareRect = CGRect(origin: squareOrigin, size: CGSize(width: squareSide, height: squareSide))
let cornerRadius = squareSide * 0.22

let backgroundColor = CGColor(red: CGFloat(0x1E) / 255, green: CGFloat(0x24) / 255, blue: CGFloat(0x30) / 255, alpha: 1)
let squirclePath = CGPath(roundedRect: squareRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
context.addPath(squirclePath)
context.setFillColor(backgroundColor)
context.fillPath()

let center = CGPoint(x: dimension / 2, y: dimension / 2)
let circleDiameter = squareSide * 0.62
let circleRadius = circleDiameter / 2

// 白い輪郭円
let ringLineWidth = circleDiameter * 0.06
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(ringLineWidth)
context.addArc(center: center, radius: circleRadius - ringLineWidth / 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

// 扇形 (12時位置から時計回りに約65%)。CoreGraphics の角度は反時計回りが正、0°=3時位置。
// 12時 = 90°、時計回りに進む = 角度を減らす方向。
func angle(forFractionFrom12 fraction: CGFloat) -> CGFloat {
    (90 - fraction * 360) * .pi / 180
}
let sectorFraction: CGFloat = 0.65
let sectorPath = CGMutablePath()
sectorPath.move(to: center)
sectorPath.addArc(
    center: center,
    radius: circleRadius - ringLineWidth,
    startAngle: angle(forFractionFrom12: 0),
    endAngle: angle(forFractionFrom12: sectorFraction),
    clockwise: true
)
sectorPath.closeSubpath()
context.addPath(sectorPath)
context.setFillColor(CGColor(gray: 0.7, alpha: 1))
context.fillPath()

// 経過線 (中心から円周へ約40%位置のオレンジの線)
let lineFraction: CGFloat = 0.65
let lineAngle = angle(forFractionFrom12: lineFraction)
let lineLength = circleRadius * 0.4
let lineEnd = CGPoint(x: center.x + lineLength * cos(lineAngle), y: center.y + lineLength * sin(lineAngle))
context.setStrokeColor(CGColor(red: 1, green: CGFloat(0x95) / 255, blue: 0, alpha: 1))
context.setLineWidth(circleDiameter * 0.05)
context.setLineCap(.round)
context.move(to: center)
context.addLine(to: lineEnd)
context.strokePath()

guard let cgImage = context.makeImage() else {
    FileHandle.standardError.write("failed to render image\n".data(using: .utf8)!)
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
