// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import IdentityKit
import ShinobiKit
import SwiftUI

/// Editable state for one identity, including the password, which the `Identity` model
/// itself deliberately cannot hold.
struct IdentityDraft {
    var name: String
    var color: IdentityColor
    var useProxy: Bool
    var proxyKind: ProxySpec.Kind
    var proxyHost: String
    var proxyPort: String
    var proxyUsername: String
    var proxyPassword: String
    var userAgent: UserAgentProfile
    var customUserAgent: String
    var overrideTimezone: Bool
    var timezone: String
    var blocking: BlockingLevel
    var security: SecurityPolicy

    let id: UUID
    let isPersonal: Bool
    let createdAt: Date

    init(identity: Identity, password: String?) {
        id = identity.id
        isPersonal = identity.isPersonal
        createdAt = identity.createdAt
        name = identity.name
        color = identity.color
        useProxy = identity.proxy != nil
        proxyKind = identity.proxy?.kind ?? .socks5
        proxyHost = identity.proxy?.host ?? ""
        proxyPort = identity.proxy.map { String($0.port) } ?? ""
        proxyUsername = identity.proxy?.username ?? ""
        proxyPassword = password ?? ""
        userAgent = identity.userAgent
        customUserAgent = identity.userAgent.stringValue ?? ""
        overrideTimezone = identity.timezone != nil
        timezone = identity.timezone ?? TimeZone.current.identifier
        blocking = identity.blocking
        security = identity.security
    }

    /// Whether the draft describes something that can actually be saved.
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the identity a name." }
        guard useProxy else { return nil }
        if proxyHost.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the proxy host." }
        guard let port = UInt16(proxyPort), port > 0 else { return "Enter a port between 1 and 65535." }
        if !proxyUsername.isEmpty && proxyPassword.isEmpty {
            // Saving a username with no password would produce a identity that refuses to
            // load anything — better to catch it here than at the first navigation.
            return "This proxy has a username, so it needs a password."
        }
        return nil
    }

    func build() -> (identity: Identity, password: String?) {
        let proxy: ProxySpec? = useProxy
            ? ProxySpec(
                kind: proxyKind,
                host: proxyHost.trimmingCharacters(in: .whitespaces),
                port: UInt16(proxyPort) ?? 0,
                username: proxyUsername.isEmpty ? nil : proxyUsername
            )
            : nil

        let agent: UserAgentProfile = {
            if case .custom = userAgent { return .custom(customUserAgent) }
            return userAgent
        }()

        let identity = Identity(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            color: color,
            proxy: proxy,
            userAgent: agent,
            timezone: overrideTimezone ? timezone : nil,
            blocking: blocking,
            security: security,
            createdAt: createdAt
        )
        return (identity, proxyPassword.isEmpty ? nil : proxyPassword)
    }
}

struct IdentityEditorView: View {

    @State var draft: IdentityDraft
    let isNew: Bool
    let onSave: (Identity, String?) -> Void
    let onCancel: () -> Void

    private var timezones: [String] { TimeZone.knownTimeZoneIdentifiers.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Identity") {
                    TextField("Name", text: $draft.name)
                    Picker("Colour", selection: $draft.color) {
                        ForEach(IdentityColor.allCases, id: \.self) { color in
                            Label {
                                Text(color.rawValue.capitalized)
                            } icon: {
                                Circle().fill(Color(Palette.color(for: color)))
                            }
                            .tag(color)
                        }
                    }
                }

                Section("Egress") {
                    Toggle("Route through a proxy", isOn: $draft.useProxy)
                    if draft.useProxy {
                        Picker("Type", selection: $draft.proxyKind) {
                            ForEach(ProxySpec.Kind.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        TextField("Host", text: $draft.proxyHost, prompt: Text("127.0.0.1"))
                        TextField("Port", text: $draft.proxyPort, prompt: Text("9050"))
                        TextField("Username (optional)", text: $draft.proxyUsername)
                        SecureField("Password", text: $draft.proxyPassword)
                        Text("The password is stored in your Keychain, not in Shinobi's configuration file.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !draft.isPersonal {
                        Text("Without a proxy this identity browses from your own address.")
                            .font(.caption)
                            .foregroundStyle(Color(Palette.statusWarn))
                    }
                }

                Section("Fingerprint") {
                    Picker("User agent", selection: userAgentSelection) {
                        ForEach(UserAgentProfile.presets, id: \.name) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                        Text("Custom…").tag("custom")
                    }
                    if case .custom = draft.userAgent,
                       !UserAgentProfile.presets.contains(where: { $0.profile == draft.userAgent }) {
                        TextField("User agent string", text: $draft.customUserAgent, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    Toggle("Report a different timezone", isOn: $draft.overrideTimezone)
                    if draft.overrideTimezone {
                        Picker("Timezone", selection: $draft.timezone) {
                            ForEach(timezones, id: \.self) { Text($0).tag($0) }
                        }
                        Text("Best effort. This covers the checks most sites perform, but a "
                             + "determined fingerprinter can still detect the real timezone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Content") {
                    Picker("Blocking", selection: $draft.blocking) {
                        ForEach(BlockingLevel.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                Section("Security") {
                    Picker("Level", selection: securityPreset) {
                        ForEach(SecurityPolicy.Preset.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    Text(draft.security.preset.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if draft.security.preset == .custom {
                        Toggle("Allow JavaScript", isOn: customBinding(\.allowsJavaScript))
                        Picker("Engine restriction", selection: customBinding(\.engineRestriction)) {
                            ForEach(SecurityPolicy.EngineRestriction.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        Picker("HTTPS", selection: customBinding(\.httpsUpgrade)) {
                            ForEach(SecurityPolicy.HTTPSUpgrade.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        Toggle("Require a click to play media", isOn: customBinding(\.requiresUserActionForMedia))
                    }

                    Toggle("Fraudulent site warning", isOn: customBinding(\.fraudulentSiteWarning))
                    if draft.security.fraudulentSiteWarning && !draft.isPersonal {
                        // The one setting in this pane that leaks rather than protects.
                        Text("This checks each site against a third-party service, so "
                             + "visiting a subject's site can disclose that visit to someone "
                             + "other than the site. Consider turning it off for a working "
                             + "identity.")
                            .font(.caption)
                            .foregroundStyle(Color(Palette.statusWarn))
                    }

                    ForEach(draft.security.caveats, id: \.self) { caveat in
                        Text(caveat).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if let error = draft.validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(Palette.statusWarn))
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    let built = draft.build()
                    onSave(built.identity, built.password)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationError != nil)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
    }

    /// Selecting a preset replaces every switch it governs, so the label always describes
    /// what is actually on.
    private var securityPreset: Binding<SecurityPolicy.Preset> {
        Binding(
            get: { draft.security.preset },
            set: { preset in
                guard preset != .custom else {
                    draft.security.preset = .custom
                    return
                }
                draft.security = SecurityPolicy.policy(
                    for: preset,
                    fraudulentSiteWarning: draft.security.fraudulentSiteWarning
                )
            }
        )
    }

    /// Changing any individual switch moves the policy to Custom, so a identity never claims
    /// to be "Hardened" while running something else.
    private func customBinding<Value>(
        _ path: WritableKeyPath<SecurityPolicy, Value>
    ) -> Binding<Value> {
        Binding(
            get: { draft.security[keyPath: path] },
            set: { newValue in
                draft.security[keyPath: path] = newValue
                if !draft.security.matchesPreset { draft.security.preset = .custom }
            }
        )
    }

    /// Bridges the preset picker to the `UserAgentProfile` enum, which carries an
    /// associated value and so cannot be a `Picker` tag directly.
    private var userAgentSelection: Binding<String> {
        Binding(
            get: {
                UserAgentProfile.presets.first { $0.profile == draft.userAgent }?.name ?? "custom"
            },
            set: { name in
                if let preset = UserAgentProfile.presets.first(where: { $0.name == name }) {
                    draft.userAgent = preset.profile
                    draft.customUserAgent = preset.profile.stringValue ?? ""
                } else {
                    draft.userAgent = .custom(draft.customUserAgent)
                }
            }
        )
    }
}
