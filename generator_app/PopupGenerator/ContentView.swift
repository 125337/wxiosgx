//
//  ContentView.swift
//  弹窗配置表单 + 生成导出
//
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var title = "发现新版本"
    @State private var message = "有新版本可用，是否前往更新？"
    @State private var confirm = "去更新"
    @State private var cancel = "不再提示"
    @State private var url = ""
    @State private var pluginVersion = ""      // 留空 = 无条件弹
    @State private var showIgnore = true
    @State private var showShare = false
    @State private var generatedURL: URL?
    @State private var errorMsg: String?
    @State private var generating = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("弹窗内容")) {
                    TextField("标题", text: $title)
                    TextField("内容", text: $message)
                }
                Section(header: Text("按钮")) {
                    TextField("确认按钮(去更新)", text: $confirm)
                    TextField("取消按钮(不再提示)", text: $cancel)
                    Toggle("显示\"不再提示\"按钮", isOn: $showIgnore)
                }
                Section(header: Text("更新判断")) {
                    TextField("目标插件版本(留空=无条件弹)", text: $pluginVersion)
                        .keyboardType(.numbersAndPunctuation)
                    Text("以你的插件版本为准:用户本地版本低于此值则弹窗。点\"去更新/不再提示\"写入版本停止提醒,点\"取消\"下次继续弹。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("下载地址")) {
                    TextField("https://…", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                if let err = errorMsg {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
                Section {
                    Button(action: generate) {
                        if generating {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("生成 dylib 并导出").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(generating)
                }
            }
            .navigationTitle("弹窗生成器")
            .sheet(isPresented: $showShare) {
                if let url = generatedURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func generate() {
        errorMsg = nil
        generating = true
        DispatchQueue.global().async {
            do {
                let config = PopupConfig(
                    title: title, message: message,
                    confirm: confirm, cancel: cancel,
                    url: url, pluginVersion: pluginVersion,
                    showIgnore: showIgnore)
                let template = try TemplateEngine.loadTemplate()
                let dylib = try TemplateEngine.generate(config: config, template: template)

                let ver = pluginVersion.isEmpty ? "uncond" : pluginVersion
                let fm = FileManager.default
                let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Generated", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let out = dir.appendingPathComponent("UpdatePrompt_\(ver).dylib")
                try dylib.write(to: out)

                DispatchQueue.main.async {
                    generating = false
                    generatedURL = out
                    showShare = true
                }
            } catch {
                DispatchQueue.main.async {
                    generating = false
                    errorMsg = "生成失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// UIActivityViewController 包装,用于分享 dylib
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
