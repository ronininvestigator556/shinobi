// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import WebKit

/// Owns the WebKit session behind each identity.
///
/// This is where compartmentalisation is actually enforced. Every identity gets its own
/// `WKWebsiteDataStore(forIdentifier:)`, which gives it a separate on-disk directory under
/// `~/Library/WebKit/WebsiteDataStore/<uuid>` holding its own cookies, local storage,
/// IndexedDB and cache. The separation is WebKit's, not Shinobi's — there is no code path in
/// this app that could leak a cookie from one identity to another, because the two never
/// share a store to leak through.
///
/// Stores are cached and retained for the life of the app. Recreating a data store for an
/// identifier that already has live web views attached is not safe, and letting one
/// deallocate while a tab still holds a view built from it is worse.
@MainActor
public final class IdentitySessionProvider {

    private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    private var ruleLists: [BlockingLevel: WKContentRuleList] = [:]

    /// One content controller per identity, shared by every tab in it.
    ///
    /// Shared rather than per-tab so that a rule list arriving later can be applied to tabs
    /// that already exist. Filter lists take seconds to compile and the first tab is created
    /// long before that finishes; attaching rules only at configuration-build time meant the
    /// window a user actually starts browsing in was never protected, while the interface
    /// reported tens of thousands of active rules.
    private var contentControllers: [UUID: WKUserContentController] = [:]
    private var containersByID: [UUID: Identity] = [:]

    public init() {}

    // MARK: Sessions

    /// Returns the configuration a tab in this identity must be built with.
    ///
    /// Throws rather than degrading. A identity whose proxy is configured but unusable must
    /// not quietly fall back to the machine's own connection — that failure mode is
    /// precisely the disclosure the identity exists to prevent, and it would be invisible
    /// to the investigator until they were already browsing a subject's site from their
    /// home address.
    public func configuration(for identity: Identity) throws -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = try dataStore(for: identity)
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.userContentController = contentController(for: identity)
        identity.security.apply(to: configuration)
        return configuration
    }

    private func contentController(for identity: Identity) -> WKUserContentController {
        if let existing = contentControllers[identity.id] { return existing }

        let controller = WKUserContentController()
        if let ruleList = ruleLists[identity.blocking] {
            controller.add(ruleList)
        }
        if let timezone = identity.timezone {
            controller.addUserScript(Self.timezoneShim(identifier: timezone))
        }

        contentControllers[identity.id] = controller
        containersByID[identity.id] = identity
        return controller
    }

    private func dataStore(for identity: Identity) throws -> WKWebsiteDataStore {
        if let existing = dataStores[identity.id] { return existing }

        // Checked before the call, not after: WebKit signals a bad identifier with an
        // Objective-C exception, which no Swift `catch` can intercept.
        try WebSessionIdentifier.validate(identity.id)

        let store = WKWebsiteDataStore(forIdentifier: identity.id)
        try applyProxy(from: identity, to: store)
        dataStores[identity.id] = store
        return store
    }

    private func applyProxy(from identity: Identity, to store: WKWebsiteDataStore) throws {
        guard let spec = identity.proxy else {
            store.proxyConfigurations = []
            return
        }

        let password = spec.requiresPassword
            ? ProxyCredentialStore.password(forContainer: identity.id)
            : nil

        if spec.requiresPassword, password == nil {
            throw SessionError.missingProxyCredential(identity: identity.name)
        }

        guard let configuration = spec.makeProxyConfiguration(password: password) else {
            throw SessionError.invalidProxy(identity: identity.name, detail: spec.displayLabel)
        }

        // Apple's guidance is to finish setting proxies before any load begins on the store;
        // changing them later interrupts in-flight networking. Doing it at store-creation
        // time, before any web view exists, satisfies that by construction.
        store.proxyConfigurations = [configuration]
    }

    /// Re-applies a identity's proxy after its settings were edited.
    ///
    /// Existing tabs in the identity keep their web views, and pick the new egress up on
    /// their next load.
    public func refreshProxy(for identity: Identity) throws {
        guard let store = dataStores[identity.id] else { return }
        try applyProxy(from: identity, to: store)
    }

    /// Tears down a identity's session and erases its data from disk.
    public func destroySession(for identity: Identity) async {
        dataStores.removeValue(forKey: identity.id)
        contentControllers.removeValue(forKey: identity.id)
        containersByID.removeValue(forKey: identity.id)
        try? await WKWebsiteDataStore.remove(forIdentifier: identity.id)
    }

    // MARK: Content blocking

    /// Installs a compiled rule list for a blocking level.
    ///
    /// Applied immediately to every identity already using that level, so tabs open at the
    /// time start blocking without needing a reload, as well as to sessions built later.
    public func setRuleList(_ ruleList: WKContentRuleList?, for level: BlockingLevel) {
        ruleLists[level] = ruleList

        for (id, identity) in containersByID where identity.blocking == level {
            guard let controller = contentControllers[id] else { continue }
            controller.removeAllContentRuleLists()
            if let ruleList { controller.add(ruleList) }
        }
    }

    /// Re-applies a identity's blocking level after its settings were edited.
    public func refreshBlocking(for identity: Identity) {
        containersByID[identity.id] = identity
        guard let controller = contentControllers[identity.id] else { return }
        controller.removeAllContentRuleLists()
        if let ruleList = ruleLists[identity.blocking] { controller.add(ruleList) }
    }

    // MARK: Timezone

    /// A shim that makes page scripts report the identity's timezone.
    ///
    /// Covers the two things that virtually every real-world geo check reads:
    /// `Intl.DateTimeFormat().resolvedOptions().timeZone` and `Date.getTimezoneOffset()`.
    /// It does not, and cannot, cover everything — the engine's own formatting paths remain
    /// observable, and a determined fingerprinter will find the seam. It earns its place by
    /// defeating the casual check, which is the check that is actually performed.
    private static func timezoneShim(identifier: String) -> WKUserScript {
        let escaped = identifier.replacingOccurrences(of: "'", with: "")
        let source = """
        (function () {
            const zone = '\(escaped)';
            const NativeDateTimeFormat = Intl.DateTimeFormat;

            const offsetMinutes = (date) => {
                const parts = new NativeDateTimeFormat('en-US', {
                    timeZone: zone, hour12: false,
                    year: 'numeric', month: '2-digit', day: '2-digit',
                    hour: '2-digit', minute: '2-digit', second: '2-digit'
                }).formatToParts(date).reduce((all, part) => {
                    all[part.type] = part.value;
                    return all;
                }, {});
                const asIfUTC = Date.UTC(
                    Number(parts.year), Number(parts.month) - 1, Number(parts.day),
                    Number(parts.hour) % 24, Number(parts.minute), Number(parts.second)
                );
                // getTimezoneOffset is minutes *behind* UTC, hence the sign.
                return -Math.round((asIfUTC - date.getTime()) / 60000);
            };

            const nativeResolvedOptions = NativeDateTimeFormat.prototype.resolvedOptions;
            NativeDateTimeFormat.prototype.resolvedOptions = function () {
                const options = nativeResolvedOptions.call(this);
                options.timeZone = zone;
                return options;
            };

            Date.prototype.getTimezoneOffset = function () {
                return offsetMinutes(this);
            };
        })();
        """

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false      // subframes fingerprint too
        )
    }

    // MARK: Errors

    public enum SessionError: Error, LocalizedError {
        case invalidProxy(identity: String, detail: String)
        case missingProxyCredential(identity: String)

        public var errorDescription: String? {
            switch self {
            case .invalidProxy(let identity, let detail):
                "“\(identity)” has an unusable proxy (\(detail)). No pages were loaded, "
                + "because loading them would have used your own connection."
            case .missingProxyCredential(let identity):
                "“\(identity)” has a proxy username but no saved password. No pages were "
                + "loaded, because loading them would have used your own connection."
            }
        }
    }
}
