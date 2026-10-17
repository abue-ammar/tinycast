import SwiftUI

enum ExcludedFeature {
    static func message(_ feature: String) -> String {
        "\(feature) isn't included in this build"
    }
}

struct ExcludedFeaturePane: View {
    let feature: String
    let symbol: String

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(ExcludedFeature.message(feature)).font(.headline)
                        Text("Its settings are kept and return with a full build.")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                } icon: {
                    Image(systemName: symbol)
                }
            }
        }
        .formStyle(.grouped)
    }
}
