import Foundation

enum AppConfiguration {
    #if DEBUG
    static func recognitionURL(debugURL: String) throws -> String { debugURL }
    #endif
    static var privacyURL: URL? { configuredURL("PrivacyPolicyURL") }
    static var supportURL: URL? { configuredURL("SupportURL") }
    private static func configuredURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.contains("$("), let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
