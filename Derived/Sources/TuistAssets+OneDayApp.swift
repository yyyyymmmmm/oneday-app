// swiftlint:disable:this file_name
// swiftlint:disable all
// swift-format-ignore-file
// swiftformat:disable all
// Generated using tuist — https://github.com/tuist/tuist



#if os(macOS)
#if hasFeature(InternalImportsByDefault)
public import AppKit
#else
import AppKit
#endif
#else
#if hasFeature(InternalImportsByDefault)
public import UIKit
#else
import UIKit
#endif
#endif

#if canImport(SwiftUI)
#if hasFeature(InternalImportsByDefault)
public import SwiftUI
#else
import SwiftUI
#endif
#endif

// MARK: - Asset Catalogs

public enum OneDayAppAsset: Sendable {
  public static let brandGitHub = OneDayAppImages(name: "BrandGitHub")
  public static let brandGmail = OneDayAppImages(name: "BrandGmail")
  public static let brandGoogleCalendar = OneDayAppImages(name: "BrandGoogleCalendar")
  public static let brandGoogleDrive = OneDayAppImages(name: "BrandGoogleDrive")
  public static let brandGoogleSheets = OneDayAppImages(name: "BrandGoogleSheets")
  public static let brandInstagram = OneDayAppImages(name: "BrandInstagram")
  public static let brandNotion = OneDayAppImages(name: "BrandNotion")
  public static let brandSpotify = OneDayAppImages(name: "BrandSpotify")
  public static let channelBlueBubbles = OneDayAppImages(name: "ChannelBlueBubbles")
  public static let channelDingtalk = OneDayAppImages(name: "ChannelDingtalk")
  public static let channelDiscord = OneDayAppImages(name: "ChannelDiscord")
  public static let channelFeishu = OneDayAppImages(name: "ChannelFeishu")
  public static let channelGoogleChat = OneDayAppImages(name: "ChannelGoogleChat")
  public static let channelLINE = OneDayAppImages(name: "ChannelLINE")
  public static let channelMattermost = OneDayAppImages(name: "ChannelMattermost")
  public static let channelQQ = OneDayAppImages(name: "ChannelQQ")
  public static let channelSignal = OneDayAppImages(name: "ChannelSignal")
  public static let channelSimpleX = OneDayAppImages(name: "ChannelSimpleX")
  public static let channelSlack = OneDayAppImages(name: "ChannelSlack")
  public static let channelTeams = OneDayAppImages(name: "ChannelTeams")
  public static let channelTelegram = OneDayAppImages(name: "ChannelTelegram")
  public static let channelWecom = OneDayAppImages(name: "ChannelWecom")
  public static let channelWhatsApp = OneDayAppImages(name: "ChannelWhatsApp")
  public static let channelYuanbao = OneDayAppImages(name: "ChannelYuanbao")
  public static let launchBackground = OneDayAppColors(name: "LaunchBackground")
  public static let localHermes = OneDayAppImages(name: "LocalHermes")
  public static let localOneDayBridge = OneDayAppImages(name: "LocalOneDayBridge")
  public static let localOverviewBridge = OneDayAppImages(name: "LocalOverviewBridge")
  public static let localWriteGate = OneDayAppImages(name: "LocalWriteGate")
  public static let sangouPartner = OneDayAppImages(name: "SangouPartner")
  public static let tabChat = OneDayAppImages(name: "tab.chat")
  public static let tabFeed = OneDayAppImages(name: "tab.feed")
  public static let tabFiles = OneDayAppImages(name: "tab.files")
  public static let tabGoals = OneDayAppImages(name: "tab.goals")
  public static let tabIdeas = OneDayAppImages(name: "tab.ideas")
}

// MARK: - Implementation Details

public final class OneDayAppColors: Sendable {
  public let name: String

  #if os(macOS)
  public typealias Color = NSColor
  #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  public typealias Color = UIColor
  #endif

  @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, visionOS 1.0, *)
  public var color: Color {
    guard let color = Color(asset: self) else {
      fatalError("Unable to load color asset named \(name).")
    }
    return color
  }

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
  public var swiftUIColor: SwiftUI.Color {
      return SwiftUI.Color(asset: self)
  }
  #endif

  fileprivate init(name: String) {
    self.name = name
  }
}

public extension OneDayAppColors.Color {
  @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, visionOS 1.0, *)
  convenience init?(asset: OneDayAppColors) {
    let bundle = Bundle.module
    #if os(iOS) || os(tvOS) || os(visionOS)
    self.init(named: asset.name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    self.init(named: NSColor.Name(asset.name), bundle: bundle)
    #elseif os(watchOS)
    self.init(named: asset.name)
    #endif
  }
}

#if canImport(SwiftUI)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
public extension SwiftUI.Color {
  init(asset: OneDayAppColors) {
    let bundle = Bundle.module
    self.init(asset.name, bundle: bundle)
  }
}
#endif

public struct OneDayAppImages: Sendable {
  public let name: String

  #if os(macOS)
  public typealias Image = NSImage
  #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  public typealias Image = UIImage
  #endif

  public var image: Image {
    let bundle = Bundle.module
    #if os(iOS) || os(tvOS) || os(visionOS)
    let image = Image(named: name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    let image = bundle.image(forResource: NSImage.Name(name))
    #elseif os(watchOS)
    let image = Image(named: name)
    #endif
    guard let result = image else {
      fatalError("Unable to load image asset named \(name).")
    }
    return result
  }

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
  public var swiftUIImage: SwiftUI.Image {
    SwiftUI.Image(asset: self)
  }
  #endif
}

#if canImport(SwiftUI)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, visionOS 1.0, *)
public extension SwiftUI.Image {
  init(asset: OneDayAppImages) {
    let bundle = Bundle.module
    self.init(asset.name, bundle: bundle)
  }

  init(asset: OneDayAppImages, label: Text) {
    let bundle = Bundle.module
    self.init(asset.name, bundle: bundle, label: label)
  }

  init(decorative asset: OneDayAppImages) {
    let bundle = Bundle.module
    self.init(decorative: asset.name, bundle: bundle)
  }
}
#endif

// swiftformat:enable all
// swiftlint:enable all
