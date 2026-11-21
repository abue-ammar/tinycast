import SwiftUI

struct CloudSyncCategoryList: View {
    @Environment(AppCore.self) private var core
    @Environment(MainAppLink.self) private var mainApp
    let group: SyncCategory.Group

    private var sync: CloudSyncCoordinator { core.cloudSyncCoordinator }

    var body: some View {
        ForEach(SyncCategory.categories(in: group), id: \.self) { category in
            if category.isOptional {
                CloudSyncCategoryRow(
                    category: category,
                    isIncluded: Binding(
                        get: { sync.includes(category) },
                        set: { mainApp.send(.setICloudSyncIncluded(category, $0)) }),
                    counts: sync.isEnabled ? mainApp.status.cloudSync.counts[category] : nil,
                    isSettled: mainApp.status.cloudSync.status.lastSynced != nil)
            } else {
                CloudSyncInfoRow(title: category.title, symbol: category.symbol, detail: category.detail)
            }
        }
    }
}
