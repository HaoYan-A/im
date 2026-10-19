import AppKit
import IMCore
import SwiftUI

/// Search skills.sh on the left, preview and install on the right.
struct DiscoverView: View {
    @ObservedObject var model: DiscoverViewModel
    let accent: Color
    let strongAccent: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchField.padding(12)
                Divider()
                results
            }
            .frame(width: 280)
            Divider()
            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Search skills.sh", "搜索 skills.sh"), text: $model.query)
                .textFieldStyle(.plain)
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder
    private var results: some View {
        if model.results.isEmpty {
            VStack(spacing: 6) {
                Text(model.hasSearched ? L("No skills found.", "没有找到 Skill。") : L("Find skills by name or by what they do.", "按名字或用途查找 Skill。"))
                    .foregroundStyle(.secondary)
                if !model.hasSearched {
                    Text(L("Try “code review” or “pdf”.", "试试 “code review” 或 “pdf”。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.results, selection: $model.selection) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.skillId).font(.system(.body, design: .monospaced).weight(.medium)).lineLimit(1)
                        if model.installState(of: result) == .installed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(accent)
                                .help(L("Installed in im", "已安装到 im"))
                        }
                    }
                    HStack {
                        Text(result.source).lineLimit(1)
                        Spacer()
                        Text(Self.installs(result.installs))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                .tag(result.id)
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let result = model.selected {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.skillId).font(.title3.monospaced().weight(.semibold))
                    HStack(spacing: 10) {
                        Text(result.source)
                        Text(L("\(Self.installs(result.installs)) installs", "\(Self.installs(result.installs)) 次安装"))
                        Link(L("Open on skills.sh", "在 skills.sh 打开"), destination: result.pageURL)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                Divider()
                ScrollView {
                    previewBody(result).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                installBar(result).padding(.horizontal, 20).padding(.vertical, 14)
            }
        } else {
            Text(L("Select a skill to preview it.", "选择一个 Skill 查看详情。"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func previewBody(_ result: SkillHubResult) -> some View {
        if !result.isInstallable {
            Text(L("This skill isn't hosted on GitHub, so im can't preview or install it. Open it on skills.sh instead.",
                   "这个 Skill 不在 GitHub 上，im 无法预览和安装，请到 skills.sh 上查看。"))
                .foregroundStyle(.secondary)
        } else if let preview = model.previews[result.id] {
            VStack(alignment: .leading, spacing: 16) {
                Text(Self.markdown(preview.body))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .frame(maxWidth: 640, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Files", "文件")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(preview.files.joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        } else if model.loadingPreview == result.id {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func installBar(_ result: SkillHubResult) -> some View {
        HStack(spacing: 14) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(2)
            } else if let message = model.message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(2)
            }
            Spacer()
            switch model.installState(of: result) {
            case .installed:
                Label(L("Installed, kept up to date", "已安装，自动保持更新"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .nameTaken:
                Text(L("You already have a skill named \(result.skillId).", "已经有一个叫 \(result.skillId) 的 Skill。"))
                    .foregroundStyle(.secondary)
            case .unsupported:
                EmptyView()
            case .available:
                Text(L("Install in", "安装到")).foregroundStyle(.secondary)
                ForEach(SkillAgent.allCases, id: \.self) { agent in
                    Toggle(agent.displayName, isOn: Binding(
                        get: { model.agents.contains(agent) },
                        set: { on in if on { model.agents.insert(agent) } else { model.agents.remove(agent) } }
                    ))
                    .toggleStyle(.checkbox)
                    .tint(accent)
                }
                Button(L("Install", "安装")) { model.install(result) }
                    .buttonStyle(.borderedProminent)
                    .tint(strongAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.agents.isEmpty || model.installing != nil)
            }
        }
        .font(.callout)
    }

    // MARK: Formatting

    static func installs(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).locale(Locale(identifier: Language.current.rawValue)))
    }

    /// Inline Markdown (bold, code, links) rendered, headings shown as bold lines, the rest as written.
    static func markdown(_ text: String) -> AttributedString {
        let headings = text.components(separatedBy: "\n").map { line in
            let level = line.prefix { $0 == "#" }.count
            guard (1...6).contains(level), line.dropFirst(level).first == " " else { return line }
            return "**\(line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces))**"
        }.joined(separator: "\n")
        var rendered = (try? AttributedString(markdown: headings, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        // SKILL.md is third-party text: keep web links clickable, but never file:// or app URL schemes.
        for run in rendered.runs {
            if let url = run.link, !["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                rendered[run.range].link = nil
            }
        }
        return rendered
    }
}
