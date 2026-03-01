import SwiftUI
import MarkdownUI

// MARK: - Models

enum ResearchState: String, Equatable, Codable {
    case planning
    case searching
    case analyzing
    case completed
}

struct ResearchSource: Identifiable, Equatable, Codable {
    var id = UUID()
    let title: String
    let url: String
    let icon: String
}

struct ResearchReport: Identifiable, Equatable, Codable {
    var id = UUID()
    let title: String
    let abstract: String
    let content: String
    let sources: [ResearchSource]
}

struct ResearchSessionData: Identifiable, Equatable, Codable {
    let id: UUID
    var query: String
    var state: ResearchState = .planning
    var logs: [String] = []
    var sources: [ResearchSource] = []
    var report: ResearchReport?
    var progress: Double = 0.0
    var currentAction: String = ""
    var planSteps: [String] = []
}

// MARK: - Bubble View

struct ResearchBubbleView: View {
    let data: ResearchSessionData
    var onStart: () -> Void
    var onOpenReport: () -> Void
    var onShowDetails: () -> Void
    
    @Namespace private var animation
    @State private var isAnimating = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.indigo)
                Text("Deep Research (Alpha)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.indigo)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider().opacity(0.5)
            
            // Content based on State
            ZStack {
                if data.state == .planning {
                    planView
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if data.state == .completed {
                    completedView
                        .transition(.opacity.combined(with: .scale))
                } else {
                    progressView
                        .transition(.opacity)
                }
            }
            .padding(16)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: data.state)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .frame(maxWidth: 300)
    }
    
    // 1. PLAN VIEW
    private var planView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("План исследования")
                .font(.headline)
            
            Group {
                if data.planSteps.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Генерация стратегии...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            let stepsToShow = isExpanded ? data.planSteps : Array(data.planSteps.prefix(3))
                            ForEach(Array(stepsToShow.enumerated()), id: \.offset) { index, step in
                                stepRow(num: index + 1, text: step)
                            }
                        }
                        
                        if data.planSteps.count > 3 && !isExpanded {
                            Button(action: { withAnimation { isExpanded = true } }) {
                                Text("Показать еще \(data.planSteps.count - 3) шагов ⬇️")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Spacer().frame(height: 4)
                        
                        Button(action: onStart) {
                            Text("Подтвердить и начать")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.indigo)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
    
    private func stepRow(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.indigo)
                .frame(width: 16, height: 16)
                .padding(.top, 2)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // 2. PROGRESS VIEW (Live Activity Style)
    private var progressView: some View {
        Button(action: onShowDetails) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.indigo.opacity(0.2), lineWidth: 3)
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .onAppear {
                            withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                                isAnimating = true
                            }
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.currentAction)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                    
                    Text("\(Int(data.progress * 100))% завершено")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(4)
        }
        .buttonStyle(.plain)
    }
    
    // 3. COMPLETED VIEW
    private var completedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.bottom, 4)
            
            Text("Исследование готово")
                .font(.headline)
            
            Button(action: onOpenReport) {
                HStack {
                    Text("ОТКРЫТЬ ОТЧЕТ")
                        .fontWeight(.bold)
                        .tracking(1)
                    Image(systemName: "arrow.up.right")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }
}

// MARK: - Progress Sheet (Detail View)

struct ResearchProgressSheet: View {
    let data: ResearchSessionData
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Ход мыслей") {
                    ForEach(data.logs, id: \.self) { log in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(log)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                
                if !data.sources.isEmpty {
                    Section("Источники") {
                        ForEach(data.sources) { source in
                            HStack {
                                Image(systemName: source.icon)
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(source.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(source.url)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Статус исследования")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Report View (Magazine Style)

struct ResearchReportView: View {
    let report: ResearchReport
    @Environment(\.dismiss) var dismiss
    @State private var pdfURL: URL?
    @State private var showShareSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Cover Image / Header
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 250)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DEEP RESEARCH (ALPHA)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(report.title)
                            .font(.system(size: 32, weight: .bold, design: .serif)) // New York style
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .padding(24)
                }
                
                VStack(alignment: .leading, spacing: 24) {
                    // Abstract
                    VStack(alignment: .leading, spacing: 8) {
                        Text("АННОТАЦИЯ")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Text(report.abstract)
                            .font(.system(.body, design: .serif))
                            .italic()
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                    }
                    .padding(20)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Main Content
                    Markdown(report.content)
                        .markdownTheme(.research)
                    
                    Divider()
                    
                    // Sources Footer
                    Text("Источники")
                        .font(.headline)
                    
                    ForEach(report.sources) { source in
                        if let destination = URL(string: source.url),
                           let scheme = destination.scheme?.lowercased(),
                           ["http", "https"].contains(scheme) {
                            Link(destination: destination) {
                                Text("• \(source.title)")
                                    .font(.footnote)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            Text("• \(source.title)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 16) {
                // Menu Button
                Menu {
                    Button(action: {
                        generatePDF()
                        showShareSheet = true
                    }) {
                        Label("Экспорт в PDF / Поделиться", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: {
                        generatePDF()
                        if let url = pdfURL {
                            openInDocuments(url: url)
                        }
                    }) {
                        Label("Открыть в Документах", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Close Button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    @MainActor
    private func generatePDF() {
        let renderer = ImageRenderer(content: pdfContentView)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Research_Report.pdf")
        
        renderer.render { size, context in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
                return
            }
            
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        
        self.pdfURL = url
    }
    
    private var pdfContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(report.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Аннотация")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(report.abstract)
                .italic()
            
            Divider()
            
            Markdown(report.content)
                .markdownTheme(.research)
        }
        .padding(40)
        .frame(width: 595, height: 842) // A4 size points
        .foregroundColor(.black)
        .background(Color.white)
    }
    
    private func openInDocuments(url: URL) {
        let documentController = UIDocumentInteractionController(url: url)
        documentController.delegate = nil // Or implement delegate if needed
        documentController.presentPreview(animated: true)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension Theme {
    static let research = Theme.basic
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: .gray.opacity(0.3)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.gray.opacity(0.05))
                )
        }
        .tableCell { configuration in
            configuration.label
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
}
