//
//  Language.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import Cocoa

enum Language: String, CaseIterable, Identifiable, Codable {
    case system = "Follow System"
    case english = "English"
    case french = "French"
    case spanish = "Spanish"

    var id: String { rawValue }

    var localized: String {
        NSLocalizedString(rawValue, comment: "")
    }

    func apply() {
        let languageCode: String?
        let local = Calendar.autoupdatingCurrent.locale?.identifier
        let region = local?.split(separator: "@").last?.split(separator: "_").last

        switch self {
        case .system:
            if region == "FR" {
                languageCode = "fr"
            } else if region == "ES" {
                languageCode = "es"
            } else {
                languageCode = "en"
            }
        case .english:
            languageCode = "en"
        case .french:
            languageCode = "fr"
        case .spanish:
            languageCode = "es"
        }

        Bundle.setLanguage(languageCode)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSAlert.popRestart(
                NSLocalizedString("The language has been changed. The app will restart for the changes to take effect.", comment: ""),
                completion: restartApp
            )
        }
    }
}


private func restartApp() {
    guard let appPath = Bundle.main.executablePath else { return }
    NSApp.terminate(nil)

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: appPath)
        try? process.run()
        exit(0)
    }
}

private extension Bundle {
    private static var onLanguageDispatchOnce: () -> Void = {
        object_setClass(Bundle.main, PrivateBundle.self)
    }

    static func setLanguage(_ language: String?) {
        onLanguageDispatchOnce()

        if let language {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

private class PrivateBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let languageCode = languages.first,
              let bundlePath = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: bundlePath)
        else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}
