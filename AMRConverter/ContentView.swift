import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var model = ConversionModel()

    var body: some View {
        TabView {
            HomeView(model: model)
                .tabItem { Label("首页", systemImage: "waveform") }

            ProfileView(model: model)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(.accentColor)
    }
}

// MARK: - 首页

struct HomeView: View {
    @Bindable var model: ConversionModel

    @State private var picking = false
    @State private var videoItem: PhotosPickerItem?
    @State private var renameItem: OutputFile?
    @State private var renameText = ""
    @State private var shareItems: [Any] = []
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            List {
                importSection
                formatSection
                progressSection
                outputSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AudioForge")
            .sheet(isPresented: $picking) {
                DocumentPicker { urls in
                    picking = false
                    model.convert(urls: urls)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $sharing) {
                ShareSheet(items: shareItems)
                    .ignoresSafeArea()
            }
            .onChange(of: videoItem) { _, item in
                guard let item else { return }
                videoItem = nil
                Task {
                    do {
                        if let movie = try await item.loadTransferable(type: MovieFile.self) {
                            model.convert(urls: [movie.url])
                        } else {
                            model.errorText = "无法从相册读取这个视频"
                        }
                    } catch {
                        model.errorText = "相册读取失败：\(error.localizedDescription)"
                    }
                }
            }
            .alert("重命名", isPresented: Binding(
                get: { renameItem != nil },
                set: { if !$0 { renameItem = nil } }
            )) {
                TextField("文件名", text: $renameText)
                Button("保存") {
                    if let item = renameItem {
                        model.rename(item, to: renameText)
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只修改文件名，扩展名保持不变")
            }
        }
    }

    // MARK: 导入

    private var importSection: some View {
        Section {
            Button {
                guard !model.busy else { return }
                picking = true
            } label: {
                DetailRow(title: "从「文件」选择音频或视频",
                          subtitle: "MP3 / MP4 / M4A / MOV / WAV")
            }
            .buttonStyle(.plain)
            .disabled(model.busy)

            PhotosPicker(selection: $videoItem, matching: .videos) {
                DetailRow(title: "从相册选择视频",
                          subtitle: "自动只取视频中的声音")
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
        } header: {
            Text("导入")
        } footer: {
            if let error = model.errorText {
                Text(error).foregroundStyle(.red)
            } else {
                Text("当前状态：\(model.statusText)")
            }
        }
    }

    // MARK: 输出格式

    private var formatSection: some View {
        Section {
            Picker("输出格式", selection: $model.format) {
                ForEach(OutputFormat.allCases) { option in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.navigationLink)

            LabeledContent("采样率", value: model.format.sampleRateText)
            LabeledContent("码率", value: model.format.bitrateText)
        } header: {
            Text("输出格式")
        } footer: {
            Text(model.format.summary)
        }
    }

    // MARK: 进度

    @ViewBuilder
    private var progressSection: some View {
        if model.busy {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.currentName.isEmpty ? "正在转换" : model.currentName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((model.progress * 100).rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: model.progress)
                }
                .padding(.vertical, 2)
            } header: {
                Text("进度")
            }
        }
    }

    // MARK: 输出文件

    private var outputSection: some View {
        Section {
            if model.outputs.isEmpty {
                Text("还没有输出文件")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.outputs) { item in
                    DetailRow(title: item.name,
                              subtitle: "\(item.sizeText) · \(item.dateText)",
                              showsDisclosure: false)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                model.delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }

                            Button {
                                renameText = item.url.deletingPathExtension().lastPathComponent
                                renameItem = item
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.orange)

                            Button {
                                shareItems = [item.url]
                                sharing = true
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text("输出文件")
                Spacer()
                Text("\(model.outputs.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("左滑文件行可以分享、重命名或删除。文件保存在「文件」App → 我的 iPhone → AudioForge。")
        }
    }
}

// MARK: - 参考项目风格的行

private struct DetailRow: View {
    let title: String
    let subtitle: String
    var showsDisclosure = true

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
