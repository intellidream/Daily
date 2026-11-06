import SwiftUI
import Charts
import AppKit
import DailyCore

public enum SupabaseAdminSectionFilter: String, CaseIterable, Identifiable {
    case all = "All Telemetry"
    case quotas = "Quotas & Egress"
    case database = "Database & Bloat"
    case gateway = "Gateway & Logs"
    case runtime = "Functions & Realtime"
    case fleet = "Fleet & Advisors"

    public var id: String { rawValue }
}

/// Native macOS Cloud Observability & Usage Console for Supabase.
/// Strictly read-only, backed by 10-minute local snapshot caching and instant Markdown forensic export.
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

                VStack(spacing: 0) {
                    topConsoleToolbar
                    Divider().background(Color.white.opacity(0.12))

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let err = adminService.errorMessage {
                                errorBanner(err)
                            }

                            if let snap = adminService.snapshot {
                                if !snap.resourceWarnings.isEmpty {
                                    warningsBanner(snap.resourceWarnings)
                                }

                                serviceHealthStrip(snap)
                                aiCopilotCard(snap)
                                filterPillsBar

                                if selectedFilter == .all || selectedFilter == .quotas {
                                    executiveQuotasGrid(snap)
                                    dailyEgressChartCard(snap)
                                }

                                if selectedFilter == .all || selectedFilter == .database {
                                    databaseAndBloatCard(snap)
                                    cronAndTopSqlGrid(snap)
                                }

                                if selectedFilter == .all || selectedFilter == .gateway {
                                    gatewayForensicsCard(snap)
                                }

                                if selectedFilter == .all || selectedFilter == .runtime {
                                    functionsAndRealtimeGrid(snap)
                                }

                                if selectedFilter == .all || selectedFilter == .fleet {
                                    fleetAndAdvisorsGrid(snap)
                                }
                            } else if adminService.isLoading {
                                VStack(spacing: 14) {
                                    ProgressView()
                                        .tint(ThemeColors.accentCyan)
                                    Text("Aggregating live Supabase telemetry (Quotas, ClickHouse Logs, pg_catalog, Edge & Realtime)...")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 90)
                            } else {
                                emptyStateCard
                            }
                        }
                        .padding(22)
                    }
                }
            }
            .frame(minWidth: 920, idealWidth: 1060, maxWidth: 1280, minHeight: 720, idealHeight: 840, maxHeight: 980)
        }
        .task {
            await adminService.ensureLoadedOnAppear()
        }
        .confirmationDialog(
            "Disconnect Supabase Admin Session?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect & Clear Local Token", role: .destructive) {
                adminService.disconnect()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Top Toolbar

    private var topConsoleToolbar: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(ThemeColors.accentCyan.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "server.rack")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(adminService.snapshot?.project.name ?? "Supabase Cloud Console")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let snap = adminService.snapshot {
                        Text(snap.orgPlan.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(ThemeColors.accentCyan))

                        Text("\(snap.computeTier) · \(snap.project.region) · PG \(snap.project.postgresVersion)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Text("READ-ONLY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeColors.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ThemeColors.success.opacity(0.14)))
                }

                HStack(spacing: 10) {
                    if let id = adminService.credentials.adminIdentity {
                        Text("Admin: \(id)")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    if let fetched = adminService.snapshot?.fetchedAt {
                        Text("Snapshot: \(fetched.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.textMuted)
                    }
                    if let msg = copyFeedback {
                        Text(msg)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColors.success)
                    }
                }
            }

            Spacer()

            if let projects = adminService.snapshot?.availableProjects, projects.count > 1 {
                Menu {
                    ForEach(projects) { p in
                        Button {
                            Task { await adminService.selectProject(ref: p.ref) }
                        } label: {
                            HStack {
                                Text("\(p.name) (\(p.ref))")
                                if p.ref == adminService.credentials.selectedProjectRef {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Project", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Toggle(isOn: Binding(
                get: { adminService.credentials.requireBiometrics },
                set: { adminService.setRequireBiometrics($0) }
            )) {
                Label("Touch ID", systemImage: "touchid")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Button {
                copyMarkdownReport()
            } label: {
                Label("Copy .md", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(GlassButtonStyle(variant: .secondary, cornerRadius: 9))
            .disabled(adminService.snapshot == nil)

            Button {
                saveMarkdownReportToFile()
            } label: {
                Label("Save Report", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(GlassButtonStyle(variant: .secondary, cornerRadius: 9))
            .disabled(adminService.snapshot == nil)

            Button {
                Task { await adminService.refreshSnapshot(force: true) }
            } label: {
                HStack(spacing: 5) {
                    if adminService.isLoading {
                        ProgressView().controlSize(.small).tint(ThemeColors.accentCyan)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)
            }
            .buttonStyle(GlassButtonStyle(variant: .secondary, cornerRadius: 9))
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(adminService.isLoading)

            Button {
                showDisconnectConfirm = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(ThemeColors.error)
            }
            .buttonStyle(GlassButtonStyle(variant: .plain, cornerRadius: 9))
            .help("Disconnect Supabase Admin Session")

            Button("Done") {
                dismiss()
            }
            .buttonStyle(GlassButtonStyle(variant: .primary, cornerRadius: 9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.35))
    }

    // MARK: - Banners & Health Strip

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundColor(ThemeColors.error)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ThemeColors.error.opacity(0.18)))
    }

    private func warningsBanner(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(warnings, id: \.self) { w in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(ThemeColors.warning)
                    Text(w)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ThemeColors.warning.opacity(0.16)))
    }

    private func serviceHealthStrip(_ snap: SupabaseAdminSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(snap.serviceHealth) { svc in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(svc.healthy ? ThemeColors.success : ThemeColors.error)
                            .frame(width: 7, height: 7)
                        Text(svc.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        Text(svc.healthy ? "Healthy" : svc.status)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(svc.healthy ? ThemeColors.success : ThemeColors.error)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    )
                }
            }
        }
    }

    // MARK: - AI SRE Co-Pilot Card

    private func aiCopilotCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cloud SRE AI Diagnostic Co-Pilot", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Spacer()
                    Button {
                        Task { await adminService.analyzeWithAI() }
                    } label: {
                        HStack(spacing: 6) {
                            if adminService.isAnalyzingAI {
                                ProgressView().controlSize(.small).tint(.black)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(adminService.aiAnalysis == nil ? "Analyze with AI" : "Re-Analyze")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(ThemeColors.accentCyan))
                    }
                    .buttonStyle(.plain)
                    .disabled(adminService.isAnalyzingAI)
                }

                if let analysis = adminService.aiAnalysis {
                    Text(.init(analysis))
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.92))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else {
                    Text("Synthesize Egress drivers, PostgreSQL B-tree index bloat, Realtime WAL load, and Advisor lints into actionable recommendations.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
    }

    private var filterPillsBar: some View {
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
                        .background(
                            Capsule()
                                .fill(active ? ThemeColors.accentCyan : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - 1. Executive Quota Grid

    private func executiveQuotasGrid(_ snap: SupabaseAdminSnapshot) -> some View {
        let cols = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        return LazyVGrid(columns: cols, spacing: 14) {
            quotaGaugeTile(
                title: snap.isExactBillingUsageAvailable ? "Unified Egress (Cycle)" : "Gateway Egress (24h)",
                icon: "arrow.up.right.circle.fill",
                usedLabel: SupabaseAdminSnapshot.formatBytes(snap.egressUsedBytes),
                quotaLabel: SupabaseAdminSnapshot.formatBytes(snap.egressQuotaBytes),
                percent: snap.egressQuotaPercent,
                subtitle: snap.cachedEgressUsedBytes > 0
                    ? "Cached CDN: \(SupabaseAdminSnapshot.formatBytes(snap.cachedEgressUsedBytes))"
                    : "24h HTTP: \(snap.totalHttpRequests24h) reqs"
            )
            quotaGaugeTile(
                title: "Database Size",
                icon: "cylinder.split.1x2.fill",
                usedLabel: SupabaseAdminSnapshot.formatBytes(snap.dbSizeBytes),
                quotaLabel: SupabaseAdminSnapshot.formatBytes(snap.dbQuotaBytes),
                percent: snap.dbQuotaPercent,
                subtitle: "Heap \(SupabaseAdminSnapshot.formatBytes(snap.heapDataBytes)) · Idx \(SupabaseAdminSnapshot.formatBytes(snap.indexTotalBytes))"
            )
            quotaGaugeTile(
                title: "Edge Function Calls",
                icon: "bolt.horizontal.circle.fill",
                usedLabel: "\(snap.functionInvocations)",
                quotaLabel: "\(snap.functionInvocationsQuota)",
                percent: snap.functionInvocationsQuota > 0 ? (Double(snap.functionInvocations) * 100.0 / Double(snap.functionInvocationsQuota)) : 0,
                subtitle: "\(snap.edgeFunctions.count) deployed functions"
            )
            quotaGaugeTile(
                title: "Realtime & Auth MAU",
                icon: "dot.radiowaves.left.and.right",
                usedLabel: "\(snap.realtimeActiveSubscriptions) live subs",
                quotaLabel: "Peak \(snap.realtimePeakConnections)/\(snap.realtimePeakConnectionsQuota)",
                percent: snap.realtimePeakConnectionsQuota > 0 ? (Double(snap.realtimePeakConnections) * 100.0 / Double(snap.realtimePeakConnectionsQuota)) : 0,
                subtitle: "MAU: \(snap.mauCount) · Logs: \(snap.logIngestionEvents)"
            )
        }
    }

    private func quotaGaugeTile(
        title: String,
        icon: String,
        usedLabel: String,
        quotaLabel: String,
        percent: Double,
        subtitle: String
    ) -> some View {
        let accent: Color = percent >= 95 ? ThemeColors.error : (percent >= 78 ? ThemeColors.warning : ThemeColors.accentCyan)
        return GlassCard(cornerRadius: 16, padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(accent)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", percent))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(usedLabel)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("/ \(quotaLabel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeColors.textMuted)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(accent)
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, percent / 100.0))))
                    }
                }
                .frame(height: 6)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 2. Daily Egress & API Volume Chart

    private func dailyEgressChartCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Bandwidth & Gateway Request Distribution", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Storage: \(SupabaseAdminSnapshot.formatBytes(snap.storageSizeBytes)) / \(SupabaseAdminSnapshot.formatBytes(snap.storageQuotaBytes))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }

                if !snap.dailyEgress.isEmpty {
                    Chart {
                        ForEach(snap.dailyEgress) { pt in
                            BarMark(x: .value("Date", String(pt.date.suffix(5))), y: .value("MB", Double(pt.restBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "PostgREST"))
                            BarMark(x: .value("Date", String(pt.date.suffix(5))), y: .value("MB", Double(pt.functionBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "Edge Functions"))
                            BarMark(x: .value("Date", String(pt.date.suffix(5))), y: .value("MB", Double(pt.realtimeBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "Realtime"))
                            BarMark(x: .value("Date", String(pt.date.suffix(5))), y: .value("MB", Double(pt.authBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "Auth"))
                            BarMark(x: .value("Date", String(pt.date.suffix(5))), y: .value("MB", Double(pt.storageBytes) / 1_048_576.0))
                                .foregroundStyle(by: .value("Service", "Storage"))
                        }
                    }
                    .frame(height: 180)
                    .chartYAxisLabel("MB")
                } else if !snap.apiCounts24h.isEmpty {
                    Chart {
                        ForEach(snap.apiCounts24h) { pt in
                            BarMark(x: .value("Window", String(pt.timestamp.prefix(16).suffix(5))), y: .value("Requests", pt.restRequests))
                                .foregroundStyle(by: .value("Service", "REST"))
                            BarMark(x: .value("Window", String(pt.timestamp.prefix(16).suffix(5))), y: .value("Requests", pt.authRequests))
                                .foregroundStyle(by: .value("Service", "Auth"))
                            BarMark(x: .value("Window", String(pt.timestamp.prefix(16).suffix(5))), y: .value("Requests", pt.realtimeRequests))
                                .foregroundStyle(by: .value("Service", "Realtime"))
                        }
                    }
                    .frame(height: 165)
                } else {
                    Text("No multi-day billing egress points returned yet for this window.")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }
        }
    }

    // MARK: - 3. PostgreSQL Storage & B-Tree Index Bloat

    private func databaseAndBloatCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("PostgreSQL Storage, Table Footprint & B-Tree Index Bloat", systemImage: "internaldrive.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Cache Hit: \(String(format: "%.2f%%", snap.cacheHitRatioPercent)) · Active Conns: \(snap.activeDbConnections) · gp3 \(snap.diskIops) IOPS (\(snap.diskThroughputMibps) MiB/s)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeColors.accentCyan)
                }

                HStack(spacing: 12) {
                    Text("Table")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Heap Data")
                        .frame(width: 90, alignment: .trailing)
                    Text("Indexes")
                        .frame(width: 90, alignment: .trailing)
                    Text("Total")
                        .frame(width: 90, alignment: .trailing)
                    Text("Live / Dead")
                        .frame(width: 110, alignment: .trailing)
                    Text("Health")
                        .frame(width: 115, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ThemeColors.textMuted)

                Divider().background(Color.white.opacity(0.10))

                ForEach(snap.tables.prefix(16)) { tbl in
                    HStack(spacing: 12) {
                        Text("\(tbl.schema).\(tbl.tableName)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(SupabaseAdminSnapshot.formatBytes(tbl.dataBytes))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .frame(width: 90, alignment: .trailing)

                        Text(SupabaseAdminSnapshot.formatBytes(tbl.indexBytes))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(tbl.hasIndexBloatWarning ? ThemeColors.warning : ThemeColors.fgMutedDark)
                            .frame(width: 90, alignment: .trailing)

                        Text(SupabaseAdminSnapshot.formatBytes(tbl.totalBytes))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 90, alignment: .trailing)

                        Text("\(tbl.liveRows) / \(tbl.deadRows)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(tbl.deadRows > 1000 ? ThemeColors.warning : ThemeColors.fgMutedDark)
                            .frame(width: 110, alignment: .trailing)

                        Group {
                            if tbl.hasIndexBloatWarning {
                                Text("Bloat \(String(format: "%.1fx", tbl.bloatRatio))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(ThemeColors.warning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(ThemeColors.warning.opacity(0.16)))
                            } else {
                                Text("Nominal")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(ThemeColors.success)
                            }
                        }
                        .frame(width: 115, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func cronAndTopSqlGrid(_ snap: SupabaseAdminSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("pg_cron Retention & Scheduled Jobs", systemImage: "clock.arrow.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    if snap.cronJobs.isEmpty {
                        Text("No scheduled pg_cron jobs detected or accessible.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    } else {
                        ForEach(snap.cronJobs) { job in
                            HStack {
                                Circle()
                                    .fill(job.isSucceeded || job.status == "scheduled" ? ThemeColors.success : ThemeColors.error)
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.jobName)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text("\(job.schedule) · \(job.status)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                                Spacer()
                                if let ms = job.durationMs {
                                    Text(String(format: "%.0f ms", ms))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Top SQL Statements (pg_stat_statements)", systemImage: "terminal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    if snap.topSqlStatements.isEmpty {
                        Text("No statement execution metrics available.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    } else {
                        ForEach(snap.topSqlStatements.prefix(6)) { sql in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sql.queryPreview)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("Calls: \(sql.calls) · Total: \(String(format: "%.0f ms", sql.totalExecTimeMs)) · Mean: \(String(format: "%.2f ms", sql.meanExecTimeMs))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 4. ClickHouse Logs & Gateway Forensics

    private func gatewayForensicsCard(_ snap: SupabaseAdminSnapshot) -> some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("ClickHouse Unified Logs & Top HTTP Bandwidth Routes (24h)", systemImage: "network")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 12) {
                        Text("2xx: \(snap.http2xxCount24h)")
                            .foregroundColor(ThemeColors.success)
                        Text("4xx: \(snap.http4xxCount24h)")
                            .foregroundColor(snap.http4xxCount24h > 0 ? ThemeColors.warning : ThemeColors.fgMutedDark)
                        Text("5xx: \(snap.http5xxCount24h)")
                            .foregroundColor(snap.http5xxCount24h > 0 ? ThemeColors.error : ThemeColors.fgMutedDark)
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                if !snap.logCountsBySource.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(snap.logCountsBySource.sorted(by: { $0.value > $1.value }), id: \.key) { src, cnt in
                                Text("\(src): \(cnt)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(ThemeColors.accentCyan.opacity(0.12)))
                            }
                        }
                    }
                }

                ForEach(snap.topRoutes24h.prefix(10)) { route in
                    HStack(spacing: 10) {
                        Text(route.method)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeColors.accentCyan)
                            .frame(width: 46, alignment: .leading)
                        Text(route.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(route.requests24h) req")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .frame(width: 80, alignment: .trailing)
                        Text(SupabaseAdminSnapshot.formatBytes(route.responseBytes24h))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 90, alignment: .trailing)
                        Text(String(format: "%.0f ms", route.avgLatencyMs))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .frame(width: 65, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }

                if !snap.recentErrors24h.isEmpty {
                    Divider().background(Color.white.opacity(0.10))
                    Text("Recent 4xx / 5xx Gateway Events")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.warning)

                    ForEach(snap.recentErrors24h.prefix(6)) { err in
                        HStack(spacing: 8) {
                            Text("\(err.statusCode)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(err.statusCode >= 500 ? ThemeColors.error : ThemeColors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                            Text("\(err.method) \(err.path)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(String(err.timestamp.prefix(19)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ThemeColors.textMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Edge Functions & Realtime WAL

    private func functionsAndRealtimeGrid(_ snap: SupabaseAdminSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Edge Functions (24h Combined Stats)", systemImage: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    if snap.edgeFunctions.isEmpty {
                        Text("No Edge Functions deployed on this project.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    } else {
                        ForEach(snap.edgeFunctions) { fn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(fn.slug)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                        Text("v\(fn.version)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(ThemeColors.accentCyan)
                                    }
                                    Text("JWT: \(fn.verifyJwt ? "Enforced" : "Off") · Avg \(String(format: "%.0f ms", fn.avgExecutionMs))")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(fn.invocations24h) calls")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text(String(format: "%.1f%% OK", fn.successRatePercent))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(fn.errors24h == 0 ? ThemeColors.success : ThemeColors.warning)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Realtime Elixir & WAL Poller", systemImage: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    HStack {
                        Text("Active Subscriptions:")
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Spacer()
                        Text("\(snap.realtimeActiveSubscriptions)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    .font(.system(size: 12))

                    HStack {
                        Text("realtime.list_changes SQL CPU:")
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Spacer()
                        Text("\(String(format: "%.1f%%", snap.realtimeWalCpuSharePercent)) (\(snap.realtimeWalListChangesCalls) calls)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(snap.realtimeWalCpuSharePercent > 25 ? ThemeColors.warning : ThemeColors.success)
                    }
                    .font(.system(size: 12))

                    if !snap.realtimeSubscriptionsByTable.isEmpty {
                        Divider().background(Color.white.opacity(0.10))
                        ForEach(snap.realtimeSubscriptionsByTable.sorted(by: { $0.value > $1.value }), id: \.key) { entity, cnt in
                            HStack {
                                Text(entity)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(cnt) subs")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 6. DayOne Ecosystem Fleet & Advisors

    private func fleetAndAdvisorsGrid(_ snap: SupabaseAdminSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("DayOne Ecosystem Fleet Footprint (24h)", systemImage: "laptopcomputer.and.iphone")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("Sessions: \(snap.activeAuthSessionsCount) · Watches: \(snap.pairedWatchesCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeColors.accentCyan)
                    }

                    if snap.fleetDevices.isEmpty {
                        Text("No recent HTTP User-Agent traffic buckets recorded in the last 24h.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    } else {
                        ForEach(snap.fleetDevices) { dev in
                            HStack(spacing: 10) {
                                Image(systemName: dev.sfSymbol)
                                    .foregroundColor(ThemeColors.accentCyan)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                    if !dev.registeredSources.isEmpty {
                                        Text(dev.registeredSources.joined(separator: ", "))
                                            .font(.system(size: 10))
                                            .foregroundColor(ThemeColors.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text("\(dev.requests24h) req (\(String(format: "%.0f%%", dev.sharePercent))) · \(SupabaseAdminSnapshot.formatBytes(dev.responseBytes24h))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Supabase Performance & Security Advisors", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    let combined = snap.securityLints + snap.performanceLints
                    if combined.isEmpty {
                        Text("Zero Security or Performance advisor lints active.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.success)
                    } else {
                        ForEach(combined.prefix(8)) { lint in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("\(lint.category) · \(lint.level)")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(lint.level == "ERROR" ? ThemeColors.error : ThemeColors.warning)
                                    Text(lint.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                                Text(lint.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyStateCard: some View {
        GlassCard(cornerRadius: 16, padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 28))
                    .foregroundColor(ThemeColors.accentCyan)
                Text("No Telemetry Snapshot Loaded")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Button("Fetch Live Telemetry") {
                    Task { await adminService.refreshSnapshot(force: true) }
                }
                .buttonStyle(GlassButtonStyle(variant: .primary, cornerRadius: 10))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Export Actions

    private func copyMarkdownReport() {
        guard let md = adminService.snapshot?.toMarkdownReport() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        copyFeedback = "Copied forensic Markdown report!"
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            copyFeedback = nil
        }
    }

    private func saveMarkdownReportToFile() {
        guard let snap = adminService.snapshot else { return }
        let md = snap.toMarkdownReport()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Supabase_Telemetry_\(snap.project.ref).md"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? md.write(to: url, atomically: true, encoding: .utf8)
                Task { @MainActor in
                    self.copyFeedback = "Saved \(url.lastPathComponent)"
                }
            }
        }
    }
}
