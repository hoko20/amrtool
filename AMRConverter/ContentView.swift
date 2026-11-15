import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = ConversionModel()
    @State private var picking = false
    @State private var showingPhotos = false
    @State private var videoItem: PhotosPickerItem?
    @State private var confirmClear = false

    // 不按 UTI 过滤：第三方 App 存的 mp3 常常没有正确的 public.mp3 类型，
    // 过滤会导致「打开」按钮变灰或点了没反应。选中后由编码器给出明确错误。
    private static let allowedTypes: [UTType] = [.item]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard

                    SectionLabel(text: "输入")
                    inputCard

                    if model.busy {
                        progressCard
                    }

                    if let error = model.errorText {
                        InlineNotice(text: error)
                    }

                    SectionLabel(text: "输出文件")

                    if model.outputs.isEmpty {
                        EmptyCard(text: "还没有输出文件。选择 MP3 或 MP4 后会自动生成 AMR。")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(model.outputs) { item in
                                OutputCard(item: item) {
                                    model.delete(item)
                                }
                            }
                        }
                    }

                    Text("输出为 AMR-NB 12.2 kbps / 8 kHz / 单声道，保存在本应用的 Documents 目录，可在「文件」App 的「我的 iPhone → 语音转AMR」中查看和导出。")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                        .padding(.top, 2)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(Palette.background)
            .glassNavigationBar(title: "语音转 AMR")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !model.outputs.isEmpty {
                        Button {
                            confirmClear = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: Self.allowedTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    model.convert(urls: urls)
                case .failure(let error):
                    model.errorText = error.localizedDescription
                }
            }
            .confirmationDialog("删除全部输出文件？", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("全部删除", role: .destructive) { model.deleteAll() }
                Button("取消", role: .cancel) { }
            }
            .photosPicker(isPresented: $showingPhotos, selection: $videoItem, matching: .videos)
            .onChange(of: videoItem) { _, item in
                guard let item else { return }
                videoItem = nil
                model.convert(pickedItem: item)
            }
        }
    }

    // MARK: - 概览

    private var summaryCard: some View {
        CardBox(radius: 22, padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("已转换")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(model.busy ? "转换中…" : "AMR-NB 12.2k")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }

                Text("\(model.outputs.count)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 10)

                ThinSeparator()
                    .padding(.vertical, 16)

                Text(model.statusText)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 输入

    private var inputCard: some View {
        CardBox(radius: 20, padding: 0) {
            VStack(spacing: 0) {
                PickerRow(system: "doc.badge.plus",
                          title: model.busy ? "转换中…" : "从「文件」选择",
                          subtitle: "MP3 · MP4 · M4A · MOV · WAV，自动抽取音轨",
                          disabled: model.busy) {
                    picking = true
                }

                ThinSeparator()
                    .padding(.leading, 16)

                PickerRow(system: "photo.on.rectangle",
                          title: "从「相册」选择视频",
                          subtitle: "相册里的 MP4 / MOV 视频",
                          disabled: model.busy) {
                    showingPhotos = true
                }

                ThinSeparator()
                    .padding(.leading, 16)

                HStack(spacing: 12) {
                    Text("输出格式")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                    Spacer(minLength: 8)
                    Text("AMR-NB 12.2 kbps")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .opacity(model.busy ? 0.6 : 1)
    }

    // MARK: - 进度

    private var progressCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(model.currentName.isEmpty ? "准备中…" : model.currentName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(Int((model.progress * 100).rounded()))%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(Palette.ink)
            }
        }
    }
}

// MARK: - 输出行

private struct OutputCard: View {
    let item: OutputFile
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.placeholder)
                    .frame(width: 46, height: 46)
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(item.sizeText) · \(item.dateText)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer(minLength: 6)

            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Palette.placeholder, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
        .contextMenu {
            Button {
                UIPasteboard.general.string = item.url.path
            } label: {
                Label("复制文件路径", systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - 输入行

private struct PickerRow: View {
    let system: String
    let title: String
    let subtitle: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: system)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#Preview {
    ContentView()
}
