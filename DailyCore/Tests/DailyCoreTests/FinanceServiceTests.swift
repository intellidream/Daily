import Foundation
import Testing
@testable import DailyCore

@Suite("Finance Service & Models Tests")
struct FinanceServiceTests {
    
    @Test("Finance Account & Net Worth Recalculation")
    @MainActor
    func testFinanceSummaryCalculations() {
        let service = FinanceService.shared
        service.recalculateSummary()
        
        let summary = service.summary
        #expect(summary.netWorth > 0)
        #expect(summary.cashTotal > 0)
        #expect(summary.investmentsTotal > 0)
        #expect(summary.formattedNetWorth.contains("$"))
    }
    
    @Test("Macro Indicators 6 Core Pillars & Insights")
    func testMacroIndicatorInsights() {
        let indicators = [
            MacroIndicator(symbol: "CL=F", name: "Crude Oil", pillar: "Energy", emoji: "🛢️", currentPrice: 75.0, change: 1.5, percentChange: 2.0),
            MacroIndicator(symbol: "GC=F", name: "Gold", pillar: "Safe Haven", emoji: "🟡", currentPrice: 2800.0, change: -10.0, percentChange: -0.35),
            MacroIndicator(symbol: "DX-Y.NYB", name: "US Dollar", pillar: "The King", emoji: "💵", currentPrice: 104.0, change: 0.2, percentChange: 0.19),
            MacroIndicator(symbol: "^NDX", name: "Nasdaq 100", pillar: "Tech/Growth", emoji: "💻", currentPrice: 21500.0, change: 120.0, percentChange: 0.56),
            MacroIndicator(symbol: "BTC-USD", name: "Bitcoin", pillar: "Risk/Future", emoji: "₿", currentPrice: 96000.0, change: -1200.0, percentChange: -1.23),
            MacroIndicator(symbol: "^VIX", name: "VIX", pillar: "Stress", emoji: "📊", currentPrice: 32.5, change: 5.0, percentChange: 18.0)
        ]
        
        #expect(indicators[0].insight == "Energy costs rising — inflation pressure")
        #expect(indicators[1].insight == "Confidence returning — risk-on")
        #expect(indicators[2].insight == "Dollar strong — pressure on emerging markets")
        #expect(indicators[3].insight == "Tech optimism — growth mode")
        #expect(indicators[4].insight == "Risk-off — caution prevails")
        #expect(indicators[5].insight.contains("Markets panicking"))
    }
    
    @Test("Country Economic Data Real Rate Calculation")
    func testCountryEconomicRealRate() {
        let us = CountryEconomicData(countryCode: "US", countryName: "United States", currencyCode: "USD", interestRate: 4.50, inflationRate: 2.80, region: "Americas")
        #expect(abs(us.realRate - 1.70) < 0.001)
        #expect(us.flagEmoji.isEmpty == false)
        #expect(us.formattedRealRate == "+1.70%")
        
        let tr = CountryEconomicData(countryCode: "TR", countryName: "Turkey", currencyCode: "TRY", interestRate: 42.50, inflationRate: 44.00, region: "Europe")
        #expect(abs(tr.realRate - (-1.50)) < 0.001)
        #expect(tr.formattedRealRate == "-1.50%")
    }
    
    @Test("Add Transaction Recalculates Account Balance")
    @MainActor
    func testAddTransactionRecalculation() {
        let service = FinanceService.shared
        guard let checking = service.accounts.first(where: { $0.type == .checking }) else {
            Issue.record("Missing checking account")
            return
        }
        
        let initialBalance = checking.currentBalance
        let depositAmount = 500.0
        
        service.addTransaction(
            accountId: checking.id,
            amount: depositAmount,
            category: "Bonus",
            description: "Performance Bonus"
        )
        
        let updatedChecking = service.accounts.first(where: { $0.id == checking.id })
        #expect(updatedChecking?.currentBalance == initialBalance + depositAmount)
    }
}
