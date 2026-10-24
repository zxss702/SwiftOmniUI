// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
import Foundation
import JsonData
import SwiftOmniUIJsonData
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@Model
private final class PickerModel {
    var id: UUID
    var name: String
    init(name: String) { id = UUID(); self.name = name }
}

private struct PickerModelSettings: View {
    @Query(sort: [SortDescriptor<PickerModel>(\.name)], animation: .snappy) private var models: [PickerModel]
    @Environment(\.modelContext) private var context
    @Binding var selected: String

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack {
                    VStack {
                        ForEach(0..<15) { expert in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Expert \(expert)").font(.headline)
                                    Text("用于规划与构思未来愿景、架构及核心逻辑。")
                                        .font(.subheadline)
                                }
                                Spacer()
                                Picker("", selection: $selected) {
                                    ForEach(models) { model in Text(model.name).tag(model.id.uuidString) }
                                }.labelsHidden()
                            }.frame(height: 40).frame(maxWidth: .infinity)
                        }
                    }
                    VStack(spacing: 4) {
                        ForEach(Array(models.enumerated()), id: \.element) { index, model in
                            if index != 0 { Divider() }
                            HStack {
                                NavigationLink {
                                    Text(model.name)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(model.name).bold()
                                            Text("Model / Responses").font(.footnote)
                                        }
                                        Text("https://example.invalid/v1").font(.footnote)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: 40)
                                }
                                Button("Delete") {
                                    withAnimation(.snappy) { context.delete(model) }
                                    try? context.save()
                                }.id("delete-\(model.name)")
                            }.frame(height: 40).frame(maxWidth: .infinity)
                                .transition(.blur.combined(with: .scale(scale: 0.8, anchor: .top)).animation(.snappy.speed(2)))
                        }
                    }.padding(.vertical, 8).padding(.horizontal, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .buttonStyle(.plain)
                }.padding(16)
            }
        }
    }
}

final class WinUIPickerModelDeletionTests: XCTestCase {
    func testCopyingAndDeletingModelsWhileSettingsRowsAnimate() throws {
        try onUIThread {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SOUI-picker-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let container = try ModelContainer(for: Schema([PickerModel.self]),
                                               configurations: [ModelConfiguration(url: directory.appendingPathComponent("models.sqlite"))])
            let context = container.mainContext
            let original = PickerModel(name: "A selected model for every expert / 所有专家使用的模型")
            context.insert(original)
            for index in 0..<14 { context.insert(PickerModel(name: "Model \(index)")) }
            try context.save()
            let selected = State(wrappedValue: original.id.uuidString)
            let host = WinUIRenderer.running(room: LayoutSize(width: 790, height: 850)) {
                PickerModelSettings(selected: selected.projectedValue).modelContainer(container)
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            for _ in 0..<8 { host.step() }
            scroll.scroller.move(to: Point(0, scroll.scroller.standing.reach.y))
            for turn in 0..<12 {
                let copy = PickerModel(name: "Copy \(turn) " + String(repeating: "model name 中文 ", count: turn % 3 + 1))
                withAnimation(.snappy) { context.insert(copy) }
                try context.save()
                for _ in 0..<12 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                    host.step()
                    host.frame()
                }
                XCTAssertNotNil(host.view(id: .manual("delete-\(copy.name)")),
                                "the query update must actually insert the copied model's native row")
                let removed = turn == 0 ? original : copy
                let removedID = "delete-\(removed.name)"
                withAnimation(.snappy) { context.delete(removed) }
                try context.save()
                for _ in 0..<18 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                    host.step()
                    host.frame()
                }
                XCTAssertNil(host.view(id: .manual(removedID)),
                             "the deleted row must finish its removal transition")
            }
            XCTAssertEqual(try context.fetch(FetchDescriptor<PickerModel>()).count, 15)
        }
    }

    func testDeletingThePersistedModelSelectedByExpertPickers() throws {
        try onUIThread {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SOUI-picker-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let container = try ModelContainer(for: Schema([PickerModel.self]),
                                               configurations: [ModelConfiguration(url: directory.appendingPathComponent("models.sqlite"))])
            let alpha = PickerModel(name: "Alpha"), beta = PickerModel(name: "Beta — a long model name / 模型名称，用于专家配置")
            container.mainContext.insert(alpha)
            container.mainContext.insert(beta)
            try container.mainContext.save()
            let selected = State(wrappedValue: beta.id.uuidString)
            let deletedID = selected.wrappedValue
            let host = WinUIRenderer.running(room: LayoutSize(width: 800, height: 900)) {
                PickerModelSettings(selected: selected.projectedValue).modelContainer(container)
            }
            let deleteID = "delete-\(beta.name)"
            host.settle { host.view(id: .manual(deleteID)) != nil }
            let delete = try XCTUnwrap(host.view(id: .manual(deleteID)) as? WinUIButtonView)
            delete.invoke()
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PickerModel>()).map(\.name), ["Alpha"])
            for _ in 0..<60 {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                host.step()
                host.layOut()
                if host.views(WinUIPickerView.self).allSatisfy({ $0.chosen == -1 }) { break }
            }
            XCTAssertEqual(selected.wrappedValue, deletedID)
            let pickers = host.views(WinUIPickerView.self)
            XCTAssertEqual(pickers.count, 15)
            for picker in pickers {
                XCTAssertEqual(picker.chosen, -1)
                XCTAssertEqual(WinUIStrings.read { swiftomniui_winui_read(picker.handle, "displayedText", $0, $1) }, "")
            }
        }
    }
}
