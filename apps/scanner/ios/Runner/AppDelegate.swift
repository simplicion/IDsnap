import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let privacyCover = PrivacyCover()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    privacyCover.observe()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Ads (ADR-0013): the consent platform's IAB TCF values, for
    // non-personalised requests. Must match
    // GoogleAdsPlatform.consentChannelName in engine_ads.
    let adConsent = FlutterMethodChannel(
      name: "idsnap/ad_consent",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    adConsent.setMethodCallHandler { call, result in
      guard call.method == "tcf" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let defaults = UserDefaults.standard
      result([
        "gdprApplies": defaults.object(forKey: "IABTCF_gdprApplies") as? Int as Any,
        "purposeConsents": defaults.string(forKey: "IABTCF_PurposeConsents") as Any,
      ])
    }
    // Channel name must match SecureWindow.channelName in engine_security.
    let channel = FlutterMethodChannel(
      name: "docscan/secure_window",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setSecure":
        let args = call.arguments as? [String: Any]
        self?.privacyCover.enabled = (args?["enabled"] as? Bool) ?? false
        result(nil)
      case "consumeExternalLaunch":
        // Presented pickers / share sheets don't background an iOS app.
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// App Lock privacy snapshot: while enabled (App Lock on or a sensitive
/// screen visible), covers every window when the app resigns active, so the
/// app-switcher snapshot shows no content, and removes the cover when the app
/// becomes active again. Uses notifications rather than overriding
/// FlutterSceneDelegate, so Flutter's own lifecycle handling is untouched.
final class PrivacyCover {
  var enabled = false {
    didSet { if !enabled { hide() } }
  }

  private var covers: [UIView] = []

  func observe() {
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      self?.show(in: note.object as? UIWindowScene)
    }
    center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.hide()
    }
  }

  private func show(in scene: UIWindowScene?) {
    guard enabled, covers.isEmpty, let scene = scene else { return }
    for window in scene.windows where !window.isHidden {
      let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
      cover.frame = window.bounds
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
      icon.tintColor = .secondaryLabel
      icon.translatesAutoresizingMaskIntoConstraints = false
      cover.contentView.addSubview(icon)
      NSLayoutConstraint.activate([
        icon.centerXAnchor.constraint(equalTo: cover.contentView.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: cover.contentView.centerYAnchor),
        icon.widthAnchor.constraint(equalToConstant: 44),
        icon.heightAnchor.constraint(equalToConstant: 52),
      ])
      window.addSubview(cover)
      covers.append(cover)
    }
  }

  private func hide() {
    covers.forEach { $0.removeFromSuperview() }
    covers.removeAll()
  }
}
