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
    }
}

// MARK: - 首页

struct HomeView: View {
    @Bindable var model: ConversionModel

    @State private var picking = false
    @State private var showingPhotos = false
    @State private var videoItem: PhotosPickerItem?
    @State private var renameItem: OutputFile?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                importSection
                formatSection
                progressSection
                outputSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("语音转音频")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    .accessibilityLabel("从相册选择视频")
                }
            }
            .sheet(isPresented: $picking) {
                DocumentPicker { urls in
                    picking = false
                    model.convert(urls: urls)
                }
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
                Label("从「文件」选择音频或视频", systemImage: "folder")
            }
            .disabled(model.busy)

            PhotosPicker(selection: $videoItem, matching: .videos) {
                Label("从相册选择视频", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(model.busy)
        } header: {
            Text("导入")
        } footer: {
            if let error = model.errorText {
                Text(error).foregroundStyle(.red)
            } else {
                Text("支持 MP3、MP4、M4A、MOV、WAV 等带音轨的文件，视频会自动只取声音。当前状态：\(model.statusText)")
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
            Section("进度") {
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
                    OutputRow(item: item)
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
            Text("左滑文件行可以重命名或删除。文件保存在「文件」App → 我的 iPhone → 语音转AMR。")
        }
    }
}

// MARK: - 文件行

private struct OutputRow: View {
    let item: OutputFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(item.sizeText) · \(item.dateText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
        }
    }

    private var symbol: String {
        switch item.url.pathExtension.lowercased() {
        case "aud": return "waveform"
        case "m4a": return "music.note"
        default:    return "waveform.path"
        }
    }
}
