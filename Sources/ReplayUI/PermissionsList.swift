import ReplayCore
import SwiftUI

/// The permission rows, shared by the welcome screen and Settings ▸ Privacy.
///
/// One view in both places because they are the same question asked at two moments, and two
/// copies would drift — the welcome screen's version already said something Settings did not.
///
/// **The tone is the design.** Nothing here is required, so a row that is off shows nothing
/// alarming: no red, no warning triangle, no "action needed". The healthy state of this app is
/// every row off, and a checklist that pushes toward switches would be lying about what Replay
/// needs in order to look reassuringly thorough.
struct PermissionsList: View {
    let permissions: PermissionsModel
    /// The welcome screen has less room and no Settings window to send anyone to.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Design.Space.snug : Design.Space.row) {
            ForEach(permissions.permissions) { permission in
                row(permission)
            }
            if let error = permissions.errorMessage {
                Text(error)
                    .font(Design.Text.micro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func row(_ permission: PermissionsModel.Permission) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.inline) {
            Image(systemName: glyph(for: permission))
                .foregroundStyle(tint(for: permission))
                .frame(width: Design.Icon.listItem)

            VStack(alignment: .leading, spacing: 1) {
                Text(permission.kind.label).font(Design.Text.itemTitle)
                Text(state(for: permission))
                    .font(Design.Text.micro)
                    .foregroundStyle(.secondary)
                if !compact {
                    Text(permission.kind.explanation)
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Design.Space.inline)

            // **Both directions, always.** The first version showed `Reset` on a granted row
            // and nothing else, which quietly made this a one-way door: having taken a
            // permission back there was no way to look at the pane again from here, and
            // granting-then-resetting-then-granting is exactly the loop somebody debugging a
            // managed Mac needs. Every row now offers a way in and, when there is something to
            // undo, a way out.
            HStack(spacing: Design.Space.tight) {
                // `Add to List` only for Accessibility — the one macOS will prompt for. Beside
                // App Management it would be a button that does nothing, which is worse than
                // no button, so that row gets the plain pane link.
                if permission.kind == .accessibility, permission.granted != true {
                    Button(Loc.t("Add to List")) {
                        permissions.requestAccessibility()
                        permissions.open(permission.kind)
                    }
                    .help(Loc.t("Puts Replay in the list so you only have to turn it on"))
                } else {
                    Button(Loc.t("Open")) { permissions.open(permission.kind) }
                        .help(Loc.t("Opens this pane in System Settings"))
                }
                // Offered when it is granted — and also when macOS will not say. App
                // Management cannot be read, so hiding `Reset` unless `granted == true` meant
                // the one permission nobody can check was also the one nobody could take back.
                // `tccutil` succeeds against an entry that is not there, so the button is
                // harmless when there was nothing to undo and essential when there was.
                if permission.granted != false {
                    Button(Loc.t("Reset")) { permissions.reset(permission.kind) }
                        .help(Loc.t("Removes Replay from this list, so it can be added again"))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// A granted permission is not an error and not an achievement — it is simply on, and a
    /// filled circle says so without praising or scolding it. Unknown gets a dash rather than
    /// a question mark: a question mark reads as a problem, a dash reads as "not something we
    /// can tell you", which is the truth.
    private func glyph(for permission: PermissionsModel.Permission) -> String {
        guard let granted = permission.granted else { return "minus" }
        return granted ? "circle.fill" : "circle"
    }

    private func tint(for permission: PermissionsModel.Permission) -> Color {
        permission.granted == true ? Design.Colour.assurance : .secondary
    }

    private func state(for permission: PermissionsModel.Permission) -> String {
        guard let granted = permission.granted else {
            return Loc.t("macOS does not let an app read this one")
        }
        return granted
            ? Loc.t("Granted — not needed, and safe to remove")
            : Loc.t("Off, which is all Replay needs")
    }
}

#if DEBUG
#Preview("Permissions") {
    PermissionsList(permissions: PermissionsModel())
        .padding(Design.Space.section)
        .frame(width: Design.Layout.previewWidth)
}
#endif
