import SwiftUI
import UIKit

/// 固定高度、区域内独立滚动的输出文件列表。
/// 行高固定 56pt，左滑出现「分享 / 重命名 / 删除」。
struct OutputListView: View {
    let outputs: [OutputFile]
    let onShare: (OutputFile) -> Void
    let onRename: (OutputFile) -> Void
    let onDelete: (OutputFile) -> Void

    /// 单行高度，与 rowHeight 保持一致
    static let rowHeight: CGFloat = 56
    /// 区域最大高度，超出后在内部滚动
    static let maxHeight: CGFloat = 300

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(outputs.enumerated()), id: \.element.id) { index, item in
                    SwipeRow(item: item,
                             onShare: { onShare(item) },
                             onRename: { onRename(item) },
                             onDelete: { onDelete(item) })
                        .frame(height: Self.rowHeight)

                    if index < outputs.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
    }

    static func height(for count: Int) -> CGFloat {
        min(CGFloat(count) * rowHeight, maxHeight)
    }
}

private struct SwipeRow: View {
    let item: OutputFile
    let onShare: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat?

    private let actionWidth: CGFloat = 204 // 3 × 68

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                action(title: "分享", symbol: "square.and.arrow.up",
                       color: .accentColor, perform: onShare)
                action(title: "重命名", symbol: "pencil",
                       color: .orange, perform: onRename)
                action(title: "删除", symbol: "trash",
                       color: .red, perform: onDelete)
            }
            .frame(width: actionWidth)

            row
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: OutputListView.rowHeight)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .offset(x: offset)
                .gesture(drag)
                .onTapGesture {
                    if offset != 0 {
                        close()
                    } else {
                        onShare()
                    }
                }
        }
        .clipped()
    }

    private var row: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(item.sizeText) · \(item.dateText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func action(title: String,
                        symbol: String,
                        color: Color,
                        perform: @escaping () -> Void) -> some View {
        Button {
            close()
            perform()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white)
            .frame(width: 68, height: OutputListView.rowHeight)
            .background(color)
        }
        .buttonStyle(.plain)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if startOffset == nil { startOffset = offset }
                offset = min(0, max(-actionWidth, (startOffset ?? 0) + value.translation.width))
            }
            .onEnded { value in
                let projected = (startOffset ?? 0) + value.predictedEndTranslation.width
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    offset = projected < -actionWidth / 2 ? -actionWidth : 0
                }
                startOffset = nil
            }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
    }
}
