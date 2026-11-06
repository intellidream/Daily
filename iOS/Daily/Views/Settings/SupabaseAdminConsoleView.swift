import SwiftUI
import Charts
import UIKit
import DailyCore

public enum SupabaseAdminSectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case quotas = "Quotas"
    case database = "Database"
    case gateway = "Gateway"
    case runtime = "Runtime"
    case fleet = "Fleet"

    public var id: String { rawValue }
}

/// Mobile-first iOS Cloud Observability & Usage Console for Supabase.
/// Strictly read-only, backed by 10-minute local snapshot caching and instant ShareLink / Clipboard Markdown export.
public struct SupabaseAdminConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var adminService = SupabaseAdminService.shared

    @State private var selectedFilter: SupabaseAdminSectionFilter = .all
    @State private var copyFeedback: String?
    @State private var showDisconnectConfirm = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [ThemeColors.bgStop0, ThemeColors.bgStop1, ThemeColors.bgStop2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        projectHeaderCard

                        if let err = adminService.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundColor(ThemeColors.error)
                                Text(err)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ThemeColors.error.opacity(0.18)))
                        }

                        if let snap = adminService.snapshot {
                            if !snap.resourceWarnings.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(snap.resourceWarnings, id: \.self) { w in
                                        Label(w, systemImage: "exclamationmark.triangle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(ThemeColors.warning)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(ThemeColors.warning.opacity(0.15)))
                            }

                            serviceHealthStrip(snap)
                            aiCopilotCard
                            filterPillsBar

                            if selectedFilter == .all || selectedFilter == .quotas {
                                executiveQuotasGrid(snap)
                                dailyEgressChartCard(snap)
                            }

                            if selectedFilter == .all || selectedFilter == .database {
                                databaseAndBloatCard(snap)
                                cronJobsCard(snap)
                            }

                            if selectedFilter == .all || selectedFilter == .gateway {
                                gatewayForensicsCard(snap)
                            }

                            if selectedFilter == .all || selectedFilter == .runtime {
                                functionsAndRealtimeCard(snap)
                            }

                            if selectedFilter == .all || selectedFilter == .fleet {
                                fleetAndAdvisorsCard(snap)
                            }

                            adminControlsFooter(snap)
                        } else if adminService.isLoading {
                            VStack(spacing: 14) {
                                ProgressView().tint(ThemeColors.accentCyan)
                                Text("Loading Supabase Cloud Telemetry...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 70)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await adminService.refreshSnapshot(force: true)
                }
            }
            .navigationTitle("Supabase Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ThemeColors.accentCyan)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let md = adminService.snapshot?.toMarkdownReport() {
                        ShareLink(item: md, preview: SharePreview("Supabase Forensic Report")) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                    Button {
                        Task { await adminService.refreshSnapshot(force: true) }
                    } label: {
                        if adminService.isLoading {
                            ProgressView().tint(ThemeColors.accentCyan)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                    .disabled(adminService.isLoading)
                }
            }
        }
        .task {
            await adminService.ensureLoadedOnAppear()
        }
        .confirmationDialog(
            "Disconnect Supabase Admin Session?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect & Clear Device Token", role: .destructive) {
                adminService.disconnect()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Project Header

    private var projectHeaderCard: some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text(adminService.snapshot?.project.name ?? "Daily Cloud")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let snap = adminService.snapshot {
                        Text(snap.orgPlan.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(ThemeColors.accentCyan))
                    }

                    Spacer()

                    Text("READ-ONLY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeColors.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ThemeColors.success.opacity(0.14)))
                }

                if let snap = adminService.snapshot {
                    Text("\(snap.computeTier) · \(snap.project.region) · PG \(snap.project.postgresVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }

                HStack {
                    if let id = adminService.credentials.adminIdentity {
                        Text("Admin: \(id)")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.textMuted)
                    }
                    Spacer()
                    if let msg = copyFeedback {
                        Text(msg)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColors.success)
                    } else if let ts = adminService.snapshot?.fetchedAt {
                        Text(ts.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.textMuted)
                    }
                }

                if let projects = adminService.snapshot?.availableProjects, projects.count > 1 {
                    Menu {
                        ForEach(projects) { p in
                            Button("\(p.name) (\(p.ref))") {
                                Task { await adminService.selectProject(ref: p.ref) }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Switch Project")
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    }
                }
            }
        }
    }

    private func serviceHealthStrip(_ snap: SupabaseAdminSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(snap.serviceHealth) { svc in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(svc.healthy ? ThemeColors.success : ThemeColors.error)
                            .frame(width: 7, height: 7)
                        Text(svc.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
    }

    private var aiCopilotCard: some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cloud SRE AI Analysis", systemImage: "sparkles")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Spacer()
                    Button {
                        Task { await adminService.analyzeWithAI() }
                    } label: {
                        HStack(spacing: 5) {
                            if adminService.isAnalyzingAI {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(adminService.aiAnalysis == nil ? "Analyze" : "Refresh")
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(ThemeColors.accentCyan))
                    }
                    .disabled(adminService.isAnalyzingAI)
                }

                if let analysis = adminService.aiAnalysis {
                    Text(.init(analysis))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.92))
                        .lineSpacing(3)
                } else {
                    Text("Inspect egress efficiency, index bloat ratios, and Realtime WAL CPU in one tap.")
                        .font(.system(size: 11.5))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
    }

    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SupabaseAdminSectionFilter.allCases) { f in
                    let active = selectedFilter == f
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = f
                        }
                    } label: {
                        Text(f.rawValue)
                            .font(.system(size: 12, weight: active ? .bold : .medium))
                            .foregroundColor(active ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(active ? ThemeColors.accentCyan : Color.white.opacity(0.08)))
                    }
                }
            }
        }
    }

    // MARK: - Quotas & Charts

    private func executiveQuotasGrid(_ snap: SupabaseAdminSnapshot) -> some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            quotaTile(
                title: snap.isExactBillingUsageAvailable ? "Egress (Cycle)" : "Egress (24h)",
                used: SupabaseAdminSnapshot.formatBytes(snap.egressUsedBytes),
                quota: SupabaseAdminSnapshot.formatBytes(snap.egressQuotaBytes),
                percent: snap.egressQuotaPercent
            )
            quotaTile(
                title: "Database",
                used: SupabaseAdminSnapshot.formatBytes(snap.dbSizeBytes),
                quota: SupabaseAdminSnapshot.formatBytes(snap.dbQuotaBytes),
                percent: snap.dbQuotaPercent
            )
            quotaTile(
                title: "Edge Calls",
                used: "\(snap.functionInvocations)",
                quota: "\(snap.functionInvocationsQuota)",
                percent: snap.functionInvocationsQuota > 0 ? (Double(snap.functionInvocations) * 100.0 / Double(snap.functionInvocationsQuota)) : 0
            )
            quotaTile(
                title: "Realtime Subs",
                used: "\(snap.realtimeActiveSubscriptions)",
                quota: "Peak \(snap.realtimePeakConnections)",
                percent: snap.realtimePeakConnectionsQuota > 0 ? (Double(snap.realtimePeakConnections) * 100.0 / Double(snap.realtimePeakConnectionsQuota)) : 0
            )
        }
    }

    private func quotaTile(title: String, used: String, quota: String, percent: Double) -> some View {
        let accent: Color = percent >= 95 ? ThemeColors.error : (percent >= 78 ? ThemeColors.warning : ThemeColors.accentCyan)
        return GlassCard(cornerRadius: 14, padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Spacer()
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                }
                Text(used)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("/ \(quota)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ThemeColors.textMuted)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(accent).frame(width: max(4, geo.size.width * CGFloat(min(1.0, percent / 100.0))))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private func dailyEgressChartCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Daily Bandwidth & Gateway Activity")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.white)

                if !snap.dailyEgress.isEmpty {
                    Chart {
                        ForEach(snap.dailyEgress.suffix(10)) { pt in
                            BarMark(x: .value("Day", String(pt.date.suffix(5))), y: .value("MB", Double(pt.restBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "REST"))
                            BarMark(x: .value("Day", String(pt.date.suffix(5))), y: .value("MB", Double(pt.functionBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "Edge"))
                            BarMark(x: .value("Day", String(pt.date.suffix(5))), y: .value("MB", Double(pt.realtimeBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "Realtime"))
                        }
                    }
                    .frame(height: 150)
                } else {
                    Text("24h HTTP: \(snap.http2xxCount24h) OK · \(snap.http4xxCount24h) 4xx · \(snap.http5xxCount24h) 5xx · MAU: \(snap.mauCount)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
    }

    // MARK: - Database & Cron

    private func databaseAndBloatCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PostgreSQL Tables & Index Bloat")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Hit \(String(format: "%.1f%%", snap.cacheHitRatioPercent))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeColors.accentCyan)
                }

                ForEach(snap.tables.prefix(12)) { tbl in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(tbl.schema).\(tbl.tableName)")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            if tbl.hasIndexBloatWarning {
                                Text("Bloat \(String(format: "%.1fx", tbl.bloatRatio))")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(ThemeColors.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(ThemeColors.warning.opacity(0.16)))
                            }
                            Text(SupabaseAdminSnapshot.formatBytes(tbl.totalBytes))
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        Text("Heap \(SupabaseAdminSnapshot.formatBytes(tbl.dataBytes)) · Idx \(SupabaseAdminSnapshot.formatBytes(tbl.indexBytes)) · Rows \(tbl.liveRows)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func cronJobsCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("pg_cron Retention Jobs")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.white)

                if snap.cronJobs.isEmpty {
                    Text("No active pg_cron jobs reported.")
                        .font(.system(size: 11.5))
                        .foregroundColor(ThemeColors.fgMutedDark)
                } else {
                    ForEach(snap.cronJobs) { job in
                        HStack {
                            Circle()
                                .fill(job.isSucceeded || job.status == "scheduled" ? ThemeColors.success : ThemeColors.error)
                                .frame(width: 7, height: 7)
                            Text(job.jobName)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Text(job.status)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Gateway, Runtime & Fleet

    private func gatewayForensicsCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top 24h HTTP Gateway Routes")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("4xx: \(snap.http4xxCount24h) · 5xx: \(snap.http5xxCount24h)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(snap.http5xxCount24h > 0 ? ThemeColors.error : ThemeColors.fgMutedDark)
                }

                ForEach(snap.topRoutes24h.prefix(8)) { r in
                    HStack {
                        Text("\(r.method) \(r.path)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(r.requests24h) · \(SupabaseAdminSnapshot.formatBytes(r.responseBytes24h))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }
        }
    }

    private func functionsAndRealtimeCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Edge Functions & Realtime WAL")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.white)

                Text("Realtime list_changes CPU: \(String(format: "%.1f%%", snap.realtimeWalCpuSharePercent)) (\(snap.realtimeActiveSubscriptions) subs)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(ThemeColors.accentCyan)

                ForEach(snap.edgeFunctions) { fn in
                    HStack {
                        Text("\(fn.slug) (v\(fn.version))")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(fn.invocations24h) calls · \(String(format: "%.0f ms", fn.avgExecutionMs))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }
        }
    }

    private func fleetAndAdvisorsCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("DayOne Ecosystem Fleet & Advisors")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.white)

                ForEach(snap.fleetDevices) { dev in
                    HStack(spacing: 8) {
                        Image(systemName: dev.sfSymbol)
                            .foregroundColor(ThemeColors.accentCyan)
                        Text(dev.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(dev.requests24h) req (\(String(format: "%.0f%%", dev.sharePercent)))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }

                let lints = snap.securityLints + snap.performanceLints
                if !lints.isEmpty {
                    Divider().background(Color.white.opacity(0.10))
                    ForEach(lints.prefix(5)) { lint in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(lint.level)] \(lint.title)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(lint.level == "ERROR" ? ThemeColors.error : ThemeColors.warning)
                            Text(lint.detail)
                                .font(.system(size: 10.5))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func adminControlsFooter(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { adminService.credentials.requireBiometrics },
                    set: { adminService.setRequireBiometrics($0) }
                )) {
                    Label("Require Face ID to Open Console", systemImage: "faceid")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .tint(ThemeColors.accentCyan)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = snap.toMarkdownReport()
                        copyFeedback = "Report copied!"
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(variant: .secondary, cornerRadius: 10))

                    Button {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(ThemeColors.error)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(variant: .plain, cornerRadius: 10))
                }
            }
        }
    }
}
