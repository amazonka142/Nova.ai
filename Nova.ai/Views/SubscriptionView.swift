import SwiftUI

struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ChatViewModel
    
    @State private var showActivationAlert = false
    @State private var selectedPlanForActivation = ""
    @State private var selectedPlan: String = "Free"
    
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Text("Nova Pro")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(selectedLanguage == .russian ? "Раскрой полный потенциал" : "Unlock Full Potential")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Plan Selector
                HStack(spacing: 15) {
                    PlanButton(title: "Free", color: .gray, selectedPlan: $selectedPlan)
                    PlanButton(title: "Pro", color: .blue, selectedPlan: $selectedPlan)
                    PlanButton(title: "Max", color: .purple, selectedPlan: $selectedPlan)
                }
                .padding(.horizontal)
                
                // --- ТАБЛИЦА СРАВНЕНИЯ ---
                VStack(spacing: 0) {
                    // Заголовки таблицы
                    HStack(alignment: .bottom) {
                        Text(selectedLanguage == .russian ? "Функции" : "Features")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Колонки тарифов
                        HStack(spacing: 20) {
                            HeaderTitle(text: "Free", color: .gray, isSelected: selectedPlan == "Free")
                            HeaderTitle(text: "Pro", color: .blue, isSelected: selectedPlan == "Pro")
                            HeaderTitle(text: "Max", color: .purple, isSelected: selectedPlan == "Max")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    Divider().opacity(0.5)
                    
                    // Список функций
                    VStack(spacing: 25) {
                        // Блок 1: Мозги
                        Group {
                            ComparisonRow(title: "Nova v1-RLHF", free: true, pro: true, max: true, selectedPlan: selectedPlan)
                            ComparisonRow(title: "Gemini Flash Lite", free: true, pro: true, max: true, selectedPlan: selectedPlan)
                            ComparisonRow(title: "GPT-5 Nano", free: selectedLanguage == .russian ? "10/д" : "10/d", pro: "check", max: "check", selectedPlan: selectedPlan)
                            ComparisonRow(title: "GPT-5 Mini", free: "minus", pro: selectedLanguage == .russian ? "100/д" : "100/d", max: "check", selectedPlan: selectedPlan)
                            ComparisonRow(title: "Nova-v1-RP", free: selectedLanguage == .russian ? "5/д" : "5/d", pro: selectedLanguage == .russian ? "50/н" : "50/w", max: selectedLanguage == .russian ? "150/н" : "150/w", selectedPlan: selectedPlan)
                            ComparisonRow(title: "Nova-v1-Pro", free: "minus", pro: selectedLanguage == .russian ? "60/н" : "60/w", max: selectedLanguage == .russian ? "200/н" : "200/w", selectedPlan: selectedPlan)
                            ComparisonRow(title: "DeepThink", free: "minus", pro: "minus", max: selectedLanguage == .russian ? "30/д" : "30/d", selectedPlan: selectedPlan)
                        }
                        
                        // Блок 2: Возможности
                        Group {
                            ComparisonRow(title: selectedLanguage == .russian ? "Безлимит (База)" : "Unlimited (Base)", free: true, pro: true, max: true, selectedPlan: selectedPlan)
                            ComparisonRow(title: selectedLanguage == .russian ? "Память (фактов)" : "Memory (facts)", free: "10", pro: "25", max: "50", selectedPlan: selectedPlan)
                            ComparisonRow(title: selectedLanguage == .russian ? "Голосовое общение" : "Voice Chat", free: false, pro: true, max: true, selectedPlan: selectedPlan)
                        }
                        
                        // Блок 3: Экстра (Max)
                        Group {
                            ComparisonRow(title: selectedLanguage == .russian ? "Поиск в интернете" : "Web Search", free: false, pro: false, max: true, selectedPlan: selectedPlan)
                            ComparisonRow(title: selectedLanguage == .russian ? "Deep Research (Альфа)" : "Deep Research (Alpha)", free: "minus", pro: "minus", max: selectedLanguage == .russian ? "10/н" : "10/w", selectedPlan: selectedPlan)
                            ComparisonRow(title: selectedLanguage == .russian ? "Генерация картинок" : "Image Generation", free: selectedLanguage == .russian ? "20/д" : "20/d", pro: "check", max: "check", selectedPlan: selectedPlan)
                            ComparisonRow(title: "Quality Images", free: "minus", pro: "minus", max: selectedLanguage == .russian ? "20/д" : "20/d", selectedPlan: selectedPlan)
                            ComparisonRow(title: selectedLanguage == .russian ? "Анализ файлов" : "File Analysis", free: false, pro: false, max: true, selectedPlan: selectedPlan)
                        }
                    }
                    .padding(.top, 25)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
                .padding()
                
                // Purchase Buttons
                VStack(spacing: 12) {
                    if selectedPlan == "Free" {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text(selectedLanguage == .russian ? "Меня все устраивает" : "I'm satisfied")
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(16)
                        }
                    } else if selectedPlan == "Pro" {
                        Button(action: {
                            selectedPlanForActivation = "Nova Pro"
                            showActivationAlert = true
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Nova Pro")
                                        .font(.headline)
                                    Text(selectedLanguage == .russian ? "299 ₽ / мес" : "$2.99 / mo")
                                        .font(.caption)
                                        .opacity(0.8)
                                }
                                Spacer()
                                Text(selectedLanguage == .russian ? "Активировать" : "Activate")
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(16)
                        }
                    } else if selectedPlan == "Max" {
                        Button(action: {
                            selectedPlanForActivation = "Nova Max"
                            showActivationAlert = true
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Nova Max")
                                        .font(.headline)
                                    Text(selectedLanguage == .russian ? "699 ₽ / мес" : "$6.99 / mo")
                                        .font(.caption)
                                        .opacity(0.8)
                                }
                                Spacer()
                                Text(selectedLanguage == .russian ? "Активировать" : "Activate")
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                        }
                    }
                }
                .padding(.horizontal)
                
                Text(selectedLanguage == .russian ? "В этой версии оплата производится вручную через администратора." : "In this version, payment is processed manually via administrator.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)
                    .padding(.horizontal)
            }
        }
        .alert("\(selectedLanguage == .russian ? "Активация" : "Activate") \(selectedPlanForActivation)", isPresented: $showActivationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(selectedLanguage == .russian ? "Напиши мне в Telegram @Vladik40perc, чтобы получить доступ. После оплаты я включу функции мгновенно." : "Write to me on Telegram @Vladik40perc to get access. I will enable features instantly after payment.")
        }
        .onAppear {
            if viewModel.isMax {
                selectedPlan = "Max"
            } else if viewModel.isPro {
                selectedPlan = "Pro"
            } else {
                selectedPlan = "Free"
            }
        }
    }
}

// --- КОМПОНЕНТЫ ---

struct ComparisonRow: View {
    let title: String
    let free: String
    let pro: String
    let max: String
    let selectedPlan: String
    
    init(title: String, free: Bool, pro: Bool, max: Bool, selectedPlan: String) {
        self.title = title
        self.free = free ? "check" : "minus"
        self.pro = pro ? "check" : "minus"
        self.max = max ? "check" : "minus"
        self.selectedPlan = selectedPlan
    }
    
    init(title: String, free: String, pro: String, max: String, selectedPlan: String) {
        self.title = title
        self.free = free
        self.pro = pro
        self.max = max
        self.selectedPlan = selectedPlan
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 20) {
                StatusIcon(status: free, color: .gray)
                    .background(selectedPlan == "Free" ? Color.gray.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                StatusIcon(status: pro, color: .blue)
                    .background(selectedPlan == "Pro" ? Color.blue.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                StatusIcon(status: max, color: .purple)
                    .background(selectedPlan == "Max" ? Color.purple.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
            }
        }
    }
}

struct HeaderTitle: View {
    let text: String
    let color: Color
    let isSelected: Bool
    
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(color)
            .frame(width: 50)
            .multilineTextAlignment(.center)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.15) : Color.clear)
            .cornerRadius(8)
    }
}

struct PlanButton: View {
    let title: String
    let color: Color
    @Binding var selectedPlan: String
    
    var body: some View {
        Button(action: {
            withAnimation {
                selectedPlan = title
            }
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(selectedPlan == title ? color : .secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(selectedPlan == title ? color.opacity(0.15) : Color.clear)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selectedPlan == title ? color : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

struct StatusIcon: View {
    let status: String
    let color: Color
    
    var body: some View {
        if status == "check" {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
                .frame(width: 50)
        } else if status == "minus" {
            Image(systemName: "minus")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.gray.opacity(0.3))
                .frame(width: 50)
        } else {
            Text(status)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .frame(width: 50)
                .multilineTextAlignment(.center)
        }
    }
}