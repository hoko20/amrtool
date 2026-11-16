import SwiftUI

/// 输出文件页：从首页「输出文件」一行推入，列表用系统 List + 原生左滑操作。
struct OutputFilesView: View {
    @Bindable var model: ConversionModel

    @State private var renameItem: OutputFile?
    @State private var renameText = ""
    @State private var shareItems: [Any] = []
    @State private var sharing = false

    var body: some View {
        List {
            Section {
                if model.outputs.isEmpty {
                    Text("还没有输出文件")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.outputs) { item in
                        Button {
                            share(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(item.sizeText) · \(item.dateText)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
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
                                share(item)
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("全部文件")
                    Spacer()
                    Text("\(model.outputs.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("左滑可分享、重命名或删除，点击行直接分享。文件保存在「文件」App → 我的 iPhone → AudioForge。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("输出文件")
        .sheet(isPresented: $sharing) {
            ShareSheet(items: shareItems)
                .ignoresSafeArea()
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

    private func share(_ item: OutputFile) {
        shareItems = [item.url]
        sharing = true
    }
}
