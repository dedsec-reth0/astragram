import Foundation
import UIKit
import Display
import AppBundle
import TelegramCore
import SwiftSignalKit

/// AstraGram Monochrome: the settings icons are drawn once, so they follow the switch after the app restarts.
private let astraMonochromeSettingsIcons: Bool = AstraGramSettings.current.monochrome

/// AstraGram Folio: the settings icons become flat tiles with one glyph colour. The switch is read at call time, so
/// toggling Folio takes effect the next time a settings list is built, without a restart. Folio wins when both
/// switches are somehow stored on.
private func astraFolioSettingsIcons() -> Bool {
    return AstraLook.design2027
}

/// Which Folio tile: ink for every tile, and Klein Volt for the AstraGram row, the one place the accent marks.
private enum AstraFolioTileKind {
    case ink
    case volt
}

/// The Folio tiles drawn so far, keyed by glyph, scale, kind and appearance, so each tile is drawn at most once per
/// appearance.
private let astraFolioTileCache = Atomic<[String: UIImage]>(value: [:])

/// AstraGram Folio: the tile for the appearance the Folio presentation is in now, drawn once and then cached.
private func astraFolioCachedSettingsTile(name: String, scaleFactor: CGFloat = 1.0, kind: AstraFolioTileKind) -> UIImage? {
    let dark = astraFolioCurrentAppearanceIsDark()
    let key = "\(name)|\(scaleFactor)|\(kind == .volt ? "v" : "i")|\(dark ? "d" : "l")"
    if let cached = astraFolioTileCache.with({ $0[key] }) {
        return cached
    }
    guard let image = astraFolioSettingsTile(name: name, scaleFactor: scaleFactor, kind: kind, dark: dark) else {
        return nil
    }
    let _ = astraFolioTileCache.modify { cache in
        var cache = cache
        cache[key] = image
        return cache
    }
    return image
}

/// AstraGram Folio: a flat 30x30 tile with continuous 9pt corners and a 0.5pt white hairline just inside the edge.
/// Light: an ink tile with a white glyph. Dark: a graphite tile with a paper glyph and a fainter rim, so the tile sits
/// on the dark cards instead of punching a hole in them. The AstraGram tile is volt (the dark volt with an ink glyph).
private func astraFolioSettingsTile(name: String, scaleFactor: CGFloat = 1.0, kind: AstraFolioTileKind, dark: Bool) -> UIImage? {
    let fill: UIColor
    let glyph: UIColor
    switch kind {
    case .ink:
        fill = dark ? UIColor(rgb: 0x2A2A2E) : UIColor(rgb: 0x0B0B0C)
        glyph = dark ? UIColor(rgb: 0xF4F3EE, alpha: 0.92) : UIColor.white
    case .volt:
        fill = dark ? UIColor(rgb: 0x8B7DFF) : UIColor(rgb: 0x3D2BFF)
        glyph = dark ? UIColor(rgb: 0x0B0B0C) : UIColor.white
    }
    let rimAlpha: CGFloat = dark ? 0.06 : 0.14
    return generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let radius = AstraLook.Folio.settingsIconRadius
        let tilePath = UIBezierPath(roundedRect: bounds, cornerRadius: radius)
        context.saveGState()
        context.addPath(tilePath.cgPath)
        context.setFillColor(fill.cgColor)
        context.fillPath()
        context.restoreGState()
        
        if let image = UIImage(bundleImageName: name), let maskImage = image.cgImage {
            let imageSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
            let imageRect = CGRect(origin: CGPoint(x: (bounds.width - imageSize.width) * 0.5, y: (bounds.height - imageSize.height) * 0.5), size: imageSize)
            
            context.saveGState()
            context.clip(to: imageRect, mask: maskImage)
            context.setFillColor(glyph.cgColor)
            context.fill(imageRect)
            context.restoreGState()
        }
        
        // The stroke is centred on a path inset by half its width, so all of it lies inside the tile.
        let strokeWidth: CGFloat = 0.5
        let strokePath = UIBezierPath(roundedRect: bounds.insetBy(dx: strokeWidth * 0.5, dy: strokeWidth * 0.5), cornerRadius: radius - strokeWidth * 0.5)
        context.saveGState()
        context.addPath(strokePath.cgPath)
        context.setLineWidth(strokeWidth)
        context.setStrokeColor(UIColor.white.withAlphaComponent(rimAlpha).cgColor)
        context.strokePath()
        context.restoreGState()
    })
}

/// AstraGram Folio: the Folio tile while Folio is on, otherwise the stock icon (drawn once, as before).
private func astraFolioSettingsIcon(name: String, kind: AstraFolioTileKind = .ink, stock: () -> UIImage?) -> UIImage? {
    if astraFolioSettingsIcons(), let tile = astraFolioCachedSettingsTile(name: name, kind: kind) {
        return tile
    }
    return stock()
}

/// AstraGram Monochrome: an icon drawn in color, with its colors taken away.
private func astraMonochromeSettingsIcon(_ image: UIImage?) -> UIImage? {
    // Folio takes precedence over Monochrome, so its own icons are never desaturated on top.
    guard astraMonochromeSettingsIcons, !astraFolioSettingsIcons(), let image, let cgImage = image.cgImage else {
        return image
    }
    let result = generateImage(image.size, contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        context.draw(cgImage, in: bounds)
        context.saveGState()
        context.clip(to: bounds, mask: cgImage)
        context.setBlendMode(.saturation)
        context.setFillColor(UIColor.black.cgColor)
        context.fill(bounds)
        context.restoreGState()
    })
    return result ?? image
}

private let gradientImage = UIImage(bundleImageName: "Item List/Icons/Gradient")
private let backdropImage = UIImage(bundleImageName: "Item List/Icons/Backdrop")
public func renderSettingsIcon(name: String, scaleFactor: CGFloat = 1.0, backgroundColors rawBackgroundColors: [UIColor]? = nil) -> UIImage? {
    if astraFolioSettingsIcons(), rawBackgroundColors != nil {
        // Under Folio every coloured tile is the same flat ink tile; only the glyph tells the rows apart.
        return astraFolioCachedSettingsTile(name: name, scaleFactor: scaleFactor, kind: .ink)
    }
    return renderStockSettingsIcon(name: name, scaleFactor: scaleFactor, backgroundColors: rawBackgroundColors)
}

/// The stock settings icon, never the Folio tile, so a stock icon cached in a `static let` stays stock.
private func renderStockSettingsIcon(name: String, scaleFactor: CGFloat = 1.0, backgroundColors rawBackgroundColors: [UIColor]? = nil) -> UIImage? {
    var backgroundColors = rawBackgroundColors
    if astraMonochromeSettingsIcons, let rawBackgroundColors {
        backgroundColors = rawBackgroundColors.map { _ in UIColor(rgb: 0x2e2e2e) }
    }
    return generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        if let backgroundColors {
            var locations: [CGFloat] = [0.0, 1.0]
            let colors: [CGColor] = backgroundColors.map(\.cgColor)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
            
            context.drawLinearGradient(gradient, start: CGPoint(x: size.width, y: size.height), end: CGPoint(x: 0.0, y: 0.0), options: CGGradientDrawingOptions())
            
            if let gradientImage, let cgImage = gradientImage.cgImage {
                context.setBlendMode(.plusLighter)
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }
            
            if let backdropImage, let cgImage = backdropImage.cgImage {
                context.setBlendMode(.overlay)
                context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
            }
                        
            context.setBlendMode(.normal)
            
            if let image = UIImage(bundleImageName: name), let maskImage = image.cgImage {
                let imageSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
                let imageRect = CGRect(origin: CGPoint(x: (bounds.width - imageSize.width) * 0.5, y: (bounds.height - imageSize.height) * 0.5), size: imageSize)
                
                context.saveGState()
                context.clip(to: imageRect, mask: maskImage)
                context.setFillColor(UIColor.white.cgColor)
                context.fill(imageRect)
                context.restoreGState()
            }
            
            let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
            let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
            outerPath.append(innerPath)

            context.saveGState()
            outerPath.usesEvenOddFillRule = true
            context.addPath(outerPath.cgPath)
            context.clip(using: .evenOdd)

            context.setBlendMode(.clear)
            context.fill(CGRect(origin: .zero, size: size))
            context.restoreGState()
        } else {
            if let image = UIImage(bundleImageName: name), let cgImage = image.cgImage {
                let imageSize: CGSize
                if scaleFactor == 1.0 {
                    imageSize = size
                } else {
                    imageSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
                }
                context.draw(cgImage, in: CGRect(origin: CGPoint(x: (bounds.width - imageSize.width) * 0.5, y: (bounds.height - imageSize.height) * 0.5), size: imageSize))
            }
        }
    })
}

public func renderAttachAppIcon(iconImage: UIImage?) -> UIImage? {
    return astraMonochromeSettingsIcon(generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
                
        if let iconImage, let cgImage = iconImage.cgImage {
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }

        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.saveGState()
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
            context.restoreGState()
        }
        
        // These icons are whole pictures with no separate glyph, so Folio keeps the picture and only matches the
        // 9pt corner of its tiles.
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: astraFolioSettingsIcons() ? AstraLook.Folio.settingsIconRadius : 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }))
}

let colorRed = UIColor(rgb: 0xFF453A)
let colorGreen = UIColor(rgb: 0x34C759)
let colorBlue = UIColor(rgb: 0x0a84ff)
let colorLightBlue = UIColor(rgb: 0x32ADE6)
let colorTeal = UIColor(rgb: 0x00c7be)
let colorOrange = UIColor(rgb: 0xFF9F0A)
let colorPurple = UIColor(rgb: 0xAF52DE)
let colorGray = UIColor(rgb: 0x8E8E93)
let colorViolet = UIColor(rgb: 0x5E5CE6)

public struct PresentationResourcesSettings {
    public static var proxy: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Proxy", stock: { stockProxy }) }
    public static var savedMessages: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/SavedMessages", stock: { stockSavedMessages }) }
    public static var recentCalls: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Phone", stock: { stockRecentCalls }) }
    public static var contacts: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Members", stock: { stockContacts }) }
    public static var devices: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Devices", stock: { stockDevices }) }
    public static var chatFolders: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Folder", stock: { stockChatFolders }) }
    public static var stickers: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Sticker", stock: { stockStickers }) }
    public static var notifications: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Notifications", stock: { stockNotifications }) }
    public static var security: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Privacy", stock: { stockSecurity }) }
    public static var dataAndStorage: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Data", stock: { stockDataAndStorage }) }
    public static var appearance: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Appearance", stock: { stockAppearance }) }
    public static var language: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Language", stock: { stockLanguage }) }
    public static var powerSaving: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/PowerSaving", stock: { stockPowerSaving }) }
    public static var business: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Business", stock: { stockBusiness }) }
    public static var myProfile: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Profile", stock: { stockMyProfile }) }
    
    public static var birthday: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Cake", stock: { stockBirthday }) }
    public static var aiTools: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/AITools", stock: { stockAiTools }) }
    public static var yourColor: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Brush", stock: { stockYourColor }) }
    
    public static var storageUsage: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Pie", stock: { stockStorageUsage }) }
    public static var dataUsage: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Stats", stock: { stockDataUsage }) }
    
    public static var cellular: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Cellular", stock: { stockCellular }) }
    public static var wifi: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Wifi", stock: { stockWifi }) }
    
    public static var privateChats: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Member", stock: { stockPrivateChats }) }
    public static var groups: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Group", stock: { stockGroups }) }
    public static var channels: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Channel", stock: { stockChannels }) }
    public static var stories: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Stories", stock: { stockStories }) }
    public static var reactions: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Reactions", stock: { stockReactions }) }
    
    public static var photos: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Photo", stock: { stockPhotos }) }
    public static var videos: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Video", stock: { stockVideos }) }
    public static var files: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/File", stock: { stockFiles }) }
    public static var gifs: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Gif", stock: { stockGifs }) }
    public static var stickersGreen: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Sticker", stock: { stockStickersGreen }) }
    public static var emoji: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Emoji", stock: { stockEmoji }) }
    public static var emojiTeal: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Emoji", stock: { stockEmojiTeal }) }
    public static var archivedSticker: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/ArchivedSticker", stock: { stockArchivedSticker }) }
    public static var trendingSticker: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/TrendingSticker", stock: { stockTrendingSticker }) }
    public static var effects: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Effect", stock: { stockEffects }) }
    // The AstraGram row is the one Folio tile in Klein Volt.
    public static var astraGram: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Effect", kind: .volt, stock: { stockAstraGram }) }
    private static let stockAstraGram = renderStockSettingsIcon(name: "Item List/Icons/Effect", backgroundColors: [colorViolet])
    public static var photosBlue: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Photo", stock: { stockPhotosBlue }) }
    public static var clock: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Clock", stock: { stockClock }) }
    public static var photosLightBlue: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Photo", stock: { stockPhotosLightBlue }) }
    public static var videosBlue: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Video", stock: { stockVideosBlue }) }
    
    public static var block: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Block", stock: { stockBlock }) }
    public static var activeSessions: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Language", stock: { stockActiveSessions }) }
    public static var faceId: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/FaceId", stock: { stockFaceId }) }
    public static var lockOrange: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Privacy", stock: { stockLockOrange }) }
    public static var passkeys: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Key", stock: { stockPasskeys }) }
    public static var timer: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Timer", stock: { stockTimer }) }
    public static var email: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Email", stock: { stockEmail }) }
        
    // Folio draws this gradient tile as an ink tile too, with the same glyph at its own size.
    public static var premium: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Premium", stock: { stockPremium }) }
    private static let stockPremium = astraMonochromeSettingsIcon(generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
                
        let colorsArray: [CGColor] = [
            UIColor(rgb: 0x6b93ff).cgColor,
            UIColor(rgb: 0x6b93ff).cgColor,
            UIColor(rgb: 0x8d77ff).cgColor,
            UIColor(rgb: 0xb56eec).cgColor,
            UIColor(rgb: 0xb56eec).cgColor
        ]
        var locations: [CGFloat] = [0.0, 0.15, 0.5, 0.85, 1.0]
        let gradient = CGGradient(colorsSpace: deviceColorSpace, colors: colorsArray as CFArray, locations: &locations)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        
        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
        }
        
        context.setBlendMode(.normal)
        
        if let image = generateTintedImage(image: UIImage(bundleImageName: "Item List/Icons/Premium"), color: UIColor(rgb: 0xffffff)), let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - image.size.width) / 2.0), y: floorToScreenPixels((bounds.height - image.size.height) / 2.0)), size: image.size))
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }))
    
    public static var ton: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Gram", stock: { stockTon }) }
    public static var gramEarnings: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Earnings", stock: { stockGramEarnings }) }
    
    public static let money = UIImage(bundleImageName: "Settings/Gram")
 
    // Folio draws this gradient tile as an ink tile too, with the same glyph at its own size.
    public static var stars: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Stars", stock: { stockStars }) }
    private static let stockStars = astraMonochromeSettingsIcon(generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let colorsArray: [CGColor] = [
            UIColor(rgb: 0xfec80f).cgColor,
            UIColor(rgb: 0xdd6f12).cgColor
        ]
        var locations: [CGFloat] = [0.0, 1.0]
        let gradient = CGGradient(colorsSpace: deviceColorSpace, colors: colorsArray as CFArray, locations: &locations)!

        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        
        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
        }
        
        context.setBlendMode(.normal)
        
        if let image = generateTintedImage(image: UIImage(bundleImageName: "Item List/Icons/Stars"), color: UIColor(rgb: 0xffffff)), let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - image.size.width) / 2.0), y: floorToScreenPixels((bounds.height - image.size.height) / 2.0)), size: image.size))
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }))
    
    // Folio draws this gradient tile as an ink tile too, with the same glyph at its own size.
    public static var premiumGift: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Gift", stock: { stockPremiumGift }) }
    private static let stockPremiumGift = astraMonochromeSettingsIcon(generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let colorsArray: [CGColor] = [
            UIColor(rgb: 0x3ba1f2).cgColor,
            UIColor(rgb: 0x3ba1f2).cgColor,
            UIColor(rgb: 0x39b3b4).cgColor,
            UIColor(rgb: 0x34c27d).cgColor,
            UIColor(rgb: 0x34c27d).cgColor
        ]
        var locations: [CGFloat] = [0.0, 0.15, 0.5, 0.85, 1.0]
        let gradient = CGGradient(colorsSpace: deviceColorSpace, colors: colorsArray as CFArray, locations: &locations)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        
        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
        }
        
        context.setBlendMode(.normal)
        
        if let image = generateTintedImage(image: UIImage(bundleImageName: "Item List/Icons/Gift"), color: UIColor(rgb: 0xffffff)), let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - image.size.width) / 2.0), y: floorToScreenPixels((bounds.height - image.size.height) / 2.0)), size: image.size))
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    }))
    
    public static var bot: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Bot", stock: { stockBot }) }

    public static let passport = renderAttachAppIcon(iconImage: UIImage(bundleImageName: "Settings/Menu/Passport"))
    public static let watch = renderAttachAppIcon(iconImage: UIImage(bundleImageName: "Settings/Menu/Watch"))
    
    public static var support: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Support", stock: { stockSupport }) }
    public static var faq: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Faq", stock: { stockFaq }) }
    public static var tips: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Tips", stock: { stockTips }) }
        
    public static var changePhoneNumber: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/ChangePhone", stock: { stockChangePhoneNumber }) }
    public static var deleteAddAccount: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Member", stock: { stockDeleteAddAccount }) }
    public static var deleteSetTwoStepAuth: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Key", stock: { stockDeleteSetTwoStepAuth }) }
    public static var deleteChats: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Delete", stock: { stockDeleteChats }) }
    public static var clearSynced: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Group", stock: { stockClearSynced }) }
    
    public static var groupType: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Members", stock: { stockGroupType }) }
    public static var channelType: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Channel", stock: { stockChannelType }) }
    public static var chatHistory: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Chat", stock: { stockChatHistory }) }
    public static var topics: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Topics", stock: { stockTopics }) }
    public static var links: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Link", stock: { stockLinks }) }
    public static var chatAppearance: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Brush", stock: { stockChatAppearance }) }
    public static var admins: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Admin", stock: { stockAdmins }) }
    public static var subscribers: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Group", stock: { stockSubscribers }) }
    public static var stats: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Stats", stock: { stockStats }) }
    public static var balance: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Balance", stock: { stockBalance }) }
    public static var affiliateProgram: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Affiliate", stock: { stockAffiliateProgram }) }
    public static var earnStars: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Earn", stock: { stockEarnStars }) }
    public static var channelMessages: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Messages", stock: { stockChannelMessages }) }
    public static var settings: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Settings", stock: { stockSettings }) }
    public static var antiSpam: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/AntiSpam", stock: { stockAntiSpam }) }
    public static var recentActions: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/View", stock: { stockRecentActions }) }
    public static var permissions: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Key", stock: { stockPermissions }) }
    public static var autoTranslate: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Translation", stock: { stockAutoTranslate }) }
    public static var emojiStatus: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Status", stock: { stockEmojiStatus }) }
    public static var location: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Location", stock: { stockLocation }) }
    public static let groupRequests = renderAttachAppIcon(iconImage: UIImage(bundleImageName: "Chat/Info/GroupRequestsIcon"))
    
    public static var calls: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Phone", stock: { stockCalls }) }
    public static var messages: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Chat", stock: { stockMessages }) }
    public static var filesGreen: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/File", stock: { stockFilesGreen }) }
    public static var stickersYellow: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Sticker", stock: { stockStickersYellow }) }
    public static var music: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Play", stock: { stockMusic }) }
    public static var voices: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Microphone", stock: { stockVoices }) }
    public static var upload: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Upload", stock: { stockUpload }) }
    public static var download: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Download", stock: { stockDownload }) }
    
    public static var welcome: UIImage? { return astraFolioSettingsIcon(name: "Item List/Icons/Hand", stock: { stockWelcome }) }

    // The stock icons, drawn once on first use while Folio is off.
    private static let stockProxy = renderStockSettingsIcon(name: "Item List/Icons/Proxy", backgroundColors: [colorGreen])
    private static let stockSavedMessages = renderStockSettingsIcon(name: "Item List/Icons/SavedMessages", backgroundColors: [colorBlue])
    private static let stockRecentCalls = renderStockSettingsIcon(name: "Item List/Icons/Phone", backgroundColors: [colorGreen])
    private static let stockContacts = renderStockSettingsIcon(name: "Item List/Icons/Members", backgroundColors: [colorViolet])
    private static let stockDevices = renderStockSettingsIcon(name: "Item List/Icons/Devices", backgroundColors: [colorOrange])
    private static let stockChatFolders = renderStockSettingsIcon(name: "Item List/Icons/Folder", backgroundColors: [colorLightBlue])
    private static let stockStickers = renderStockSettingsIcon(name: "Item List/Icons/Sticker", backgroundColors: [colorOrange])
    private static let stockNotifications = renderStockSettingsIcon(name: "Item List/Icons/Notifications", backgroundColors: [colorRed])
    private static let stockSecurity = renderStockSettingsIcon(name: "Item List/Icons/Privacy", backgroundColors: [colorGray])
    private static let stockDataAndStorage = renderStockSettingsIcon(name: "Item List/Icons/Data", backgroundColors: [colorGreen])
    private static let stockAppearance = renderStockSettingsIcon(name: "Item List/Icons/Appearance", backgroundColors: [colorLightBlue])
    private static let stockLanguage = renderStockSettingsIcon(name: "Item List/Icons/Language", backgroundColors: [colorPurple])
    private static let stockPowerSaving = renderStockSettingsIcon(name: "Item List/Icons/PowerSaving", backgroundColors: [colorOrange])
    private static let stockBusiness = renderStockSettingsIcon(name: "Item List/Icons/Business", backgroundColors: [UIColor(rgb: 0xA95CE3), UIColor(rgb: 0xF16B80)])
    private static let stockMyProfile = renderStockSettingsIcon(name: "Item List/Icons/Profile", backgroundColors: [colorRed])
    private static let stockBirthday = renderStockSettingsIcon(name: "Item List/Icons/Cake", backgroundColors: [colorBlue])
    private static let stockAiTools = renderStockSettingsIcon(name: "Item List/Icons/AITools", backgroundColors: [colorPurple])
    private static let stockYourColor = renderStockSettingsIcon(name: "Item List/Icons/Brush", backgroundColors: [colorLightBlue])
    private static let stockStorageUsage = renderStockSettingsIcon(name: "Item List/Icons/Pie", backgroundColors: [colorOrange])
    private static let stockDataUsage = renderStockSettingsIcon(name: "Item List/Icons/Stats", backgroundColors: [colorPurple])
    private static let stockCellular = renderStockSettingsIcon(name: "Item List/Icons/Cellular", backgroundColors: [colorGreen])
    private static let stockWifi = renderStockSettingsIcon(name: "Item List/Icons/Wifi", backgroundColors: [colorBlue])
    private static let stockPrivateChats = renderStockSettingsIcon(name: "Item List/Icons/Member", backgroundColors: [colorBlue])
    private static let stockGroups = renderStockSettingsIcon(name: "Item List/Icons/Group", backgroundColors: [colorGreen])
    private static let stockChannels = renderStockSettingsIcon(name: "Item List/Icons/Channel", backgroundColors: [colorOrange])
    private static let stockStories = renderStockSettingsIcon(name: "Item List/Icons/Stories", backgroundColors: [colorViolet])
    private static let stockReactions = renderStockSettingsIcon(name: "Item List/Icons/Reactions", backgroundColors: [UIColor(rgb: 0xFF2D55)])
    private static let stockPhotos = renderStockSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [colorOrange])
    private static let stockVideos = renderStockSettingsIcon(name: "Item List/Icons/Video", backgroundColors: [colorRed])
    private static let stockFiles = renderStockSettingsIcon(name: "Item List/Icons/File", backgroundColors: [colorBlue])
    private static let stockGifs = renderStockSettingsIcon(name: "Item List/Icons/Gif", backgroundColors: [colorOrange])
    private static let stockStickersGreen = renderStockSettingsIcon(name: "Item List/Icons/Sticker", backgroundColors: [colorGreen])
    private static let stockEmoji = renderStockSettingsIcon(name: "Item List/Icons/Emoji", backgroundColors: [colorLightBlue])
    private static let stockEmojiTeal = renderStockSettingsIcon(name: "Item List/Icons/Emoji", backgroundColors: [colorTeal])
    private static let stockArchivedSticker = renderStockSettingsIcon(name: "Item List/Icons/ArchivedSticker", backgroundColors: [colorGreen])
    private static let stockTrendingSticker = renderStockSettingsIcon(name: "Item List/Icons/TrendingSticker", backgroundColors: [colorOrange])
    private static let stockEffects = renderStockSettingsIcon(name: "Item List/Icons/Effect", backgroundColors: [colorLightBlue])
    private static let stockPhotosBlue = renderStockSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [colorBlue])
    private static let stockClock = renderStockSettingsIcon(name: "Item List/Icons/Clock", backgroundColors: [colorPurple])
    private static let stockPhotosLightBlue = renderStockSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [colorLightBlue])
    private static let stockVideosBlue = renderStockSettingsIcon(name: "Item List/Icons/Video", backgroundColors: [colorBlue])
    private static let stockBlock = renderStockSettingsIcon(name: "Item List/Icons/Block", backgroundColors: [colorRed])
    private static let stockActiveSessions = renderStockSettingsIcon(name: "Item List/Icons/Language", backgroundColors: [colorBlue])
    private static let stockFaceId = renderStockSettingsIcon(name: "Item List/Icons/FaceId", backgroundColors: [colorGreen])
    private static let stockLockOrange = renderStockSettingsIcon(name: "Item List/Icons/Privacy", backgroundColors: [colorOrange])
    private static let stockPasskeys = renderStockSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [colorViolet])
    private static let stockTimer = renderStockSettingsIcon(name: "Item List/Icons/Timer", backgroundColors: [colorPurple])
    private static let stockEmail = renderStockSettingsIcon(name: "Item List/Icons/Email", backgroundColors: [colorViolet])
    private static let stockTon = renderStockSettingsIcon(name: "Item List/Icons/Gram", backgroundColors: [colorBlue])
    private static let stockGramEarnings = renderStockSettingsIcon(name: "Item List/Icons/Earnings", backgroundColors: [colorBlue])
    private static let stockBot = renderStockSettingsIcon(name: "Item List/Icons/Bot", backgroundColors: [colorBlue])
    private static let stockSupport = renderStockSettingsIcon(name: "Item List/Icons/Support", backgroundColors: [colorOrange])
    private static let stockFaq = renderStockSettingsIcon(name: "Item List/Icons/Faq", backgroundColors: [colorLightBlue])
    private static let stockTips = renderStockSettingsIcon(name: "Item List/Icons/Tips", backgroundColors: [UIColor(rgb: 0xffcc02)])
    private static let stockChangePhoneNumber = renderStockSettingsIcon(name: "Item List/Icons/ChangePhone", backgroundColors: [colorPurple])
    private static let stockDeleteAddAccount = renderStockSettingsIcon(name: "Item List/Icons/Member", backgroundColors: [colorBlue])
    private static let stockDeleteSetTwoStepAuth = renderStockSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [colorViolet])
    private static let stockDeleteChats = renderStockSettingsIcon(name: "Item List/Icons/Delete", backgroundColors: [colorRed])
    private static let stockClearSynced = renderStockSettingsIcon(name: "Item List/Icons/Group", backgroundColors: [colorOrange])
    private static let stockGroupType = renderStockSettingsIcon(name: "Item List/Icons/Members", backgroundColors: [colorBlue])
    private static let stockChannelType = renderStockSettingsIcon(name: "Item List/Icons/Channel", backgroundColors: [colorBlue])
    private static let stockChatHistory = renderStockSettingsIcon(name: "Item List/Icons/Chat", backgroundColors: [colorGreen])
    private static let stockTopics = renderStockSettingsIcon(name: "Item List/Icons/Topics", backgroundColors: [colorLightBlue])
    private static let stockLinks = renderStockSettingsIcon(name: "Item List/Icons/Link", backgroundColors: [colorOrange])
    private static let stockChatAppearance = renderStockSettingsIcon(name: "Item List/Icons/Brush", backgroundColors: [colorOrange])
    private static let stockAdmins = renderStockSettingsIcon(name: "Item List/Icons/Admin", backgroundColors: [colorGreen])
    private static let stockSubscribers = renderStockSettingsIcon(name: "Item List/Icons/Group", backgroundColors: [colorBlue])
    private static let stockStats = renderStockSettingsIcon(name: "Item List/Icons/Stats", backgroundColors: [colorViolet])
    private static let stockBalance = renderStockSettingsIcon(name: "Item List/Icons/Balance", backgroundColors: [colorGreen])
    private static let stockAffiliateProgram = renderStockSettingsIcon(name: "Item List/Icons/Affiliate", backgroundColors: [colorViolet])
    private static let stockEarnStars = renderStockSettingsIcon(name: "Item List/Icons/Earn", backgroundColors: [colorGreen])
    private static let stockChannelMessages = renderStockSettingsIcon(name: "Item List/Icons/Messages", backgroundColors: [colorViolet])
    private static let stockSettings = renderStockSettingsIcon(name: "Item List/Icons/Settings", backgroundColors: [colorOrange])
    private static let stockAntiSpam = renderStockSettingsIcon(name: "Item List/Icons/AntiSpam", backgroundColors: [colorGreen])
    private static let stockRecentActions = renderStockSettingsIcon(name: "Item List/Icons/View", backgroundColors: [colorOrange])
    private static let stockPermissions = renderStockSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [colorGray])
    private static let stockAutoTranslate = renderStockSettingsIcon(name: "Item List/Icons/Translation", backgroundColors: [colorPurple])
    private static let stockEmojiStatus = renderStockSettingsIcon(name: "Item List/Icons/Status", backgroundColors: [colorBlue])
    private static let stockLocation = renderStockSettingsIcon(name: "Item List/Icons/Location", backgroundColors: [colorLightBlue])
    private static let stockCalls = renderStockSettingsIcon(name: "Item List/Icons/Phone", backgroundColors: [colorOrange])
    private static let stockMessages = renderStockSettingsIcon(name: "Item List/Icons/Chat", backgroundColors: [colorViolet])
    private static let stockFilesGreen = renderStockSettingsIcon(name: "Item List/Icons/File", backgroundColors: [colorGreen])
    private static let stockStickersYellow = renderStockSettingsIcon(name: "Item List/Icons/Sticker", backgroundColors: [colorOrange])
    private static let stockMusic = renderStockSettingsIcon(name: "Item List/Icons/Play", backgroundColors: [colorRed])
    private static let stockVoices = renderStockSettingsIcon(name: "Item List/Icons/Microphone", backgroundColors: [colorPurple])
    private static let stockUpload = renderStockSettingsIcon(name: "Item List/Icons/Upload", backgroundColors: [colorBlue])
    private static let stockDownload = renderStockSettingsIcon(name: "Item List/Icons/Download", backgroundColors: [colorGreen])
    private static let stockWelcome = renderStockSettingsIcon(name: "Item List/Icons/Hand", backgroundColors: [colorViolet])
}
