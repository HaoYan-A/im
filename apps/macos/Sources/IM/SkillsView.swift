import AppKit
import Combine
import IMCore
import SwiftUI

@MainActor
final class SkillsWindowController: NSObject, NSWindowDelegate {
    let model: SkillsViewModel
    private let window: NSWindow
    private let onClose: () -> Void
    private var languageSubscription: AnyCancellable?

    init(appState: AppState, preferences: Preferences, onClose: @escaping () -> Void) {
        model = SkillsViewModel(appState: appState)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingController(rootView: SkillsView(model: model, preferences: preferences))
        // Let the user size the window; by default the hosting controller pins it to the content's ideal size.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 420)
        window.setContentSize(NSSize(width: 720, height: 560))
        window.setFrameAutosaveName("im.skills")
        self.onClose = onClose
        super.init()
        window.delegate = self
        model.close = { [weak window] in window?.close() }
        languageSubscription = preferences.$language.sink { [weak window] _ in
            window?.title = L("Skills", "Skills")
        }
    }

    func show() {
        if !window.isVisible, !window.setFrameUsingName("im.skills") { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

/// Column widths shared by the header and every row, so the agent columns line up.
private enum Column {
    static let check: CGFloat = 18
    static let agent: CGFloat = 96
    static let trailing: CGFloat = 24
    static let spacing: CGFloat = 12
    static let inset: CGFloat = 20
}

struct SkillsView: View {
    @ObservedObject var model: SkillsViewModel
    @ObservedObject var preferences: Preferences

    private var accent: Color { Color(nsColor: preferences.cat.accentColor) }
    /// Darker, so white button text stays readable on light cat colors.
    private var strongAccent: Color { Color(nsColor: preferences.cat.accentColor.blended(withFraction: 0.22, of: .black) ?? .controlAccentColor) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let warning = model.syncWarning {
                Label(warning, systemImage: "icloud.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Column.inset)
                    .padding(.bottom, 10)
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(accent)
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        // Text comes from L(), which SwiftUI can't track; rebuild everything on a language switch.
        .id(preferences.language)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: preferences.cat.image(pointSize: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Skills", "Skills")).font(.title3.weight(.semibold))
                Text(L("Choose which skills im keeps in your repository, and which agents get them.",
                       "选择哪些 Skill 交给 im 保管，以及装到哪些 Agent。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isWorking {
                ProgressView().controlSize(.small).frame(width: 24)
            } else {
                Button { Task { await model.reload() } } label: {
                    Image(systemName: "arrow.clockwise").font(.body.weight(.medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L("Reload: sync with GitHub and scan the agents again", "重新加载：与 GitHub 同步，并重新扫描各个 Agent"))
                .frame(width: 24)
            }
        }
        .padding(.horizontal, Column.inset)
        .padding(.vertical, 16)
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if !model.hasScanned {
            ProgressView()
        } else if model.skills.isEmpty {
            VStack(spacing: 10) {
                Image(nsImage: preferences.cat.image(blinking: true, pointSize: 3))
                Text(L("No personal skills in Claude Code or Codex yet.", "Claude Code 和 Codex 里还没有个人 Skill。"))
                    .font(.headline)
                Text(L("Skills you add to ~/.claude/skills or ~/.agents/skills show up here when you reload.",
                       "放进 ~/.claude/skills 或 ~/.agents/skills 的 Skill，重新加载后就会出现在这里。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        } else {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if !model.unlinked.isEmpty {
                            Section {
                                rows(model.unlinked)
                            } header: {
                                sectionHeader(L("Not linked", "未关联"), count: model.unlinked.count)
                            }
                        }
                        if !model.linked.isEmpty {
                            Section {
                                rows(model.linked)
                            } header: {
                                sectionHeader(L("Linked", "已关联"), count: model.linked.count)
                            }
                        }
                    }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Column.spacing) {
            if model.unlinked.isEmpty {
                Color.clear.frame(width: Column.check, height: 1)
            } else {
                Button { model.selectAll(model.selectionState != true) } label: {
                    Image(systemName: selectAllSymbol)
                    .font(.body)
                    .foregroundStyle(model.selectionState == false ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                }
                .buttonStyle(.plain)
                .frame(width: Column.check)
                .help(L("Select all or none of the skills that aren't linked", "全选或全不选未关联的 Skill"))
            }
            Text(L("Skill", "Skill")).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(SkillAgent.allCases, id: \.self) { agent in
                Text(agent.displayName).frame(width: Column.agent)
            }
            Color.clear.frame(width: Column.trailing, height: 1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Column.inset)
        .padding(.vertical, 7)
    }

    private var selectAllSymbol: String {
        switch model.selectionState {
        case true: "checkmark.square.fill"
        case false: "square"
        case nil: "minus.square.fill"
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).fontWeight(.semibold)
            Text("\(count)").foregroundStyle(.secondary)
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, Column.inset)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func rows(_ skills: [Skill]) -> some View {
        ForEach(skills) { skill in
            SkillRow(skill: skill, choice: choice(for: skill), isSkipped: model.skipped.contains(skill.name), accent: accent)
            Divider().padding(.leading, Column.inset + Column.check + Column.spacing)
        }
    }

    private func choice(for skill: Skill) -> Binding<SkillsViewModel.Choice> {
        Binding(
            get: { model.choices[skill.name] ?? .init() },
            set: { model.choices[skill.name] = $0 }
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let result = model.resultMessage {
                Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            HStack(spacing: 10) {
                Text(L("Replaced folders are moved to ~/.im/backup, never deleted.", "被替换的文件夹会移到 ~/.im/backup，不会删除。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Not Now", "暂不关联"), action: model.notNow)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Button(model.applyTitle, action: model.apply)
                    .buttonStyle(.borderedProminent)
                    .tint(strongAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges || model.isWorking)
            }
        }
        .font(.callout)
        .padding(.horizontal, Column.inset)
        .padding(.vertical, 14)
    }
}

private struct SkillRow: View {
    let skill: Skill
    @Binding var choice: SkillsViewModel.Choice
    let isSkipped: Bool
    let accent: Color

    private var isLinked: Bool { skill.state == .linked }

    var body: some View {
        HStack(alignment: .top, spacing: Column.spacing) {
            Group {
                if isLinked {
                    Color.clear.frame(height: 1)
                } else {
                    Toggle("", isOn: $choice.link).toggleStyle(.checkbox).labelsHidden()
                }
            }
            .frame(width: Column.check)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.name).font(.system(.body, design: .monospaced).weight(.medium))
                    badge
                }
                if let description = skill.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(description)
                }
                if skill.state == .differentVersions {
                    if choice.link {
                        VersionPicker(skill: skill, selection: $choice.version)
                            .padding(.top, 6)
                    } else {
                        Text(L("The copies differ. Tick it to choose which version to keep.", "各处的内容不一样，勾选后选择要保留的版本。"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(SkillAgent.allCases, id: \.self) { agent in
                AgentCell(agent: agent, skill: skill, choice: $choice, accent: accent)
                    .frame(width: Column.agent)
            }

            Group {
                if isLinked {
                    Menu {
                        Button(choice.unlink ? L("Keep Linked", "保持关联") : L("Unlink…", "取消关联…")) { choice.unlink.toggle() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .tint(.secondary)
                    .menuIndicator(.hidden)
                    .help(L("More", "更多"))
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: Column.trailing)
        }
        .padding(.horizontal, Column.inset)
        .padding(.vertical, 10)
        .opacity(choice.unlink ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: choice)
    }

    @ViewBuilder
    private var badge: some View {
        if choice.unlink {
            Badge(text: L("Will unlink", "将取消关联"), color: .secondary)
        } else if skill.state == .differentVersions {
            Badge(text: L("Different versions", "版本不同"), color: .orange)
        } else if skill.state == .onlyInIM {
            Badge(text: L("From another machine", "来自另一台电脑"), color: .secondary)
        } else if isSkipped {
            Text(L("Skipped", "已跳过")).font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// One agent column of a row. Untouched rows show where the skill is now;
/// rows being changed show where it will be, with + / − for what changes.
private struct AgentCell: View {
    let agent: SkillAgent
    let skill: Skill
    @Binding var choice: SkillsViewModel.Choice
    let accent: Color

    private var isLinked: Bool { skill.state == .linked }
    private var isEditable: Bool { isLinked ? !choice.unlink : choice.link }
    private var isHere: Bool { (isLinked ? skill.linkedAgents : skill.installedAgents).contains(agent) }
    private var willBeHere: Bool { isEditable ? choice.agents.contains(agent) : isHere }

    var body: some View {
        ZStack {
            Button {
                if willBeHere { choice.agents.remove(agent) } else { choice.agents.insert(agent) }
            } label: {
                // A quiet mark rather than a checkbox: the row's checkbox is the decision, these are its details.
                Image(systemName: willBeHere ? "checkmark" : "circle")
                    .font(willBeHere ? .body.weight(.semibold) : .caption)
                    .foregroundStyle(willBeHere ? (isEditable ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)) : AnyShapeStyle(.quaternary))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)
            .accessibilityLabel(agent.displayName)
            .accessibilityValue(willBeHere ? L("On", "开") : L("Off", "关"))

            Group {
                if isEditable, willBeHere, !isHere {
                    Image(systemName: "plus.circle.fill").foregroundStyle(accent)
                        .help(L("Will be added to \(agent.displayName)", "将新增到 \(agent.displayName)"))
                } else if isEditable, !willBeHere, isHere {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        .help(L("Will be removed from \(agent.displayName); the folder goes to the backup", "将从 \(agent.displayName) 移除，文件夹会移到备份"))
                } else {
                    Color.clear
                }
            }
            .font(.caption)
            .frame(width: 12, height: 12)
            // Beside the mark, so the mark itself stays centered under the column title.
            .offset(x: 20)
        }
        .help(isEditable ? "" : (isHere ? L("In \(agent.displayName) now", "当前在 \(agent.displayName) 中") : L("Not in \(agent.displayName)", "不在 \(agent.displayName) 中")))
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }
}

private struct VersionPicker: View {
    let skill: Skill
    @Binding var selection: SkillVersion.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Keep which version?", "保留哪个版本？")).font(.caption.weight(.semibold))
            Picker("", selection: $selection) {
                ForEach(skill.versions) { version in
                    Text(describe(version)).tag(Optional(version.id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(L("Differs in \(skill.differingFiles.joined(separator: ", ")). The other version goes to the backup.",
                   "不同的文件：\(skill.differingFiles.joined(separator: "、"))。另一个版本会移到备份。"))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.07)))
    }

    private func describe(_ version: SkillVersion) -> String {
        let owners = version.owners.map { $0?.displayName ?? "im" }.joined(separator: L(" and ", " 和 "))
        let date = version.content.modified.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: Language.current.rawValue))
        )
        return L("\(owners), edited \(date)", "\(owners)，修改于 \(date)")
    }
}
