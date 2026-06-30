//  DisclosureField.swift
//  Ravns
//
//  A collapsible input row used through onboarding/settings: it shows LABEL + the current value as a
//  compact tappable row, and reveals its editor (wheel, text field, …) only when opened. A shared
//  `expanded` id makes the group behave like an accordion — one control open at a time — so a step
//  full of pickers reads as a clean list instead of a wall of wheels.

import SwiftUI

struct DisclosureField<Editor: View>: View {
    let id: String
    let label: String
    let value: String
    var placeholder: String = "Tap to set"
    @Binding var expanded: String?
    @ViewBuilder var editor: () -> Editor

    private var isOpen: Bool { expanded == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                if isOpen {
                    Button("Done") { withAnimation(.easeInOut(duration: 0.2)) { expanded = nil } }
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.mint)
                }
            }

            if isOpen {
                editor()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.mint.opacity(0.55), lineWidth: 1))
            } else {
                Button { withAnimation(.easeInOut(duration: 0.2)) { expanded = id } } label: {
                    HStack {
                        Text(value.isEmpty ? placeholder : value)
                            .foregroundStyle(value.isEmpty ? Palette.textFaint : Palette.text)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption).foregroundStyle(Palette.textMuted)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.surfaceLine, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A text field that grabs focus the moment it appears — so a DisclosureField opening to a text editor
/// pops the keyboard immediately (the editor is only built while expanded, so onAppear fires on open).
struct FocusedTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .never
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard).textInputAutocapitalization(autocap)
            .autocorrectionDisabled()
            .focused($focused)
            .foregroundStyle(Palette.text)
            .padding(.vertical, 8).padding(.horizontal, 8)
            .onAppear { focused = true }
    }
}
