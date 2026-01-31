import SwiftUI

struct LimitReachedOverlay: View {
    let modelName: String
    let isPro: Bool
    let isMax: Bool
    var onUpgrade: () -> Void
    var onSwitchToFree: () -> Void
    var onClose: () -> Void
    
    @State private var timeRemaining: String = ""
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.top, 10)
                
                // Title
                Text("\(selectedLanguage == .russian ? "Лимит исчерпан для" : "Limit reached for") \(modelName)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Body
                Text(selectedLanguage == .russian ? "Ваш лимит на эту модель обновится через \(timeRemaining). Вы можете перейти на безлимитную модель или улучшить тариф." : "Your limit for this model will reset in \(timeRemaining). You can switch to an unlimited model or upgrade your plan.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    // Primary Action: Upgrade
                    if !isMax {
                        Button(action: onUpgrade) {
                            HStack {
                                Text(upgradeButtonTitle)
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "sparkles")
                            }
                            .padding()
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .cornerRadius(12)
                        }
                    }
                    
                    // Secondary Action: Switch to Free
                    Button(action: onSwitchToFree) {
                        Text("\(selectedLanguage == .russian ? "Переключиться на" : "Switch to") Nova v1-RLHF")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(12)
                    }
                    
                    // Tertiary Action: Close
                    Button(selectedLanguage == .russian ? "Закрыть" : "Close") {
                        onClose()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .cornerRadius(24)
            .shadow(radius: 20)
            .padding(30)
        }
        .onAppear {
            calculateTimeLeft()
        }
    }
    
    private var upgradeButtonTitle: String {
        if isPro {
            return selectedLanguage == .russian ? "Получить Max за 699 ₽" : "Get Max for $6.99"
        } else {
            return selectedLanguage == .russian ? "Получить Pro за 299 ₽" : "Get Pro for $2.99"
        }
    }
    
    private func calculateTimeLeft() {
        let calendar = Calendar.current
        let now = Date()
        
        // Проверяем, является ли модель недельной
        if modelName.contains("Nova-v1-RP") || modelName.contains("Nova-v1-Pro") || modelName.contains("DeepSeek") {
            // Считаем время до конца недели (обычно до понедельника)
            // Находим следующий понедельник (или начало следующей недели по локали)
            if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now),
               let startOfNextWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeek)) {
                let diff = calendar.dateComponents([.day, .hour], from: now, to: startOfNextWeek)
                if let d = diff.day, let h = diff.hour {
                    timeRemaining = selectedLanguage == .russian ? "\(d) дн \(h) ч" : "\(d) d \(h) h"
                }
                return
            }
        }
        
        // Стандартный дневной расчет
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let diff = calendar.dateComponents([.hour, .minute], from: now, to: tomorrow)
        if let h = diff.hour, let m = diff.minute {
            timeRemaining = selectedLanguage == .russian ? "\(h) ч \(m) мин" : "\(h) h \(m) min"
        }
    }
}