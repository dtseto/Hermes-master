import Foundation
import Testing

struct HermesInfoPlistTests {

    @Test func inputMonitoringUsageDescriptionPresent() async throws {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        var candidateURLs: [URL] = []
        if let productsDir = environment["BUILT_PRODUCTS_DIR"],
           let bundleName = environment["FULL_PRODUCT_NAME"] {
            let url = URL(fileURLWithPath: productsDir, isDirectory: true)
                .appendingPathComponent(bundleName)
            candidateURLs.append(url)
        }

        let siblingAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Hermes.app")
        candidateURLs.append(siblingAppURL)

        guard let bundleURL = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }),
              let bundle = Bundle(url: bundleURL) else {
            Issue.record("Unable to locate Hermes.app to inspect Info.plist for Input Monitoring usage description.")
            return
        }

        let description = bundle.object(forInfoDictionaryKey: "NSInputMonitoringUsageDescription") as? String
        #expect(description?.isEmpty == false, "Info.plist must define NSInputMonitoringUsageDescription.")
    }

}
