import SwiftUI
import SwiftData

struct FolderDetailView: View {
    let folder: ChatFolder
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isMenuOpen: Bool
    
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    @State private var sessionToRename: ChatSession?
    @State private var newTitleInput: String = ""
    @State private var showRenameAlert = false
    
    // We cannot use @Query here easily because we need to filter by a dynamic folder ID.
    // Instead, we rely on the `folder.sessions` relationship which SwiftData manages.
    
    var body: some View {
        List {
            if let sessions = folder.sessions, !sessions.isEmpty {
                ForEach(sessions.sorted(by: { $0.lastModified > $1.lastModified })) { session in
                    Button(action: {
                        viewModel.selectSession(session)
                        withAnimation { isMenuOpen = false }
                    }) {
                        HStack {
                            Image(systemName: "bubble.left")
                                .foregroundColor(.secondary)
                            Text(session.title)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .contextMenu {
                        Button {
                            sessionToRename = session
                            newTitleInput = session.title
                            showRenameAlert = true
                        } label: {
                            Label(selectedLanguage == .russian ? "Переименовать" : "Rename", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            viewModel.removeChatFromFolder(session)
                        } label: {
                            Label(selectedLanguage == .russian ? "Убрать из папки" : "Remove from Folder", systemImage: "folder.badge.minus")
                        }
                    }
                }
            } else {
                Text(selectedLanguage == .russian ? "В этой папке пока нет чатов" : "No chats in this folder yet")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("\(folder.emoji) \(folder.name)")
        .navigationBarTitleDisplayMode(.inline)
        .alert(selectedLanguage == .russian ? "Переименовать чат" : "Rename Chat", isPresented: $showRenameAlert) {
            TextField(selectedLanguage == .russian ? "Название" : "Name", text: $newTitleInput)
            Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            Button(selectedLanguage == .russian ? "Сохранить" : "Save") {
                if let session = sessionToRename {
                    viewModel.renameSession(session, newTitle: newTitleInput)
                }
            }
        }
    }
}
