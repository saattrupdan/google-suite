import Foundation
import UserNotifications
import WebKit

/// Bridges in-page `new Notification(...)` calls to native notifications.
///
/// Read this before trusting it. WebKit in a third-party app has **no** service
/// worker push: Google Calendar/Gmail deliver reminders through a service
/// worker registered against Google's push service, which `WKWebView` cannot
/// run. What *does* reach us is a notification constructed from page JS while
/// the page is open (some Gmail paths do this, e.g. hangout/chat and
/// "reminders while the window is open"). So:
///
///   * notifications while a tab is open and awake → may work
///   * reminders while the app is closed, or via Google's push → will NOT work
///
/// The reliable path for reminders is Google Calendar Settings → General →
/// Notification settings → "Email", so alerts arrive in Mail.app. Say so in the
/// README rather than pretending otherwise.
enum Notifier {
    /// Name of the script message handler the shim posts to.
    static let handlerName = "gcalNotify"

    static let installScript = """
    (() => {
      if (window.__gcalNotifyInstalled) return;
      window.__gcalNotifyInstalled = true;
      const post = (payload) => {
        try { window.webkit.messageHandlers.\(handlerName).postMessage(payload); } catch (e) {}
      };
      class GCalNotification {
        constructor(title, options) {
          options = options || {};
          this.title = String(title == null ? '' : title);
          this.body = options.body == null ? '' : String(options.body);
          this.tag = options.tag == null ? '' : String(options.tag);
          this.dir = options.dir || 'auto';
          this.lang = options.lang || '';
          this.icon = options.icon || '';
          this.silent = !!options.silent;
          this.renotify = !!options.renotify;
          this.requireInteraction = !!options.requireInteraction;
          this.timestamp = options.timestamp || Date.now();
          this.data = options.data || null;
          this.vibrate = options.vibrate || null;
          post({ title: this.title, body: this.body, tag: this.tag });
        }
        static get permission() { return 'granted'; }
        static requestPermission(success, failure) {
          if (typeof success === 'function') { try { success('granted'); } catch (e) {} }
          return Promise.resolve('granted');
        }
        close() {}
        addEventListener() {}
        removeEventListener() {}
        dispatchEvent() { return true; }
        onclick = null; onclose = null; onerror = null; onshow = null;
      }
      try {
        Object.defineProperty(window, 'Notification', {
          value: GCalNotification, writable: true, configurable: true,
        });
      } catch (e) {}
    })();
    """

    static func makeUserScript(enabled: Bool) -> WKUserScript {
        WKUserScript(
            source: enabled ? installScript : "",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page)
    }

    /// Delivers one native notification. No-ops when not running from a real
    /// app bundle (a bare executable has no bundle identifier, and
    /// `UNUserNotificationCenter` refuses to work there).
    static func deliver(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request(for: title, body: body), withCompletionHandler: nil)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { center.add(request(for: title, body: body), withCompletionHandler: nil) }
                }
            default:
                break
            }
        }
    }

    private static func request(for title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Google" : title
        content.body = body
        content.sound = .default
        return UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
    }
}

/// Receives the shim's messages. Held by the web view's user content
/// controller, so it must not own the web view.
final class NotifyHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Notifier.handlerName, let dict = message.body as? [String: Any] else { return }
        let title = (dict["title"] as? String) ?? "Google"
        let body = (dict["body"] as? String) ?? ""
        Notifier.deliver(title: title, body: body)
    }
}
