import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Modal sheet for creating a new financial category item in a chosen Smart Ledger section.
public struct AddLedgerItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ledgerStore = SmartLedgerStore.shared
    
    public let defaultSectionName: String
    
    @State private var selectedSection: String
    @State private var itemName: String = ""
    @State private var amountText: String = ""
    @State private var noteText: String = ""
    
    public init(defaultSectionName: String = "Outgoing") {
        self.defaultSectionName = defaultSectionName
        self._selectedSection = State(initialValue: defaultSectionName)
    }
    
    private let availableSections = ["Incoming", "Outgoing", "Deposit"]
    
    private var isScaled: Bool {
        selectedSection.lowercased() != "deposit"
    }
    
    private var convertedAmountPreview: String {
        let clean = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let val = Double(clean) else { return "" }
        if isScaled {
            let lei = val * 100.0
            return "\(Int(lei)) Lei (\(Int(val)))"
        } else {
            return "\(Int(val)) Lei"
        }
    }
    
    private var isValid: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) != nil
    }
    
    public var body: some View {
        NavigationStack {
            LiquidGlassBackground {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Section Picker
                        GlassCard(cornerRadius: 20, padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SECȚIUNE DESTINAȚIE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .tracking(1.2)
                                
                                Picker("Secțiune", selection: $selectedSection) {
                                    ForEach(availableSections, id: \.self) { sec in
                                        Text(sec).tag(sec)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        
                        // Inputs Card
                        GlassCard(cornerRadius: 20, padding: 18) {
                            VStack(alignment: .leading, spacing: 16) {
                                // Category Name
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("NUME CATEGORIE / CHELTUIALĂ")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                        .tracking(1.2)
                                    
                                    TextField("ex: Sala, Restaurant, Uber, Bonus", text: $itemName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1))
                                }
                                
                                // Amount
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(isScaled ? "VALOARE RAW DSL (1 = 100 LEI)" : "SUMĂ LEI")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(ThemeColors.fgMutedDark)
                                            .tracking(1.2)
                                        Spacer()
                                        if !convertedAmountPreview.isEmpty {
                                            Text(convertedAmountPreview)
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(ThemeColors.accentGreen)
                                        }
                                    }
                                    
                                    TextField(isScaled ? "ex: 15 (= 1.500 Lei)" : "ex: 1500", text: $amountText)
                                        .keyboardType(.numbersAndPunctuation)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1))
                                }
                                
                                // Optional Note
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("NOTIȚĂ OPȚIONALĂ (PARANTEZE)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                        .tracking(1.2)
                                    
                                    TextField("ex: WorldClass, Lunar, etc.", text: $noteText)
                                        .font(.system(size: 16, weight: .medium))
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Adaugă Categorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adaugă") {
                        addItem()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isValid ? ThemeColors.accentGreen : ThemeColors.fgMutedDark.opacity(0.5))
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private func addItem() {
        let clean = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let num = Double(clean) else { return }
        
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        ledgerStore.addItem(
            sectionName: selectedSection,
            key: itemName.trimmingCharacters(in: .whitespaces),
            rawAmount: num,
            note: noteText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : noteText.trimmingCharacters(in: .whitespaces)
        )
        dismiss()
    }
}
