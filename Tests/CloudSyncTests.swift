import Foundation

@main
struct CloudSyncTests {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = t0.addingTimeInterval(60)
        let t2 = t0.addingTimeInterval(120)
        let fields = Data([1])
        let tag = "tag"
        let all: (String) -> Bool = { _ in true }
        func name(for key: String) -> String { SyncSourceID.notes.recordName(for: key) }

        // MARK: Record names

        let groceries = SyncSourceID.notes.recordName(for: "Groceries.md")
        check("a record name is stable", groceries == SyncSourceID.notes.recordName(for: "Groceries.md"))
        check("a record name never carries the key", !groceries.contains("Groceries"))
        check("a record name names its source", SyncSourceID(recordName: groceries) == .notes)
        check(
            "two sources never share a record name",
            groceries != SyncSourceID.snippets.recordName(for: "Groceries.md"))

        // MARK: Categories

        check(
            "only the clipboard waits for a Mac to opt in",
            SyncCategory.allCases.filter(\.isOptIn) == [.clipboardText, .clipboardImages])
        check(
            "each clipboard source speaks for its own category",
            SyncSourceID.clipboardText.category(of: "k") == .clipboardText
                && SyncSourceID.clipboardImages.category(of: "k") == .clipboardImages)

        // MARK: Local changes

        var ledger = SyncLedger()
        ledger.join([.notes])
        var changes = ledger.record(["a.md": "v1"], of: .notes, now: t0, includes: all)
        check("a new local item queues a save", changes == [name(for: "a.md"): .save])

        changes = ledger.record(["a.md": "v1"], of: .notes, now: t1, includes: all)
        check("an unchanged snapshot queues nothing", changes.isEmpty)

        changes = ledger.record([:], of: .notes, now: t1, includes: all)
        check("deleting an item never uploaded queues nothing", changes.isEmpty)
        check("and forgets it", ledger.entry(named: name(for: "a.md")) == nil)

        _ = ledger.record(["b.md": "v1"], of: .notes, now: t0, includes: all)
        let b = name(for: "b.md")
        _ = ledger.willSend(b)
        ledger.didSave(b, systemFields: fields, changeTag: tag)
        check("a confirmed save clears the pending upload", ledger.entry(named: b)?.pending == nil)

        changes = ledger.record([:], of: .notes, now: t1, includes: all)
        check("deleting an uploaded item queues a delete", changes == [b: .delete])
        ledger.didDelete(b)
        check("a confirmed delete forgets the item", ledger.entry(named: b) == nil)

        // MARK: A save overtaken by a newer edit

        _ = ledger.record(["c.md": "v1"], of: .notes, now: t0, includes: all)
        let c = name(for: "c.md")
        _ = ledger.willSend(c)
        _ = ledger.record(["c.md": "v2"], of: .notes, now: t1, includes: all)
        ledger.didSave(c, systemFields: fields, changeTag: tag)
        check(
            "a save confirmed after a newer edit keeps that edit pending",
            ledger.entry(named: c)?.pending == .save)

        // MARK: Unavailable and excluded items are never deleted

        var paused = SyncLedger()
        paused.join([.otherSettings])
        let setting = SyncSourceID.settings.recordName(for: "emoji.gridColumns")
        _ = paused.receive(
            setting, source: .settings, key: "emoji.gridColumns", modifiedAt: t0, changeTag: tag,
            systemFields: fields)
        paused.didApply(setting, localVersion: nil)
        changes = paused.record([:], of: .settings, now: t1, includes: all)
        check("an item this Mac never held is never deleted by a snapshot", changes.isEmpty)

        _ = paused.record(["emoji.skinTone": "v1"], of: .settings, now: t0, includes: all)
        changes = paused.record([:], of: .settings, now: t1, includes: { $0 != "emoji.skinTone" })
        check("an excluded key is never deleted", changes.isEmpty)

        let clip = SyncSourceID.clipboardText.recordName(for: "clip")
        let otherClip = SyncSourceID.clipboardText.recordName(for: "other")
        var retry = SyncLedger()
        changes = retry.record(
            ["clip": "v1", "other": "v1"], of: .clipboardText, now: t0, isDeferred: { $0 == clip },
            includes: all)
        check("a deferred remote deletion cannot re-upload the clip", changes == [otherClip: .save])
        _ = retry.record(["clip": "v1"], of: .clipboardText, now: t1, includes: all)
        _ = retry.willSend(clip)
        retry.didSave(clip, systemFields: fields, changeTag: tag)
        changes = retry.record(
            [:], of: .clipboardText, now: t2, isDeferred: { $0 == clip }, includes: all)
        check("a deferred remote arrival cannot become a local deletion", changes.isEmpty)
        check("a deferred key keeps its recorded version", retry.entry(named: clip)?.version == "v1")

        // MARK: Last write wins

        var lww = SyncLedger()
        lww.join([.notes])
        let d = name(for: "d.md")
        _ = lww.record(["d.md": "local"], of: .notes, now: t2, includes: all)
        check(
            "a newer local edit beats an older server copy",
            lww.receive(d, source: .notes, key: "d.md", modifiedAt: t1, changeTag: tag, systemFields: fields)
                == .keepLocal)
        check("and stays pending", lww.entry(named: d)?.pending == .save)
        check(
            "a newer server copy beats an older local edit",
            lww.receive(
                d, source: .notes, key: "d.md", modifiedAt: t2.addingTimeInterval(1), changeTag: tag,
                systemFields: fields)
                == .apply)
        check("and drops the local upload", lww.entry(named: d)?.pending == nil)

        let e = name(for: "e.md")
        _ = lww.record(["e.md": "local"], of: .notes, now: t1, includes: all)
        check(
            "a tie goes to the server",
            lww.receive(e, source: .notes, key: "e.md", modifiedAt: t1, changeTag: tag, systemFields: fields)
                == .apply)

        // MARK: Echo-free apply

        lww.didApply(e, localVersion: "reread")
        changes = lww.record(["e.md": "reread"], of: .notes, now: t2, includes: all)
        check("an applied change never uploads again", changes.isEmpty)

        // MARK: Re-fetch

        var refetch = SyncLedger()
        refetch.join([.notes])
        let r = name(for: "r.md")
        _ = refetch.record(["r.md": "v1"], of: .notes, now: t0, includes: all)
        _ = refetch.willSend(r)
        refetch.didSave(r, systemFields: fields, changeTag: "saved")
        check(
            "a re-fetch of the version this Mac saved is skipped",
            refetch.receive(
                r, source: .notes, key: "r.md", modifiedAt: t0, changeTag: "saved", systemFields: fields)
                == .unchanged)
        check(
            "a newer server version applies",
            refetch.receive(
                r, source: .notes, key: "r.md", modifiedAt: t1, changeTag: "newer", systemFields: fields)
                == .apply)
        _ = refetch.record(["r.md": "v2"], of: .notes, now: t2, includes: all)
        check(
            "an edit not yet uploaded is never skipped",
            refetch.receive(
                r, source: .notes, key: "r.md", modifiedAt: t1, changeTag: "newer", systemFields: fields)
                == .keepLocal)

        // MARK: Deletions

        let f = name(for: "f.md")
        _ = lww.record(["f.md": "v1"], of: .notes, now: t1, includes: all)
        check("an edit not yet uploaded outlives a remote delete", lww.receiveDeletion(f) == .keepLocal)
        check("and saves as a new record", lww.entry(named: f)?.systemFields == nil)

        _ = lww.willSend(f)
        lww.didSave(f, systemFields: fields, changeTag: tag)
        if case .apply(let entry) = lww.receiveDeletion(f) {
            check("a remote delete of a settled item applies", entry.key == "f.md")
        } else {
            check("a remote delete of a settled item applies", false)
        }
        check("an unknown record's deletion is ignored", lww.receiveDeletion("notes.nothing") == .ignore)

        // MARK: Categories

        var categories = SyncLedger()
        _ = categories.receive(
            groceries, source: .notes, key: "Groceries.md", modifiedAt: t0, changeTag: tag,
            systemFields: fields)
        categories.join([.notes])
        categories.forget(.notes)
        check("forgetting a category drops its items", categories.entry(named: groceries) == nil)
        check("and leaves it to merge again", !categories.isJoined(.notes, key: "x.md"))

        var counted = SyncLedger()
        let g = name(for: "g.md")
        _ = counted.receive(
            g, source: .notes, key: "g.md", modifiedAt: t0, changeTag: tag, systemFields: fields)
        counted.didApply(g, localVersion: "v1")
        _ = counted.record(["g.md": "v1", "h.md": "v1"], of: .notes, now: t0, includes: all)
        check("counts tell this Mac from iCloud", counted.counts(of: .notes) == (2, 1) as (Int, Int))

        // MARK: Setting scope

        let enabledKeys = SettingsFileKey.allCases.filter {
            $0.name == "enabled" || $0.name == "builtInEnabled"
        }
        let syncedSwitches = enabledKeys.filter { SyncSettingScope.category(of: $0) != nil }
        check("every feature switch stays on its Mac — \(syncedSwitches)", syncedSwitches.isEmpty)
        let local: [SettingsFileKey] = [
            .language, .notesFolder, .snippetsFolder, .dictationModel, .dictationMicrophone,
            .fileSearchScopes, .searchScopes
        ]
        check(
            "folders, scopes, language and devices stay on their Mac",
            local.allSatisfy { SyncSettingScope.category(of: $0) == nil })
        check(
            "Open at Login has its own category",
            SyncSettingScope.category(of: SyncSettingScope.launchAtLoginKey) == .launchAtLogin)
        check("an unknown key belongs to nothing", SyncSettingScope.category(of: "future.key") == nil)
        check(
            "window layouts travel together",
            [.customWindowSizes, .windowLayouts, .windowRooms].allSatisfy {
                SyncSettingScope.category(of: $0) == .windowLayouts
            })

        // MARK: Entry keys

        let keys = SyncEntryKey(
            snippetFolder: URL(filePath: "/Users/a/Snippets", directoryHint: .isDirectory),
            homeDirectory: URL(filePath: "/Users/a", directoryHint: .isDirectory))
        let other = SyncEntryKey(
            snippetFolder: URL(filePath: "/Users/b/Dropbox/Snippets", directoryHint: .isDirectory),
            homeDirectory: URL(filePath: "/Users/b", directoryHint: .isDirectory))
        let snippet = keys.portable("snippet:/Users/a/Snippets/greeting.md")
        check("a snippet key drops its folder", snippet == "snippet:greeting.md")
        check(
            "and lands in the other Mac's folder",
            other.local(snippet) == "snippet:/Users/b/Dropbox/Snippets/greeting.md")
        let file = keys.portable("file:///Users/a/Documents/Plan%20B.pdf")
        check("a home file drops its home", file == "file:~/Documents/Plan%20B.pdf")
        check("and lands in the other home", other.local(file) == "file:///Users/b/Documents/Plan%20B.pdf")
        check("a bundle ID passes through", keys.portable("com.apple.Safari") == "com.apple.Safari")
        check(
            "a snippet outside the folder keeps its path",
            keys.portable("snippet:/Elsewhere/x.md") == "snippet:/Elsewhere/x.md")

        // MARK: Devices

        let seen = SyncDevice.seen(at: Date(timeIntervalSinceReferenceDate: 7_250))
        check("a device's last-seen rounds to the hour", seen == Date(timeIntervalSinceReferenceDate: 7_200))

        print(failures == 0 ? "\nAll CloudSync checks passed." : "\n\(failures) CloudSync check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
