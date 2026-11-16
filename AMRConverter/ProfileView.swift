import SwiftUI

struct ProfileView: View {
    @Bindable var model: ConversionModel
    @State private var confirmClear = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("当前设置") {
                    LabeledContent("输出格式", value: model.format.title)
                    LabeledContent("采样率", value: model.format.sampleRateText)
                    LabeledContent("码率", value: model.format.bitrateText)
                    LabeledContent("已转换", value: "\(model.outputs.count) 个文件")
                }

                Section {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text("清空全部输出文件")
                    }
                    .disabled(model.outputs.isEmpty)
                } header: {
                    Text("文件")
                } footer: {
                    Text("输出保存在本应用的 Documents 目录，可以在「文件」App → 我的 iPhone → 语音转AMR 中查看、导出或删除。")
                }

                Section("关于说明") {
                    AboutRow(title: "这个应用做什么",
                             text: "把手机里的语音或视频文件转成体积小、兼容性好的语音格式，全程在本机完成，不上传任何数据。")
                    AboutRow(title: "支持哪些输入",
                             text: "MP3、MP4、M4A、MOV、WAV、AAC 等带音轨的文件；视频会自动忽略画面只取声音。")
                    AboutRow(title: "四种输出怎么选",
                             text: "SILK（.aud）是微信、QQ 语音条的原生格式，音质最好且体积小；AMR-NB 兼容性最广，但只有 8kHz 电话音质；AMR-WB 是 AMR 家族的最高档（16kHz）；M4A 用 AAC 96kbps，接近原音，适合通用播放和存档。")
                    AboutRow(title: "为什么 AMR 音质一般",
                             text: "AMR 标准的上限就是 NB 12.2kbps（8kHz）、WB 23.85kbps（16kHz），无法再提高。想更清晰只能用 SILK 或 M4A。")
                    AboutRow(title: "转换失败怎么办",
                             text: "如果提示没有音轨，说明该文件是纯视频或音轨编码不被系统支持；可以先用其它工具导出为 m4a 再转换。")
                }

                Section("关于") {
                    LabeledContent("版本", value: version)
                    Link("GitHub 仓库",
                         destination: URL(string: "https://github.com/hoko20/amrtool")!)
                    Link("opencore-amr（AMR-NB 编码）",
                         destination: URL(string: "https://sourceforge.net/projects/opencore-amr/")!)
                    Link("vo-amrwbenc（AMR-WB 编码）",
                         destination: URL(string: "https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/")!)
                    Link("silk-v3-decoder（SILK 编码）",
                         destination: URL(string: "https://github.com/kn007/silk-v3-decoder")!)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .alert("清空全部输出文件？", isPresented: $confirmClear) {
                Button("清空", role: .destructive) { model.deleteAll() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("这会删除 Documents 目录下所有已转换的音频，操作不可撤销。")
            }
        }
    }
}

private struct AboutRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
