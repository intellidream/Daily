import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Sleek modal sheet allowing fast one-tap incremental adjustments, custom amount keypad entry,
/// note modifications, and deletion for any category pill in the Smart Ledger.
public struct SmartLedgerQuickAdjustSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ledgerStore = SmartLedgerStore.shared
    
    public let item: SmartLedgerItem
    
    @State private var inputAmountText: String = ""
    @State private var inputNoteText: String = ""
    @State private var showingDeleteConfirmation: Bool = false
    
    public init(item: SmartLedgerItem) {
        self.item = item
        // Initialize with current values
        let rawStr = item.rawAmount.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(item.rawAmount))" : String(format: "%.2f", item.rawAmount)
        self._inputAmountText = State(initialValue: rawStr)
        self._inputNoteText = State(initialValue: item.notes.joined(separator: " · "))
    }
    
    private var isScaled: Bool {
        item.isScaled
    }
    
    private var sectionColor: Color {
        switch item.sectionName.lowercased() {
        case "incoming": return ThemeColors.accentPurple
        case "outgoing": return ThemeColors.accentOrange
        case "deposit": return ThemeColors.accentGreen
        case "dentist": return ThemeColors.accentPink
        default: return ThemeColors.accentCyan
        }
    }
    
    public var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header info card
                        heroCard
                        
                        // Quick Delta Chips
                        quickDeltaSection
                        
                        // Exact Amount & Notes Editor
                        manualEditSection
                        
                        // Delete Action
                        deleteSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                ToolbarItem(placement: .principal) {
                    AutoScrollingText(
                        text: item.displayName,
                        fontSize: 15,
                        weight: .bold,
                        color: .white,
                        alignment: .center,
                        fixedContainerWidth: 200
                    )
                    .frame(width: 200, height: 32)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveManualChanges()
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentGreen)
                }
            }
            .confirmationDialog(
                "Sigur dorești să ștergi această categorie?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Șterge Categoria", role: .destructive) {
                    triggerHaptic()
                    ledgerStore.deleteItem(item: item)
                    dismiss()
                }
                Button("Anulează", role: .cancel) {}
            } message: {
                Text("Această acțiune va elimina linia din Smart Ledger și va recalcula automat soldul și totalurile.")
            }
        }
    }
    
    // MARK: - Hero Card
    private var heroCard: some View {
        GlassCard(cornerRadius: 22, padding: 20) {
            VStack(spacing: 12) {
                HStack {
                    Text(item.sectionName.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(sectionColor)
                        .tracking(1.5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(sectionColor.opacity(0.15))
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    if item.percentageOfSection > 0 {
                        Text(String(format: "%.1f%% din secțiune", item.percentageOfSection * 100))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                
                // Prominent auto-scrolling category title
                AutoScrollingText(
                    text: item.displayName,
                    fontSize: 18,
                    weight: .bold,
                    design: .rounded,
                    color: .white,
                    alignment: .center
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                
                Text(item.formattedCalculatedAmount)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                if item.isScaled && item.rawAmount > 0 {
                    HStack(spacing: 6) {
                        Text("Unitate DSL:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text(item.formattedRawAmount)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(sectionColor)
                        Text("(1 unitate = 100 Lei)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Quick Delta Chips Section
    private var quickDeltaSection: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Ajustare Rapidă", systemImage: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.warning)
                
                if isScaled {
                    // Scaled presets (1 unit = 100 Lei)
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            deltaChip(title: "-500 Lei", subtitle: "-5", delta: -5, isNegative: true)
                            deltaChip(title: "-200 Lei", subtitle: "-2", delta: -2, isNegative: true)
                            deltaChip(title: "-100 Lei", subtitle: "-1", delta: -1, isNegative: true)
                        }
                        HStack(spacing: 8) {
                            deltaChip(title: "+100 Lei", subtitle: "+1", delta: 1, isNegative: false)
                            deltaChip(title: "+200 Lei", subtitle: "+2", delta: 2, isNegative: false)
                            deltaChip(title: "+500 Lei", subtitle: "+5", delta: 5, isNegative: false)
                        }
                        HStack(spacing: 8) {
                            deltaChip(title: "+1.000 Lei", subtitle: "+10", delta: 10, isNegative: false)
                        }
                    }
                } else {
                    // Unscaled presets (e.g. Deposit)
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            deltaChip(title: "-1.000 Lei", subtitle: "-1.000", delta: -1000, isNegative: true)
                            deltaChip(title: "-500 Lei", subtitle: "-500", delta: -500, isNegative: true)
                        }
                        HStack(spacing: 8) {
                            deltaChip(title: "+500 Lei", subtitle: "+500", delta: 500, isNegative: false)
                            deltaChip(title: "+1.000 Lei", subtitle: "+1.000", delta: 1000, isNegative: false)
                            deltaChip(title: "+5.000 Lei", subtitle: "+5.000", delta: 5000, isNegative: false)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func deltaChip(title: String, subtitle: String, delta: Double, isNegative: Bool) -> some View {
        Button {
            triggerHaptic()
            ledgerStore.adjustItem(item: item, deltaRaw: delta)
            dismiss()
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isNegative ? ThemeColors.accentPink : ThemeColors.accentGreen)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                (isNegative ? ThemeColors.accentPink : ThemeColors.accentGreen).opacity(0.12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder((isNegative ? ThemeColors.accentPink : ThemeColors.accentGreen).opacity(0.30), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Manual Amount & Note Editor
    private var manualEditSection: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Valoare Exactă & Notițe", systemImage: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(isScaled ? "UNITATE RAW DSL (1 = 100 LEI)" : "SUMĂ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .tracking(1.2)
                    
                    HStack {
                        TextField("0", text: $inputAmountText)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if isScaled, let num = Double(inputAmountText.replacingOccurrences(of: ",", with: ".")) {
                            Text("= \(Int(num * 100)) Lei")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(ThemeColors.accentGreen)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTIȚE INFORMATIVE (PARANTEZE)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .tracking(1.2)
                    
                    TextField("ex: 40/45, Edn/3, etc.", text: $inputNoteText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - Delete Section
    private var deleteSection: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Șterge Categoria din Ledger")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(ThemeColors.accentPink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ThemeColors.accentPink.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ThemeColors.accentPink.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    private func saveManualChanges() {
        triggerHaptic()
        let clean = inputAmountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let newNum = Double(clean) else { return }
        
        ledgerStore.setItemAmount(item: item, newRaw: newNum)
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
