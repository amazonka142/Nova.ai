import SwiftUI

struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ChatViewModel
    
    @State private var showActivationAlert = false
    @State private var selectedPlanForActivation = ""
    @State private var selectedPlan: String = "Free"
    
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    // Animation properties
    @State private var animateGradient = false
    @Namespace private var animationNamespace
    
    // Theme Colors based on selection
    var themeColor: Color {
        switch selectedPlan {
        case "Free": return .gray
        case "Pro": return .blue
        case "Max": return .purple
        default: return .gray
        }
    }
    
    var themeGradient: LinearGradient {
        switch selectedPlan {
        case "Free":
            return LinearGradient(colors: [Color.gray.opacity(0.8), Color.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Pro":
            return LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Max":
            return LinearGradient(colors: [Color.purple, Color.indigo, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        ZStack {
            // 1. Dynamic Background
            RadialGradient(gradient: Gradient(colors: [themeColor.opacity(0.12), Color(UIColor.systemBackground)]), center: .top, startRadius: 50, endRadius: 800)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: selectedPlan)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    // 2. Header
                    SubscriptionHeaderView(selectedLanguage: selectedLanguage, themeGradient: themeGradient, animateGradient: $animateGradient)
                        .padding(.top, 20)
                    
                    // 3. Custom Segmented Control
                    CustomPlanPicker(selectedPlan: $selectedPlan, animationNamespace: animationNamespace, themeColor: themeColor, selectedLanguage: selectedLanguage)
                    
                    // 4. Large Plan Card
                    PlanCardView(
                        plan: selectedPlan,
                        selectedLanguage: selectedLanguage,
                        themeGradient: themeGradient,
                        themeColor: themeColor
                    ) {
                        handlePlanAction()
                    }
                    .padding(.horizontal)
                    // Плавный переход при смене карточки
                    .id(selectedPlan)
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                    
                    // 5. Detailed Comparison
                    VStack(spacing: 20) {
                        Text(selectedLanguage == .russian ? "Сравнение возможностей" : "Compare Features")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        DetailedComparisonView(selectedPlan: selectedPlan, selectedLanguage: selectedLanguage)
                    }
                    .padding(.top, 10)
                    .padding(.horizontal)
                    
                    // Footer
                    Text(selectedLanguage == .russian ? "В этой версии оплата производится вручную через администратора." : "In this version, payment is processed manually via administrator.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            if viewModel.isMax { selectedPlan = "Max" }
            else if viewModel.isPro { selectedPlan = "Pro" }
            else { selectedPlan = "Free" }
            
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                animateGradient = true
            }
        }
        .alert("\(selectedLanguage == .russian ? "Активация" : "Activate") \(selectedPlanForActivation)", isPresented: $showActivationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(selectedLanguage == .russian ? "Напиши мне в Telegram @Vladik40perc, чтобы получить доступ. После оплаты я включу функции мгновенно." : "Write to me on Telegram @Vladik40perc to get access. I will enable features instantly after payment.")
        }
    }
    
    func handlePlanAction() {
        if selectedPlan == "Free" {
            dismiss()
        } else {
            selectedPlanForActivation = selectedPlan == "Pro" ? "Nova Pro" : "Nova Max"
            showActivationAlert = true
        }
    }
}

// MARK: - Components

struct SubscriptionHeaderView: View {
    let selectedLanguage: AppLanguage
    let themeGradient: LinearGradient
    @Binding var animateGradient: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundStyle(themeGradient)
                    .opacity(0.3)
                    .offset(x: -30, y: -10)
                    .blur(radius: 5)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(themeGradient)
                    .symbolEffect(.bounce, value: animateGradient)
            }
            .padding(.bottom, 10)
            
            Text("Nova AI")
                .font(.largeTitle)
                .fontWeight(.black)
                .overlay(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.5), .primary],
                        startPoint: animateGradient ? .topLeading : .bottomTrailing,
                        endPoint: animateGradient ? .bottomTrailing : .topLeading
                    )
                    .mask(Text("Nova AI").font(.largeTitle).fontWeight(.black))
                )
            
            Text(selectedLanguage == .russian ? "Разблокируйте полный потенциал nova.ai" : "Unlock full potential of nova.ai")
                .font(.body)
                .foregroundColor(.secondary)
            
            Text(selectedLanguage == .russian ? "Выберите подписку" : "Choose a subscription")
                .font(.headline)
                .padding(.top, 4)
        }
    }
}

struct CustomPlanPicker: View {
    @Binding var selectedPlan: String
    var animationNamespace: Namespace.ID
    var themeColor: Color
    var selectedLanguage: AppLanguage
    
    let plans = ["Free", "Pro", "Max"]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(plans, id: \.self) { plan in
                ZStack {
                    if selectedPlan == plan {
                        Capsule()
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            .matchedGeometryEffect(id: "ActiveTab", in: animationNamespace)
                    }
                    
                    Text(plan)
                        .font(.system(size: 16, weight: selectedPlan == plan ? .bold : .medium))
                        .foregroundColor(selectedPlan == plan ? themeColor : .secondary)
                        .padding(.vertical, 10)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedPlan = plan
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(Capsule())
        .padding(.horizontal, 40)
    }
}

struct PlanCardView: View {
    let plan: String
    let selectedLanguage: AppLanguage
    let themeGradient: LinearGradient
    let themeColor: Color
    let action: () -> Void
    
    var price: String {
        switch plan {
        case "Free": return selectedLanguage == .russian ? "0 ₽" : "$0"
        case "Pro": return selectedLanguage == .russian ? "299 ₽" : "$2.99"
        case "Max": return selectedLanguage == .russian ? "699 ₽" : "$6.99"
        default: return ""
        }
    }
    
    var period: String {
        selectedLanguage == .russian ? "/ месяц" : "/ month"
    }
    
    var description: String {
        switch plan {
        case "Free": return selectedLanguage == .russian ? "Начни свой путь" : "Start your journey"
        case "Pro": return selectedLanguage == .russian ? "Раскрой потенциал" : "Unlock your potential"
        case "Max": return selectedLanguage == .russian ? "Максимум возможностей" : "Maximize productivity"
        default: return ""
        }
    }
    
    var features: [String] {
        switch plan {
        case "Free":
            return selectedLanguage == .russian ? 
                ["Базовая модель Nova", "10 фактов памяти", "Текстовое общение"] :
                ["Basic Nova Model", "10 Memory Facts", "Text Chat"]
        case "Pro":
            return selectedLanguage == .russian ?
                ["GPT-5 Nano & Voice", "Поиск в интернете", "25 фактов памяти"] :
                ["GPT-5 Nano & Voice", "Web Search", "25 Memory Facts"]
        case "Max":
            let baseFeatures = selectedLanguage == .russian ?
                ["Всё из Nova Pro, плюс:", "GPT-5 Mini & DeepThink", "Deep Research (Alpha)", "Генерация картинок", "Анализ файлов"] :
                ["Everything in Nova Pro, plus:", "GPT-5 Mini & DeepThink", "Deep Research (Alpha)", "Image Generation", "File Analysis"]
            return baseFeatures
        default:
            return []
        }
    }
    
    var buttonText: String {
        if plan == "Free" {
            return selectedLanguage == .russian ? "Текущий план" : "Current Plan"
        }
        return selectedLanguage == .russian ? "Активировать \(plan)" : "Activate \(plan)"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Title & Price
            VStack(spacing: 5) {
                Text(plan.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(themeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(themeColor.opacity(0.1))
                    .clipShape(Capsule())
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.primary)
                    Text(period)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
            
            Divider()
                .padding(.horizontal)
            
            // Features List
            VStack(alignment: .leading, spacing: 12) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(themeColor)
                            .font(.system(size: 18))
                        
                        Text(feature)
                            .font(.system(size: 16))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            
            Spacer().frame(height: 10)
            
            // Action Button
            Button(action: action) {
                Text(buttonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(themeGradient)
                    .cornerRadius(16)
                    .shadow(color: themeColor.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
        .padding(24)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(themeColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)
    }
}

struct DetailedComparisonView: View {
    let selectedPlan: String
    let selectedLanguage: AppLanguage
    @State private var showProjectsInfo = false
    
    private var perDay: String {
        selectedLanguage == .russian ? "/д" : "/d"
    }
    
    private var perWeek: String {
        selectedLanguage == .russian ? "/н" : "/w"
    }
    
    private func daily(_ value: Int) -> String {
        "\(value)\(perDay)"
    }
    
    private func weekly(_ value: Int) -> String {
        "\(value)\(perWeek)"
    }
    
    private var comparisonSections: [ComparisonSectionModel] {
        [
            ComparisonSectionModel(
                id: "ai-models",
                title: selectedLanguage == .russian ? "AI модели" : "AI Models",
                rows: [
                    ComparisonItemModel(id: "nova-v1-rlhf", title: "Nova v1-RLHF", free: true, pro: true, max: true),
                    ComparisonItemModel(id: "gemini-flash-lite", title: "Gemini Flash Lite", free: true, pro: true, max: true),
                    ComparisonItemModel(id: "gpt-5-nano", title: "GPT-5 Nano", free: daily(10), pro: "check", max: "check"),
                    ComparisonItemModel(id: "gpt-5-mini", title: "GPT-5 Mini", free: "minus", pro: daily(100), max: "check"),
                    ComparisonItemModel(id: "nova-v1-rp", title: "Nova-v1-RP", free: daily(5), pro: weekly(50), max: weekly(150)),
                    ComparisonItemModel(id: "nova-v1-pro", title: "Nova-v1-Pro", free: "minus", pro: weekly(60), max: weekly(200)),
                    ComparisonItemModel(id: "deepthink", title: "DeepThink", free: "minus", pro: "minus", max: daily(30))
                ]
            ),
            ComparisonSectionModel(
                id: "features",
                title: selectedLanguage == .russian ? "Функции" : "Features",
                rows: [
                    ComparisonItemModel(
                        id: "memory",
                        title: selectedLanguage == .russian ? "Память (фактов)" : "Memory (facts)",
                        free: "10",
                        pro: "25",
                        max: "50"
                    ),
                    ComparisonItemModel(
                        id: "projects",
                        title: selectedLanguage == .russian ? "Проекты" : "Projects",
                        free: selectedLanguage == .russian ? "Ограниченно" : "Limited",
                        pro: selectedLanguage == .russian ? "Расширено" : "Extended",
                        max: "check",
                        hasInfoButton: true
                    ),
                    ComparisonItemModel(
                        id: "image-uploads",
                        title: selectedLanguage == .russian ? "Загрузка изображений" : "Image Uploads",
                        free: daily(10),
                        pro: daily(35),
                        max: daily(75)
                    ),
                    ComparisonItemModel(
                        id: "voice-chat",
                        title: selectedLanguage == .russian ? "Голосовое общение" : "Voice Chat",
                        free: false,
                        pro: true,
                        max: true
                    ),
                    ComparisonItemModel(
                        id: "web-search",
                        title: selectedLanguage == .russian ? "Поиск в интернете" : "Web Search",
                        free: false,
                        pro: true,
                        max: true
                    )
                ]
            ),
            ComparisonSectionModel(
                id: "advanced-features",
                title: selectedLanguage == .russian ? "Продвинутое" : "Advanced",
                rows: [
                    ComparisonItemModel(
                        id: "deep-research",
                        title: "Deep Research (Alpha)",
                        free: "minus",
                        pro: "minus",
                        max: weekly(10)
                    ),
                    ComparisonItemModel(
                        id: "image-generation",
                        title: selectedLanguage == .russian ? "Генерация картинок" : "Image Generation",
                        free: daily(20),
                        pro: "check",
                        max: "check"
                    ),
                    ComparisonItemModel(
                        id: "file-analysis",
                        title: selectedLanguage == .russian ? "Анализ файлов" : "File Analysis",
                        free: false,
                        pro: false,
                        max: true
                    )
                ]
            )
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
                Text(selectedLanguage == .russian ? "Функция" : "Feature")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Only show columns if screen is wide enough, otherwise simplifying or keeping as is. 
                // For simplicity, we keep the original 3 columns but highlight the selected one.
                HStack(spacing: 15) {
                    PlanHeader(text: "Free", selected: selectedPlan == "Free")
                    PlanHeader(text: "Pro", selected: selectedPlan == "Pro")
                    PlanHeader(text: "Max", selected: selectedPlan == "Max")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            Divider()
            
            VStack(spacing: 12) {
                ForEach(comparisonSections) { section in
                    ComparisonSectionCard(
                        section: section,
                        selectedPlan: selectedPlan
                    ) { item in
                        guard item.hasInfoButton else { return }
                        showProjectsInfo = true
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .sheet(isPresented: $showProjectsInfo) {
            ProjectsInfoSheet(selectedPlan: selectedPlan, selectedLanguage: selectedLanguage)
        }
    }
}

struct ComparisonSectionModel: Identifiable {
    let id: String
    let title: String
    let rows: [ComparisonItemModel]
}

struct ComparisonItemModel: Identifiable {
    let id: String
    let title: String
    let free: String
    let pro: String
    let max: String
    let hasInfoButton: Bool
    
    init(id: String, title: String, free: Bool, pro: Bool, max: Bool, hasInfoButton: Bool = false) {
        self.id = id
        self.title = title
        self.free = free ? "check" : "minus"
        self.pro = pro ? "check" : "minus"
        self.max = max ? "check" : "minus"
        self.hasInfoButton = hasInfoButton
    }
    
    init(id: String, title: String, free: String, pro: String, max: String, hasInfoButton: Bool = false) {
        self.id = id
        self.title = title
        self.free = free
        self.pro = pro
        self.max = max
        self.hasInfoButton = hasInfoButton
    }
}

struct ComparisonSectionCard: View {
    let section: ComparisonSectionModel
    let selectedPlan: String
    let onInfoTap: (ComparisonItemModel) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(section.title.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemFill))
            
            ForEach(section.rows) { row in
                ComparisonRow(
                    title: row.title,
                    free: row.free,
                    pro: row.pro,
                    max: row.max,
                    selectedPlan: selectedPlan,
                    infoAction: row.hasInfoButton ? { onInfoTap(row) } : nil
                )
            }
        }
        .background(Color(UIColor.systemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PlanHeader: View {
    let text: String
    let selected: Bool
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(selected ? .primary : .secondary)
            .frame(width: 45)
            .multilineTextAlignment(.center)
    }
}

struct ComparisonRow: View {
    let title: String
    let free: String
    let pro: String
    let max: String
    let selectedPlan: String
    let infoAction: (() -> Void)?
    
    init(title: String, free: Bool, pro: Bool, max: Bool, selectedPlan: String, infoAction: (() -> Void)? = nil) {
        self.title = title
        self.free = free ? "check" : "minus"
        self.pro = pro ? "check" : "minus"
        self.max = max ? "check" : "minus"
        self.selectedPlan = selectedPlan
        self.infoAction = infoAction
    }
    
    init(title: String, free: String, pro: String, max: String, selectedPlan: String, infoAction: (() -> Void)? = nil) {
        self.title = title
        self.free = free
        self.pro = pro
        self.max = max
        self.selectedPlan = selectedPlan
        self.infoAction = infoAction
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    
                    if let infoAction {
                        Button(action: infoAction) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                
                HStack(spacing: 15) {
                    StatusIcon(status: free, highlighted: selectedPlan == "Free")
                    StatusIcon(status: pro, highlighted: selectedPlan == "Pro")
                    StatusIcon(status: max, highlighted: selectedPlan == "Max")
                }
            }
            Divider().opacity(0.5)
        }
    }
}

struct StatusIcon: View {
    let status: String
    let highlighted: Bool
    
    var body: some View {
        Group {
            if status == "check" {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(highlighted ? .green : .gray)
            } else if status == "minus" {
                Image(systemName: "minus")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.3))
            } else {
                Text(status)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(highlighted ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: 45)
    }
}

struct ProjectsInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    let selectedPlan: String
    let selectedLanguage: AppLanguage
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Text(selectedLanguage == .russian ? "Проекты" : "Projects")
                        .font(.headline)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(selectedLanguage == .russian
                     ? "Детальная таблица возможностей проекта."
                     : "Detailed comparison for project features.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ProjectsComparisonTable(selectedPlan: selectedPlan, selectedLanguage: selectedLanguage)
                
                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct ProjectsComparisonTable: View {
    let selectedPlan: String
    let selectedLanguage: AppLanguage
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text(selectedLanguage == .russian ? "Функция" : "Feature")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 15) {
                    PlanHeader(text: "Free", selected: selectedPlan == "Free")
                    PlanHeader(text: "Pro", selected: selectedPlan == "Pro")
                    PlanHeader(text: "Max", selected: selectedPlan == "Max")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            Divider()
            
            VStack(spacing: 0) {
                ComparisonRow(title: selectedLanguage == .russian ? "Доступ к проектам" : "Project access", free: true, pro: true, max: true, selectedPlan: selectedPlan)
                ComparisonRow(title: selectedLanguage == .russian ? "Лимит проектов" : "Project limit", free: "1", pro: "5", max: "∞", selectedPlan: selectedPlan)
                ComparisonRow(title: selectedLanguage == .russian ? "База знаний (20 файлов)" : "Knowledge base (20 files)", free: "minus", pro: "minus", max: "check", selectedPlan: selectedPlan)
                ComparisonRow(title: selectedLanguage == .russian ? "Системные инструкции" : "Project brain", free: "minus", pro: "minus", max: "check", selectedPlan: selectedPlan)
                ComparisonRow(title: selectedLanguage == .russian ? "Память проекта" : "Project memory", free: true, pro: true, max: true, selectedPlan: selectedPlan)
                ComparisonRow(title: selectedLanguage == .russian ? "Изоляция памяти" : "Memory isolation", free: true, pro: true, max: true, selectedPlan: selectedPlan)
            }
            .padding(.top, 10)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}
