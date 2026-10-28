import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel
    let window: () -> NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 10)
                .frame(height: 44)
            Divider()
            EditorCanvas(model: model)
                .frame(minWidth: 320, minHeight: 180)
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 4) {
            if model.tool == .crop {
                Label("Drag the edges or corners to crop", systemImage: "crop")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancelCrop() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.applyCrop() }
                    .keyboardShortcut(.defaultAction)
            } else {
                InkToolButton(model: model, tool: .pen, symbol: "pencil.tip", help: "Pen")
                InkToolButton(model: model, tool: .highlighter, symbol: "highlighter", help: "Highlighter")
                EraserButton(model: model)

                Divider().frame(height: 22).padding(.horizontal, 4)

                ToolbarIconButton(symbol: "crop", help: "Crop") { model.tool = .crop }

                Spacer()

                ToolbarIconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndo)
                ToolbarIconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)

                Divider().frame(height: 22).padding(.horizontal, 4)

                ToolbarIconButton(symbol: "doc.on.doc", help: "Copy (⌘C)") { model.copyToClipboard() }
                    .keyboardShortcut("c", modifiers: .command)
                ToolbarIconButton(symbol: "square.and.arrow.down", help: "Save as (⌘S)") {
                    model.save(from: window())
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

/// Pen or highlighter: the first click selects it, a click on the selected tool opens its color and size options.
private struct InkToolButton: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var settings = AppSettings.shared
    let tool: EditorTool
    let symbol: String
    let help: String
    @State private var showsOptions = false

    private var kind: InkKind { tool.inkKind ?? .pen }

    var body: some View {
        Button {
            if model.tool == tool {
                showsOptions.toggle()
            } else {
                model.tool = tool
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                Capsule()
                    .fill(Color(nsColor: settings.style(for: kind).color))
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 16, height: 4)
            }
            .frame(width: 36, height: 32)
            .background(model.tool == tool ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
            InkOptionsView(kind: kind, style: kind == .pen ? $settings.penStyle : $settings.highlighterStyle)
        }
    }
}

private struct InkOptionsView: View {
    let kind: InkKind
    @Binding var style: InkStyle

    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colors").font(.headline)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(kind.palette, id: \.self) { hex in
                    Button {
                        style.colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: hex)))
                            .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .padding(-3)
                                    .opacity(style.colorHex == hex ? 1 : 0)
                            )
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Size").font(.headline)
            HStack(spacing: 10) {
                Slider(value: $style.width, in: kind.widthRange)
                    .frame(width: 140)
                Circle()
                    .fill(Color(nsColor: style.color).opacity(kind == .highlighter ? 0.55 : 1))
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                    .frame(width: min(style.width, 32), height: min(style.width, 32))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(14)
    }
}

/// Eraser: removes whole strokes it touches. A click on the selected eraser offers "Erase all ink".
private struct EraserButton: View {
    @ObservedObject var model: EditorModel
    @State private var showsOptions = false

    var body: some View {
        Button {
            if model.tool == .eraser {
                showsOptions.toggle()
            } else {
                model.tool = .eraser
            }
        } label: {
            Image(systemName: "eraser")
                .font(.system(size: 15))
                .frame(width: 36, height: 32)
                .background(model.tool == .eraser ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Eraser")
        .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
            Button("Erase all ink") {
                model.eraseAllInk()
                showsOptions = false
            }
            .disabled(model.state.strokes.isEmpty)
            .padding(12)
        }
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
