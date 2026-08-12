import AppKit
import UserNotifications
import TheReadingRoomCore

/// Posts a Notification Center banner when files change in an open folder.
/// Clicking one brings up the file.
@MainActor
final class ChangeNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ChangeNotifier()

    /// More changes than this in one batch collapse into a single banner —
    /// a build that rewrites forty files shouldn't produce forty notifications.
    private let maximumIndividualBanners = 3

    private var authorized: Bool?
    private var isRequesting = false

    private enum Key {
        static let path = "path"
        static let root = "root"
    }

    /// Called before the app finishes launching, so the delegate is in place by
    /// the time any notification can be delivered.
    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Posting

    func notify(_ changes: [TreeChange], in folder: URL) {
        guard !changes.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            guard await self.ensureAuthorized() else {
                NSLog("[TheReadingRoom] not notifying: notifications are not authorized")
                return
            }
            await self.post(changes, in: folder)
        }
    }

    private func post(_ changes: [TreeChange], in folder: URL) async {
        let center = UNUserNotificationCenter.current()
        let folderName = folder.lastPathComponent

        if changes.count > maximumIndividualBanners {
            let content = UNMutableNotificationContent()
            content.title = "\(changes.count) files changed"
            content.subtitle = folderName
            content.body = changes.prefix(4).map(\.label).joined(separator: ", ")
                + (changes.count > 4 ? "…" : "")
            if let newest = changes.first(where: \.isOpenable) {
                content.userInfo = [Key.path: newest.url.path, Key.root: folder.path]
            }
            try? await center.add(
                UNNotificationRequest(
                    // One summary per folder, replacing any earlier summary.
                    identifier: "summary:\(folder.path)",
                    content: content,
                    trigger: nil
                )
            )
            return
        }

        for change in changes {
            let content = UNMutableNotificationContent()
            content.title = change.label
            content.subtitle = "\(change.kind.verb) in \(folderName)"
            if change.isOpenable {
                content.userInfo = [Key.path: change.url.path, Key.root: folder.path]
            }
            do {
                try await center.add(
                    UNNotificationRequest(
                        // Keyed by file, so repeated saves replace rather than stack.
                        identifier: "change:\(change.url.path)",
                        content: content,
                        trigger: nil
                    )
                )
            } catch {
                NSLog("[TheReadingRoom] could not post notification: \(error)")
            }
        }
    }

    // MARK: - Authorization

    /// Asks the first time a change is worth reporting, rather than at launch —
    /// no permission prompt for someone who never leaves a folder open.
    private func ensureAuthorized() async -> Bool {
        if let authorized { return authorized }
        guard !isRequesting else { return false }
        isRequesting = true
        defer { isRequesting = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert])
            authorized = granted
            NSLog("[TheReadingRoom] notification authorization granted: \(granted)")
            return granted
        } catch {
            // Leave `authorized` unset so a later change tries again.
            NSLog("[TheReadingRoom] notification authorization failed: \(error)")
            return false
        }
    }

    // MARK: - Delegate

    /// Show the banner even when the app is frontmost; the point is to notice a
    /// change in a file you aren't currently looking at.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let path = userInfo[Key.path] as? String else { return }
        let root = (userInfo[Key.root] as? String).map { URL(fileURLWithPath: $0) }

        await MainActor.run {
            WindowRouter.shared.reveal(file: URL(fileURLWithPath: path), preferringRoot: root)
        }
    }
}
