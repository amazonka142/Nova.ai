import SwiftUI
import SwiftData
import FirebaseAuth

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isMenuOpen: Bool
    
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    // Используем SwiftData для получения списка чатов
    @Query(sort: \ChatSession.lastModified, order: .reverse) private var sessions: [ChatSession]
    @Query(sort: \ChatFolder.creationDate) private var folders: [ChatFolder]
    
    @State private var sessionToRename: ChatSession?
    @State private var newTitleInput: String = ""
    @State private var showRenameAlert = false
    @State private var sessionToDelete: ChatSession?
    @State private var showDeleteAlert = false
    @State private var isGalleryPresented = false
    
    // Folder State
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var newFolderEmoji = "📁"
    @State private var selectedFolder: ChatFolder? // For detail view
    @State private var sessionToMove: ChatSession? // For moving to folder
    @State private var showMoveSheet = false
    
    // Rename Folder State
    @State private var showRenameFolderAlert = false
    @State private var folderToRename: ChatFolder?
    @State private var renameFolderName = ""
    @State private var renameFolderEmoji = ""
    
    // Группировка сессий по датам (исключая те, что в папках)
    private var groupedSessions: [(String, [ChatSession])] {
        let calendar = Calendar.current
        var sections: [(String, [ChatSession])] = []
        
        // Filter out sessions that are in a folder
        let filteredSessions = sessions.filter { $0.folder == nil }
        
        for session in filteredSessions {
            let key: String
            if calendar.isDateInToday(session.lastModified) {
                key = selectedLanguage == .russian ? "Сегодня" : "Today"
            } else if calendar.isDateInYesterday(session.lastModified) {
                key = selectedLanguage == .russian ? "Вчера" : "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: selectedLanguage == .russian ? "ru_RU" : "en_US")
                formatter.dateFormat = "d MMMM"
                key = formatter.string(from: session.lastModified)
            }
            
            if let lastIndex = sections.indices.last, sections[lastIndex].0 == key {
                sections[lastIndex].1.append(session)
            } else {
                sections.append((key, [session]))
            }
        }
        return sections
    }
    
    // Emoji Filter Helper
    private func filterEmojiInput(_ input: String) -> String {
        let emojis = input.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return scalar.properties.isEmoji && (scalar.value > 0x238C || scalar.properties.isEmojiPresentation)
        }
        return String(emojis.prefix(1))
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Заголовок меню
            HStack {
                Text(selectedLanguage == .russian ? "История" : "History")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    viewModel.createNewSession()
                    withAnimation { isMenuOpen = false }
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .padding(.top, 40) // Отступ для статус-бара
            
            // Галерея
            Button(action: {
                isGalleryPresented = true
            }) {
                HStack {
                    Image(systemName: "photo.stack")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    Text(selectedLanguage == .russian ? "Галерея генераций" : "Generations Gallery")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .sheet(isPresented: $isGalleryPresented) {
                GalleryView()
            }
            
            // Список чатов
            ScrollView {
                LazyVStack(spacing: 4) {
                    
                    // --- FOLDERS SECTION ---
                    VStack(alignment: .leading) {
                        HStack {
                            Text(selectedLanguage == .russian ? "Папки" : "Folders")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                newFolderName = ""
                                newFolderEmoji = "📁"
                                showCreateFolderAlert = true
                            }) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(folders) { folder in
                                    Button(action: {
                                        selectedFolder = folder
                                    }) {
                                        VStack {
                                            Text(folder.emoji)
                                                .font(.title)
                                            Text(folder.name)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .foregroundColor(.primary)
                                        }
                                        .frame(width: 70, height: 70)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(12)
                                    }
                                    .contextMenu {
                                        Button {
                                            folderToRename = folder
                                            renameFolderName = folder.name
                                            renameFolderEmoji = folder.emoji
                                            showRenameFolderAlert = true
                                        } label: {
                                            Label(selectedLanguage == .russian ? "Переименовать" : "Rename", systemImage: "pencil")
                                        }
                                        
                                        Button(role: .destructive) {
                                            viewModel.deleteFolder(folder)
                                        } label: {
                                            Label(selectedLanguage == .russian ? "Удалить папку" : "Delete Folder", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    // -----------------------
                    
                    ForEach(groupedSessions, id: \.0) { section in
                        Text(section.0)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        
                        ForEach(section.1) { session in
                        HStack {
                            Image(systemName: "bubble.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(session.title)
                                .font(.body)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        .background(
                            viewModel.currentSession.id == session.id ? Color.secondary.opacity(0.15) : Color.clear
                        )
                        .cornerRadius(8)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectSession(session)
                            withAnimation { isMenuOpen = false }
                        }
                        // Контекстное меню по долгому нажатию
                        .contextMenu {
                            Button {
                                sessionToMove = session
                                showMoveSheet = true
                            } label: {
                                Label(selectedLanguage == .russian ? "Добавить в папку" : "Add to Folder", systemImage: "folder")
                            }
                            
                            Button {
                                sessionToRename = session
                                newTitleInput = session.title
                                showRenameAlert = true
                            } label: {
                                Label(selectedLanguage == .russian ? "Переименовать" : "Rename", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                sessionToDelete = session
                                showDeleteAlert = true
                            } label: {
                                Label(selectedLanguage == .russian ? "Удалить" : "Delete", systemImage: "trash")
                            }
                        }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Профиль пользователя внизу
            if let user = viewModel.userSession {
                VStack(spacing: 0) {
                    Divider()
                    
                    HStack(spacing: 12) {
                        // Аватар
                        if let photoURL = user.photoURL {
                            AsyncImage(url: photoURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } placeholder: {
                                SidebarAvatarPlaceholder(user: user)
                            }
                        } else {
                            SidebarAvatarPlaceholder(user: user)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(user.displayName ?? (user.isAnonymous ? (selectedLanguage == .russian ? "Гость" : "Guest") : (selectedLanguage == .russian ? "Пользователь" : "User")))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                if viewModel.isMax {
                                    Text("MAX")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                        .clipShape(Capsule())
                                } else if viewModel.isPro {
                                    Text("PRO")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            if !user.isAnonymous, let email = user.email {
                                Text(email)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.isSettingsPresented = true
                            withAnimation { isMenuOpen = false }
                        }) {
                            Image(systemName: "gearshape")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                    .padding(.bottom, 20) // Отступ для устройств без кнопки Home
                }
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
            }
        }
        .background(Color(UIColor.systemBackground))
        // Sheets & Alerts
        .sheet(item: $selectedFolder) { folder in
            NavigationStack {
                FolderDetailView(folder: folder, viewModel: viewModel, isMenuOpen: $isMenuOpen)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { selectedFolder = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMoveSheet) {
            NavigationStack {
                List {
                    ForEach(folders) { folder in
                        Button {
                            if let session = sessionToMove {
                                viewModel.moveChatToFolder(session, folder: folder)
                            }
                            showMoveSheet = false
                            sessionToMove = nil
                        } label: {
                            HStack {
                                Text(folder.emoji)
                                Text(folder.name)
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle(selectedLanguage == .russian ? "Выберите папку" : "Select Folder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showMoveSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // CREATE FOLDER ALERT
        .alert(selectedLanguage == .russian ? "Новая папка" : "New Folder", isPresented: $showCreateFolderAlert) {
            TextField(selectedLanguage == .russian ? "Название" : "Name", text: $newFolderName)
            TextField("Emoji", text: Binding(
                get: { newFolderEmoji },
                set: { newFolderEmoji = filterEmojiInput($0) }
            ))
            Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            Button(selectedLanguage == .russian ? "Создать" : "Create") {
                viewModel.createFolder(name: newFolderName, emoji: newFolderEmoji.isEmpty ? "📁" : newFolderEmoji)
            }
        }
        // RENAME FOLDER ALERT
        .alert(selectedLanguage == .russian ? "Переименовать папку" : "Rename Folder", isPresented: $showRenameFolderAlert) {
            TextField(selectedLanguage == .russian ? "Название" : "Name", text: $renameFolderName)
            TextField("Emoji", text: Binding(
                get: { renameFolderEmoji },
                set: { renameFolderEmoji = filterEmojiInput($0) }
            ))
            Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            Button(selectedLanguage == .russian ? "Сохранить" : "Save") {
                if let folder = folderToRename {
                    viewModel.renameFolder(folder, newName: renameFolderName, newEmoji: renameFolderEmoji.isEmpty ? "📁" : renameFolderEmoji)
                }
            }
        }
        // RENAME CHAT ALERT
        .alert(selectedLanguage == .russian ? "Переименовать чат" : "Rename Chat", isPresented: $showRenameAlert) {
            TextField(selectedLanguage == .russian ? "Название" : "Name", text: $newTitleInput)
            Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            Button(selectedLanguage == .russian ? "Сохранить" : "Save") {
                if let session = sessionToRename {
                    viewModel.renameSession(session, newTitle: newTitleInput)
                }
            }
        }
        .alert(selectedLanguage == .russian ? "Вы уверены?" : "Are you sure?", isPresented: $showDeleteAlert) {
            Button(selectedLanguage == .russian ? "Удалить" : "Delete", role: .destructive) {
                if let session = sessionToDelete {
                    withAnimation {
                        viewModel.deleteSession(session)
                    }
                }
            }
            Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
        } message: {
            Text(selectedLanguage == .russian ? "Этот чат будет удален навсегда. Это действие нельзя отменить." : "This chat will be deleted permanently. This action cannot be undone.")
        }
    }
}

struct SidebarAvatarPlaceholder: View {
    let user: User
    
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
            
            Text(String(user.displayName?.prefix(1) ?? user.email?.prefix(1) ?? "G").uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
