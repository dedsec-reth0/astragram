import Foundation
import UIKit
import TelegramCore

/// Online updates. A sideloaded app cannot replace itself: SideStore installs the update (it re-signs the IPA).
/// AyuGram checks the latest GitHub release and offers to open it in SideStore; SideStore can also follow the source
/// that CI publishes (ayugram/ci/publish_release.py) and show updates on its own.
public enum AyuUpdateChecker {
    public static let repository = "dedsec-reth0/ayugram"

    public static var sourceUrl: String {
        return "https://github.com/\(AyuUpdateChecker.repository)/releases/download/sidestore-source/source.json"
    }

    private static let lastCheckKey = "ayugram.update.lastCheck"
    private static let skippedBuildKey = "ayugram.update.skippedBuild"

    private struct Release {
        let version: String
        let build: Int
        let ipaUrl: String
        let pageUrl: String
        let notes: String
    }

    private static var isRussian: Bool {
        let language = Locale.preferredLanguages.first?.lowercased() ?? ""
        return language.hasPrefix("ru") || language.hasPrefix("uk") || language.hasPrefix("be")
    }

    private static func t(_ ru: String, _ en: String) -> String {
        return AyuUpdateChecker.isRussian ? ru : en
    }

    private static var currentBuild: Int {
        return Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    private static func fetchLatest(completion: @escaping (Release?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(AyuUpdateChecker.repository)/releases/latest") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 20.0)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            var release: Release?
            if let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let tag = object["tag_name"] as? String {
                // Tags are v<version>-<build>.
                let parts = tag.dropFirst().split(separator: "-")
                if parts.count == 2, let build = Int(parts[1]) {
                    let assets = object["assets"] as? [[String: Any]] ?? []
                    let ipaUrl = assets.compactMap { $0["browser_download_url"] as? String }.first(where: { $0.hasSuffix(".ipa") })
                    if let ipaUrl = ipaUrl {
                        release = Release(version: String(parts[0]), build: build, ipaUrl: ipaUrl, pageUrl: object["html_url"] as? String ?? "", notes: object["body"] as? String ?? "")
                    }
                }
            }
            DispatchQueue.main.async {
                completion(release)
            }
        }).resume()
    }

    private static func topViewController(_ window: UIWindow?) -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    /// Checks at launch (at most twice a day) when "Check for updates" is on.
    public static func checkOnLaunch(window: UIWindow?) {
        guard AyuGramSettings.current.checkForUpdates else {
            return
        }
        let now = Date().timeIntervalSince1970
        let lastCheck = UserDefaults.standard.double(forKey: AyuUpdateChecker.lastCheckKey)
        if now - lastCheck < 12.0 * 60.0 * 60.0 {
            return
        }
        UserDefaults.standard.set(now, forKey: AyuUpdateChecker.lastCheckKey)
        AyuUpdateChecker.fetchLatest(completion: { release in
            guard let release = release, release.build > AyuUpdateChecker.currentBuild, release.build != UserDefaults.standard.integer(forKey: AyuUpdateChecker.skippedBuildKey) else {
                return
            }
            if let controller = AyuUpdateChecker.topViewController(window) {
                AyuUpdateChecker.presentUpdate(release, from: controller, allowSkip: true)
            }
        })
    }

    /// "Check for Updates" in AyuGram settings.
    public static func checkNow(from controller: UIViewController) {
        AyuUpdateChecker.fetchLatest(completion: { release in
            if let release = release, release.build > AyuUpdateChecker.currentBuild {
                AyuUpdateChecker.presentUpdate(release, from: controller, allowSkip: false)
            } else {
                let text = release == nil ? AyuUpdateChecker.t("Не удалось проверить обновления. Проверьте подключение к интернету.", "Could not check for updates. Check your internet connection.") : AyuUpdateChecker.t("У вас последняя версия.", "You have the latest version.")
                let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                alert.addAction(UIAlertAction(title: AyuUpdateChecker.t("Добавить источник в AltStore", "Add Source to AltStore"), style: .default, handler: { _ in
                    AyuUpdateChecker.openSideStoreSource()
                }))
                controller.present(alert, animated: true)
            }
        })
    }

    private static func presentUpdate(_ release: Release, from controller: UIViewController, allowSkip: Bool) {
        var message = AyuUpdateChecker.t("Версия \(release.version) (\(release.build)). Обновление устанавливает AltStore, данные и вход сохранятся.", "Version \(release.version) (\(release.build)). AltStore installs the update; your data and login are kept.")
        let notes = release.notes.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !notes.isEmpty {
            message += "\n\n" + notes
        }
        let alert = UIAlertController(title: AyuUpdateChecker.t("Доступно обновление AstraGram", "AstraGram Update Available"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AyuUpdateChecker.t("Обновить в AltStore", "Update in AltStore"), style: .default, handler: { _ in
            AyuUpdateChecker.openSideStoreInstall(release)
        }))
        if allowSkip {
            alert.addAction(UIAlertAction(title: AyuUpdateChecker.t("Пропустить эту версию", "Skip This Version"), style: .default, handler: { _ in
                UserDefaults.standard.set(release.build, forKey: AyuUpdateChecker.skippedBuildKey)
            }))
        }
        alert.addAction(UIAlertAction(title: AyuUpdateChecker.t("Позже", "Later"), style: .cancel))
        controller.present(alert, animated: true)
    }

    private static func encoded(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// Opens the first of `urls` that an installed app handles (AltStore, then SideStore), else calls `fallback`.
    private static func openFirst(_ urls: [URL], fallback: @escaping () -> Void) {
        guard let url = urls.first else {
            fallback()
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: { success in
            if !success {
                AyuUpdateChecker.openFirst(Array(urls.dropFirst()), fallback: fallback)
            }
        })
    }

    private static func openSideStoreInstall(_ release: Release) {
        let ipaUrl = AyuUpdateChecker.encoded(release.ipaUrl)
        let urls = ["altstore://install?url=\(ipaUrl)", "sidestore://install?url=\(ipaUrl)"].compactMap(URL.init(string:))
        AyuUpdateChecker.openFirst(urls, fallback: {
            if let page = URL(string: release.pageUrl.isEmpty ? release.ipaUrl : release.pageUrl) {
                UIApplication.shared.open(page)
            }
        })
    }

    public static func openSideStoreSource() {
        let sourceUrl = AyuUpdateChecker.encoded(AyuUpdateChecker.sourceUrl)
        let urls = ["altstore://source?url=\(sourceUrl)", "sidestore://source?url=\(sourceUrl)"].compactMap(URL.init(string:))
        AyuUpdateChecker.openFirst(urls, fallback: {
            UIPasteboard.general.string = AyuUpdateChecker.sourceUrl
        })
    }
}
