import SwiftUI

struct MemoryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var memories: [String] = []
    @State private var newMemoryText: String = ""
    @State private var isAdding: Bool = false
    
    @AppStorage("isPro") private var isPro: Bool = false
    @AppStorage("isMax") private var isMax: Bool = false
    
    private var memoryLimit: Int {
        if isMax { return 50 }
        if isPro { return 25 }
        return 10
    }
    
    var body: some View {
        List {
            Section(header: Text("Использовано \(memories.count) из \(memoryLimit)"), footer: Text("Nova автоматически запоминает важные факты из диалога. Вы также можете добавить воспоминания вручную.")) {
                if isAdding {
                    HStack {
                        TextField("Например: У меня есть собака Рекс", text: $newMemoryText)
                            .onSubmit {
                                addMemory()
                            }
                        
                        Button(action: addMemory) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .disabled(newMemoryText.isEmpty)
                    }
                } else {
                    if memories.count >= memoryLimit {
                        Text("Лимит памяти достигнут")
                            .foregroundColor(.secondary)
                    } else {
                        Button(action: { withAnimation { isAdding = true } }) {
                            Label("Добавить воспоминание", systemImage: "plus")
                        }
                    }
                }
                
                ForEach(memories, id: \.self) { memory in
                    Text(memory)
                }
                .onDelete(perform: deleteMemory)
            }
            
            if !memories.isEmpty {
                Section {
                    Button("Забыть всё", role: .destructive) {
                        memories.removeAll()
                        saveMemories()
                    }
                }
            }
        }
        .navigationTitle("Память")
        .onAppear(perform: loadMemories)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
    
    private func loadMemories() {
        memories = UserDefaults.standard.stringArray(forKey: "ai_memories") ?? []
    }
    
    private func saveMemories() {
        UserDefaults.standard.set(memories, forKey: "ai_memories")
    }
    
    private func addMemory() {
        guard !newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        withAnimation {
            memories.insert(newMemoryText, at: 0)
            saveMemories()
            newMemoryText = ""
            isAdding = false
        }
    }
    
    private func deleteMemory(at offsets: IndexSet) {
        memories.remove(atOffsets: offsets)
        saveMemories()
    }
}

#Preview {
    NavigationStack {
        MemoryView()
    }
}