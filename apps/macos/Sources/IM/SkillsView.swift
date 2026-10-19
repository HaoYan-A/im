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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 420)
        window.contentViewController = NSHostingController(rootView: SkillsView(model: model, preferences: preferences))
        window.setContentSize(NSSize(width: 680, height: 600))
        self.onClose = onClose
        super.init()
        window.delegate = self
        model.close = { [weak window] in window?.close() }
        languageSubscription = preferences.$language.sink { [weak window] _ in
            window?.title = L("Skills", "Skills")
        }
    }

    func show() {
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

struct SkillsView: View {
    @ObservedObject var model: SkillsViewModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(20)
            Divider()
            content
            Divider()
            footer.padding(16)
        }
        // Rows read their text through L(), which SwiftUI can't track; rebuild them on a language switch.
        .id(preferences.language)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: preferences.cat.image(pointSize: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Skills", "Skills")).font(.title2.bold())
                Text(L("Personal skills from Claude Code and Codex. Linked skills live once in your im repository and are shared by the agents you pick. Skills you don't link stay where they are.",
                       "这里列出 Claude Code 和 Codex 的个人 Skills。关联后的 Skill 只在 im 仓库里保存一份，并共享给你勾选的 Agent；不关联的 Skill 保持原样。"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await model.reload() }
            } label: {
                Label(L("Reload", "重新加载"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isWorking)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasScanned {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.skills.isEmpty {
            Text(L("No personal skills found in Claude Code or Codex.", "在 Claude Code 和 Codex 里没有找到个人 Skills。"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.unlinked.isEmpty {
                        section(L("Not linked", "未关联"), count: model.unlinked.count) {
                            HStack(spacing: 8) {
                                Button(L("Select All", "全选")) { model.selectAll(true) }
                                Button(L("Select None", "全不选")) { model.selectAll(false) }
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                        }
                        ForEach(model.unlinked) { skill in
                            SkillRow(skill: skill, choice: choice(for: skill), isSkipped: model.skipped.contains(skill.name))
                        }
                    }
                    if !model.linked.isEmpty {
                        section(L("Linked", "已关联"), count: model.linked.count) { EmptyView() }
                        ForEach(model.linked) { skill in
                            SkillRow(skill: skill, choice: choice(for: skill), isSkipped: false)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func section(_ title: String, count: Int, @ViewBuilder accessory: () -> some View) -> some View {
        HStack {
            Text("\(title) · \(count)").font(.headline)
            Spacer()
            accessory()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let warning = model.syncWarning {
                Label(warning, systemImage: "exclamationmark.icloud").foregroundStyle(.orange).font(.callout).lineLimit(3)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if let result = model.resultMessage {
                Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            }
            HStack {
                Text(L("Replaced folders are kept in ~/.im/backup.", "被替换的文件夹会保存在 ~/.im/backup。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button(L("Not Now", "暂不关联"), action: model.notNow)
                    .disabled(model.isWorking)
                Button(L("Apply", "应用"), action: model.apply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges || model.isWorking)
            }
        }
    }

    private func choice(for skill: Skill) -> Binding<SkillsViewModel.Choice> {
        Binding(
            get: { model.choices[skill.name] ?? .init() },
            set: { model.choices[skill.name] = $0 }
        )
    }
}

private struct SkillRow: View {
    let skill: Skill
    @Binding var choice: SkillsViewModel.Choice
    let isSkipped: Bool

    private var isLinked: Bool { skill.state == .linked }
    private var isActive: Bool { isLinked ? !choice.unlink : choice.link }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isLinked {
                Toggle("", isOn: $choice.link).labelsHidden().toggleStyle(.checkbox)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(skill.name).font(.body.monospaced().bold())
                    StateBadge(state: skill.state, unlinking: choice.unlink)
                    if isSkipped {
                        Text(L("Skipped", "已跳过")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLinked {
                        Button(choice.unlink ? L("Keep Linked", "保持关联") : L("Unlink", "取消关联")) { choice.unlink.toggle() }
                            .controlSize(.small)
                    }
                }
                if let description = skill.description {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 16) {
                    Text(foundIn).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(L("Install in", "安装到")).font(.caption).foregroundStyle(.secondary)
                    ForEach(SkillAgent.allCases, id: \.self) { agent in
                        Toggle(agent.displayName, isOn: agentBinding(agent))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }
                }
                .disabled(!isActive)
                if skill.state == .differentVersions {
                    VersionPicker(skill: skill, selection: $choice.version)
                        .disabled(!choice.link)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .opacity(isActive || !isLinked ? 1 : 0.6)
    }

    private var foundIn: String {
        let places = skill.installedAgents.sorted().map(\.displayName) + (skill.repositoryCopy != nil ? ["im"] : [])
        return L("Found in: ", "所在位置：") + places.joined(separator: " · ")
    }

    private func agentBinding(_ agent: SkillAgent) -> Binding<Bool> {
        Binding(
            get: { choice.agents.contains(agent) },
            set: { on in
                if on { choice.agents.insert(agent) } else { choice.agents.remove(agent) }
            }
        )
    }
}

private struct StateBadge: View {
    let state: Skill.State
    let unlinking: Bool

    var body: some View {
        Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var title: String {
        if unlinking { return L("Will unlink", "将取消关联") }
        switch state {
        case .linked: return L("Linked", "已关联")
        case .notLinked: return L("Not linked", "未关联")
        case .differentVersions: return L("Different versions", "版本不同")
        case .onlyInIM: return L("From im", "来自 im")
        }
    }

    private var color: Color {
        if unlinking { return .secondary }
        switch state {
        case .linked: return .green
        case .notLinked: return .secondary
        case .differentVersions: return .orange
        case .onlyInIM: return .blue
        }
    }
}

private struct VersionPicker: View {
    let skill: Skill
    @Binding var selection: SkillVersion.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("The copies differ. Keep:", "各处的内容不一样，保留哪个版本：")).font(.caption.bold())
            Picker("", selection: $selection) {
                ForEach(skill.versions) { version in
                    Text(describe(version)).tag(Optional(version.id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(.caption)
            Text(L("Different files: ", "不同的文件：") + skill.differingFiles.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    private func describe(_ version: SkillVersion) -> String {
        let owners = version.owners.map { $0?.displayName ?? "im" }.joined(separator: " · ")
        let date = version.content.modified.formatted(date: .abbreviated, time: .shortened)
        let files = version.content.files.count
        return L("\(owners) — modified \(date), \(files) files", "\(owners) — 修改于 \(date)，\(files) 个文件")
    }
}
