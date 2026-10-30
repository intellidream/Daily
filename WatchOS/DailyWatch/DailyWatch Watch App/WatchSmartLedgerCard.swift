import SwiftUI
import WatchKit

struct WatchSmartLedgerCard: View {
    @ObservedObject private var store = WatchSmartLedgerStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#10B981"))
                Text("SMART LEDGER")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "#10B981"))
                    .tracking(0.5)

                Spacer()

                if store.isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        Task {
                            await store.fetchLedgerData(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Net Worth Hero
            VStack(alignment: .leading, spacing: 1) {
                Text(store.netWorth)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(store.netWorthEUR)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#34D399"))
            }

            // 2 Metric Chips: Deposits & Balance
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("DEPOSITS")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color(hex: "#10B981"))
                    Text(store.deposits)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(hex: "#10B981").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text("BALANCE")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color(hex: "#00E5FF"))
                    Text(store.sold)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(hex: "#00E5FF").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider().background(Color.white.opacity(0.08))

            // Quick Adjust Steppers
            Text("QUICK ADJUST (1-TAP)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .tracking(0.4)

            VStack(spacing: 5) {
                ForEach(store.items) { item in
                    WatchSmartLedgerItemRow(item: item) { delta in
                        store.adjustItem(lineIndex: item.lineIndex, deltaRaw: delta)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#0F2018").opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#10B981").opacity(0.3), lineWidth: 1)
        )
    }
}

private struct WatchSmartLedgerItemRow: View {
    let item: WatchSmartLedgerQuickItem
    let onAdjust: (Double) -> Void

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(item.displaySubtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer(minLength: 2)

            Text(item.displayAmount)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#34D399"))
                .padding(.trailing, 2)

            // Steppers [-] and [+]
            HStack(spacing: 3) {
                Button {
                    let step = item.isScaled ? 1.0 : (item.rawAmount >= 500 ? 100.0 : 50.0)
                    onAdjust(-step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    let step = item.isScaled ? 1.0 : (item.rawAmount >= 500 ? 100.0 : 50.0)
                    onAdjust(step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: "#10B981").opacity(0.35))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
