import SwiftUI
import SwiftData

struct FolderDetailView: View {
    let folder: ChatFolder
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isMenuOpen: Bool
    
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
                        Button(role: .destructive) {
                            viewModel.removeChatFromFolder(session)
                        } label: {
                            Label("Убрать из папки", systemImage: "folder.badge.minus")
                        }
                    }
                }
            } else {
                Text("В этой папке пока нет чатов")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("\(folder.emoji) \(folder.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
