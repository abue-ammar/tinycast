import SwiftUI

struct CloudSyncCategoryList: View {
    @Environment(AppCore.self) private var core
    let group: SyncCategory.Group

    private var sync: CloudSyncCoordinator { core.cloudSyncCoordinator }

    var body: some View {
        ForEach(SyncCategory.categories(in: group), id: \.self) { category in
            if category.isOptional {
                CloudSyncCategoryRow(
                    category: category,
                    isIncluded: Binding(
                        get: { sync.includes(category) }, set: { sync.setIncluded($0, for: category) }),
                    counts: sync.isEnabled ? sync.counts[category] : nil,
                    isSettled: sync.status.lastSynced != nil)
            } else {
                CloudSyncInfoRow(title: category.title, symbol: category.symbol, detail: category.detail)
            }
        }
    }
}
