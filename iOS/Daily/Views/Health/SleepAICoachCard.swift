import SwiftUI
import DailyCore

/// Dedicated card presenting the AI Sleep Intelligence companion with interactive question prompts and chat dialog.
public struct SleepAICoachCard: View {
    public let aiContext: SleepAIContext
    public let session: SleepSession
    
    @State private var showingChatSheet: Bool = false
    @State private var selectedPrompt: String? = nil
    
    public init(aiContext: SleepAIContext, session: SleepSession) {
        self.aiContext = aiContext
        self.session = session
        if ProcessInfo.processInfo.arguments.contains("-testSleepChat") {
            self._showingChatSheet = State(initialValue: true)
            self._selectedPrompt = State(initialValue: "Este recomandat un antrenament cardio intens azi?")
        }
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header with AI Sparkle Badge
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("DAILY SLEEP INTELLIGENCE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "#00E676"))
                            .frame(width: 6, height: 6)
                        Text("AI Coach")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                
                // Conversational intro
                Text("Analyzing your \(session.totalAsleepFormatted) of sleep architecture against your personal circadian baseline:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                
                // Suggested Question Chips
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUGGESTED QUESTIONS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    
                    ForEach(aiContext.suggestedPrompts, id: \.self) { prompt in
                        Button(action: {
                            selectedPrompt = prompt
                            showingChatSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(ThemeColors.accentCyan)
                                Text(prompt)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Ask AI Button
                Button(action: {
                    selectedPrompt = nil
                    showingChatSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text("Ask Sleep AI a Question...")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [ThemeColors.accentCyan, Color(hex: "#80D8FF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingChatSheet) {
            SleepAIChatSheet(
                session: session,
                initialPrompt: selectedPrompt
            )
        }
    }
}

/// Modal sheet for interactive sleep consultations.
public struct SleepAIChatSheet: View {
    public let session: SleepSession
    public let initialPrompt: String?
    
    @Environment(\.presentationMode) var presentationMode
    @State private var userQuery: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating: Bool = false
    
    public struct ChatMessage: Identifiable {
        public let id = UUID()
        public let isUser: Bool
        public let text: String
    }
    
    public init(session: SleepSession, initialPrompt: String?) {
        self.session = session
        self.initialPrompt = initialPrompt
    }
    
    public var body: some View {
        NavigationView {
            LiquidGlassBackground {
                VStack(spacing: 0) {
                    // Chat messages list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { msg in
                                HStack(alignment: .top) {
                                    if msg.isUser {
                                        Spacer()
                                        Text(msg.text)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(ThemeColors.accentBlue)
                                            )
                                    } else {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 14))
                                                .foregroundColor(ThemeColors.accentCyan)
                                                .padding(.top, 2)
                                            
                                            Text(msg.text)
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundColor(.white.opacity(0.95))
                                                .lineSpacing(3)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .fill(Color.white.opacity(0.08))
                                                )
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            
                            if isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: ThemeColors.accentCyan))
                                        .scaleEffect(0.8)
                                    Text("Analyzing sleep architecture...")
                                        .font(.system(size: 12))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                                .padding(.leading, 8)
                            }
                        }
                        .padding(16)
                    }
                    
                    // Input bar
                    HStack(spacing: 10) {
                        TextField("Ask anything about your sleep...", text: $userQuery)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.08))
                            )
                        
                        Button(action: sendCurrentQuery) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(userQuery.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.3) : ThemeColors.accentCyan)
                        }
                        .disabled(userQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.4))
                }
            }
            .navigationTitle("Sleep Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
        .onAppear {
            setupInitialDialog()
        }
    }
    
    private func setupInitialDialog() {
        let initialGreeting = "Hello! I am your Daily Sleep Intelligence assistant. I have reviewed your latest session: \(session.totalAsleepFormatted) of total sleep with \(session.deepFormatted) of Deep sleep and \(session.remFormatted) of REM sleep. How can I help optimize your recovery today?"
        messages.append(ChatMessage(isUser: false, text: initialGreeting))
        
        if let query = initialPrompt, !query.isEmpty {
            userQuery = query
            sendCurrentQuery()
        }
    }
    
    private func sendCurrentQuery() {
        let query = userQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        
        messages.append(ChatMessage(isUser: true, text: query))
        userQuery = ""
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isGenerating = false
            let response = generateIntelligentResponse(for: query)
            messages.append(ChatMessage(isUser: false, text: response))
        }
    }
    
    private func generateIntelligentResponse(for query: String) -> String {
        let q = query.lowercased()
        let deepPct = session.deepPercent
        let remPct = session.remPercent
        let effPct = session.efficiencyPercent
        
        if q.contains("deep") || q.contains("profund") {
            return "Azi-noapte ai înregistrat \(session.deepFormatted) de Deep Sleep (\(deepPct)% din totalul somnului). Intervalul clinic recomandat este între 15% și 25%. Somnul profund este crucial pentru secreția hormonului de creștere și refacerea musculară. Pentru a-l crește diseară, păstrează dormitorul răcoros (18-20°C) și evită alimentele bogate în carbohidrați simpli cu 3 ore înainte de culcare."
        } else if q.contains("antrenament") || q.contains("cardio") || q.contains("effort") || q.contains("intens") {
            if session.sleepScore >= 75 {
                return "Cu un scor de somn de \(session.sleepScore) și o eficiență de \(effPct)%, sistemul tău nervos central și tonusul vagal sunt bine refăcute. Ești într-o stare optimă pentru un antrenament cu intensitate medie sau ridicată astăzi. Nu uita să te hidratezi bine!"
            } else {
                return "Scorul tău de somn a fost moderat (\(session.sleepScore)). Ținând cont de acumularea de oboseală, este recomandat să eviți un antrenament maximal sau cardio de mare intensitate. O sesiune de recuperare activă (mers alert 30 min, mobilitate sau stretching) va ajuta la refacere fără să suprasolicite sistemul cardiovascular."
            }
        } else if q.contains("rem") || q.contains("vis") {
            return "Somnul tău REM a fost de \(session.remFormatted) (\(remPct)% din somn). Stadiul REM este esențial pentru consolidarea memoriei, procesarea emoțiilor și claritatea mentală. Alcoolul și mesele copioase de seară suprimă masiv prima jumătate a somnului REM. Pentru o refacere cognitivă superioară, încearcă o rutină de 10 minute de citit înainte de culcare fără ecrane."
        } else if q.contains("trezir") || q.contains("awake") {
            return "Ai înregistrat \(session.awakeCount) treziri nocturne (în total \(session.awakeFormatted) de stare trează). Trezirile scurte (sub 3 minute) sunt fiziologice între ciclurile de 90 de minute, dar trezirile prelungite pot indica o temperatură ambientală prea ridicată, lumină ambientală sau fluctuații de cortizol/glicemie. Încearcă să nu bei cantități mari de apă în ultima oră înainte de somn."
        } else {
            return "Pe baza datelor din noaptea precedentă (\(session.totalAsleepFormatted) somn efectiv, \(effPct)% eficiență, \(session.restorativePercent)% stadii regenerative), corpul tău prezintă o curbă bună de refacere. Pentru a-ți menține ritmul circadian stabil, expune-te la lumină naturală în prima oră a dimineții și păstrează o oră de culcare consecventă."
        }
    }
}
