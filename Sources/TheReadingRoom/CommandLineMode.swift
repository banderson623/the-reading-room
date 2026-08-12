import Foundation
import UserNotifications
import TheReadingRoomCore

/// Flags handled before any window opens:
///
///   --render <file.md>   write a self-contained HTML page to stdout
///   --notifications      report notification permission and what's pending
enum CommandLineMode {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.contains("--notifications") {
            reportNotificationStatus()
        }
        if let flag = arguments.firstIndex(of: "--render") {
            render(arguments: arguments, flag: flag)
        }
    }

    // MARK: - Rendering

    private static func render(arguments: [String], flag: Int) -> Never {
        guard flag + 1 < arguments.count else {
            FileHandle.standardError.write(Data("usage: TheReadingRoom --render <file.md>\n".utf8))
            exit(2)
        }

        let url = URL(fileURLWithPath: arguments[flag + 1]).standardizedFileURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read \(url.path)\n".utf8))
            exit(1)
        }

        let rendered = MarkdownRenderer.render(markdown: text)
        let html = Page.standalone(
            title: url.deletingPathExtension().lastPathComponent,
            body: rendered,
            modified: DateFormatting.modificationDate(of: url),
            baseURL: url.deletingLastPathComponent()
        )
        FileHandle.standardOutput.write(Data(html.utf8))
        exit(0)
    }

    // MARK: - Notification status

    /// Answers "why am I not seeing banners?" without guesswork: whether macOS
    /// has granted permission, and what the app has already delivered.
    private static func reportNotificationStatus() -> Never {
        let center = UNUserNotificationCenter.current()
        var lines: [String] = []
        let done = DispatchSemaphore(value: 0)

        center.getNotificationSettings { settings in
            lines.append("authorization: \(describe(settings.authorizationStatus))")
            lines.append("alerts:        \(describe(settings.alertSetting))")
            lines.append("notification center: \(describe(settings.notificationCenterSetting))")

            center.getDeliveredNotifications { delivered in
                lines.append("delivered:     \(delivered.count)")
                for notification in delivered {
                    let content = notification.request.content
                    lines.append("  • \(content.title) — \(content.subtitle)")
                }
                done.signal()
            }
        }

        if done.wait(timeout: .now() + 5) == .timedOut {
            lines.append("timed out asking the notification centre")
        }
        print(lines.joined(separator: "\n"))
        exit(0)
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not asked yet"
        case .denied: return "denied — turn it on in System Settings ▸ Notifications"
        case .authorized: return "authorized"
        case .provisional: return "provisional (delivered quietly)"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "not supported"
        @unknown default: return "unknown"
        }
    }
}
