import SwiftUI
import DailyCore

/// Modal sheet for pasting, viewing, and editing the raw text-based financial Smart Ledger DSL.
/// Features real-time AST parsing preview, one-tap clipboard paste, and validation.
public struct SmartLedgerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ledgerStore = SmartLedgerStore.shared
    
    @State private var editingText: String = ""
    @State private var showingResetConfirmation: Bool = false
    
    public init() {}
    
    private var liveParsed: ParsedSmartLedger {
        SmartLedgerParser.shared.parse(editingText)
    }
    
    public var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                VStack(spacing: 14) {
                    // Live Computed Preview Card
                    liveStatsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    
                    // Action Buttons Bar (Paste, Reset)
                    HStack(spacing: 12) {
                        Button {
                            if let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty {
                                editingText = clipboardString
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Paste from Clipboard")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(ThemeColors.accentCyan.opacity(0.25))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button {
                            showingResetConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Reset")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    
                    // Monospaced Text Editor Card
                    GlassCard(cornerRadius: 18, padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("RAW LEDGER DSL")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .tracking(1.2)
                                Spacer()
                                Text("\(editingText.components(separatedBy: .newlines).count) lines")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            
                            TextEditor(text: $editingText)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .background(Color.black.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Smart Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Apply") {
                        ledgerStore.saveLedgerText(editingText)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentGreen)
                }
            }
            .confirmationDialog("Reset Ledger to Baseline Template?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Reset to Default", role: .destructive) {
                    editingText = SmartLedgerStore.defaultLedgerText
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                editingText = ledgerStore.rawText
            }
        }
    }
    
    // MARK: - Live Stats Preview
    private var liveStatsCard: some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LIVE COMPUTED NET WORTH")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .tracking(1.1)
                        Text(liveParsed.formattedNetWorth)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentGreen)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ESTIMATED EUR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .tracking(1.1)
                        Text(liveParsed.formattedNetWorthEUR)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.10))
                
                HStack(spacing: 8) {
                    metricMini(label: "DEPOZITE", value: liveParsed.formattedDepositTotal, color: ThemeColors.accentGreen)
                    metricMini(label: "SOLD", value: liveParsed.formattedBalanceTotal, color: ThemeColors.accentCyan)
                    metricMini(label: "INCOMING", value: liveParsed.formattedIncomingTotal, color: ThemeColors.accentPurple)
                    metricMini(label: "OUTGOING", value: liveParsed.formattedOutgoingTotal, color: ThemeColors.accentOrange)
                }
            }
        }
    }
    
    @ViewBuilder
    private func metricMini(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(ThemeColors.fgMutedDark)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
