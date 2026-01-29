import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Message.timestamp, order: .reverse) private var allMessages: [Message]
    
    @State private var selectedImage: (Data, String)? = nil // Data, Prompt
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    // Filter messages to get only images
    var imageMessages: [Message] {
        allMessages.filter { $0.type == .image && $0.imageData != nil }
    }
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                if imageMessages.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(selectedLanguage == .russian ? "Здесь будут ваши генерации" : "Your generations will appear here")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(imageMessages) { message in
                            if let data = message.imageData, let uiImage = UIImage(data: data) {
                                Button(action: {
                                    selectedImage = (data, message.content)
                                }) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: (UIScreen.main.bounds.width / 3) - 2, height: (UIScreen.main.bounds.width / 3) - 2)
                                        .clipped()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectedLanguage == .russian ? "Галерея" : "Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(selectedLanguage == .russian ? "Закрыть" : "Close") {
                        dismiss()
                    }
                }
            }
            .sheet(item: Binding(
                get: { selectedImage.map { GalleryItem(data: $0.0, prompt: $0.1) } },
                set: { _ in selectedImage = nil }
            )) { item in
                ImageViewer(imageData: item.data, prompt: item.prompt)
            }
        }
    }
}

struct GalleryItem: Identifiable {
    let id = UUID()
    let data: Data
    let prompt: String
}

struct ImageViewer: View {
    let imageData: Data
    let prompt: String
    @Environment(\.dismiss) var dismiss
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            
            Spacer()
            
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .padding()
                    .contextMenu {
                        Button(action: {
                            UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                        }) {
                            Label(selectedLanguage == .russian ? "Сохранить в Фото" : "Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        
                        ShareLink(item: Image(uiImage: uiImage), preview: SharePreview(prompt, image: Image(uiImage: uiImage))) {
                            Label(selectedLanguage == .russian ? "Поделиться" : "Share", systemImage: "square.and.arrow.up")
                        }
                    }
            }
            
            if !prompt.isEmpty {
                Text(prompt)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Material.thin)
                    .cornerRadius(8)
                    .padding()
            }
            
            HStack(spacing: 40) {
                if let uiImage = UIImage(data: imageData) {
                    Button(action: {
                        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                            Text(selectedLanguage == .russian ? "Сохранить" : "Save")
                                .font(.caption)
                        }
                    }
                    
                    ShareLink(item: Image(uiImage: uiImage), preview: SharePreview(prompt, image: Image(uiImage: uiImage))) {
                        VStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                            Text(selectedLanguage == .russian ? "Поделиться" : "Share")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.bottom, 30)
            
            Spacer()
        }
    }
}
