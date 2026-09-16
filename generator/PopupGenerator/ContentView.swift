//
//  ContentView.swift
//  版本标记输入 + 生成导出
//
//  弹窗内容(标题/文字/按钮/链接)全部由服务器 popup.json 控制,
//  这里只需要填"版本标记":后台 plugin_target_version 高于它 → 弹窗;等于 → 不弹。
//
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var pluginVersion = ""
    @State private var showShare = false
    @State private var generatedURL: URL?
    @State private var errorMsg: String?
    @State private var generating = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("版本标记")) {
                    TextField("插件版本号,如 2.2.0", text: $pluginVersion)
                        .keyboardType(.numbersAndPunctuation)
                    Text("这个版本号会写入生成的 dylib。\n后台 popup.json 的 plugin_target_version 高于它 → 用户弹窗提示更新;等于它 → 已是最新,不弹。")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                let config = PopupConfig(pluginVersion: pluginVersion)
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
