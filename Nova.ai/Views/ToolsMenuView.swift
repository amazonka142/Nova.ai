import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ToolsMenuView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTool: ChatViewModel.ChatTool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    var isMax: Bool = false
    var onUpgrade: () -> Void = {}
    var onFileSelected: (URL) -> Void
    var onCameraCaptured: (UIImage) -> Void
    @State private var isFileImporterPresented = false
    @State private var isCameraPresented = false
    @State private var showAlphaWarning = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
            
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Photo Carousel
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Недавние фото")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // Camera Button (Using Picker for MVP simplicity)
                                Button(action: {
                                    isCameraPresented = true
                                }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "camera.fill")
                                            .font(.title2)
                                        Text("Камера")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.primary)
                                    .frame(width: 80, height: 80)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                
                                // Recent Photos (Using Picker for consistency)
                                ForEach(1...5, id: \.self) { index in
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 80, height: 80)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.gray)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .fullScreenCover(isPresented: $isCameraPresented) {
                        ImagePicker(sourceType: .camera) { image in
                            onCameraCaptured(image)
                            dismiss()
                        }
                        .ignoresSafeArea()
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // 2. Tools List
                    VStack(spacing: 0) {
                        ToolRow(icon: "paintpalette.fill", color: .orange, title: "Создать изображение", subtitle: "Flux Generator") {
                            selectedTool = .image
                            dismiss()
                        }
                        
                        if isMax {
                            ToolRow(icon: "brain.head.profile", color: .purple, title: "Думаю", subtitle: "Включить DeepThink для сложных задач") {
                                selectedTool = .reasoning
                                dismiss()
                            }
                        } else {
                            ToolRow(icon: "lock.fill", color: .gray, title: "Думаю (Max)", subtitle: "Купить Nova Max") {
                                onUpgrade()
                            }
                        }
                        
                        if isMax {
                            ToolRow(icon: "doc.text.magnifyingglass", color: .indigo, title: "Deep Research (Alpha)", subtitle: "Глубокий анализ и отчет") {
                                showAlphaWarning = true
                            }
                        } else {
                            ToolRow(icon: "lock.fill", color: .gray, title: "Deep Research (Alpha)", subtitle: "Купить Nova Max") {
                                onUpgrade()
                            }
                        }
                        
                        ToolRow(icon: "globe", color: .blue, title: "Поиск в сети", subtitle: "Искать актуальную информацию") {
                            selectedTool = .search
                            dismiss()
                        }
                        
                        ToolRow(icon: "paperclip", color: .gray, title: "Добавить файлы", subtitle: "PDF, DOCX, PPTX для анализа") {
                            isFileImporterPresented = true
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
        }
        .background(Color(UIColor.systemBackground))
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: allowedFileTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    onFileSelected(url)
                    dismiss()
                }
            case .failure(let error):
                print("File selection error: \(error.localizedDescription)")
            }
        }
        .alert("Deep Research (Alpha)", isPresented: $showAlphaWarning) {
            Button("Продолжить") {
                selectedTool = .deepResearch
                dismiss()
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Эта функция находится в стадии альфа-тестирования. Возможны ошибки, неточности или нестабильная работа.")
        }
    }
    
    private var allowedFileTypes: [UTType] {
        var types: [UTType] = [.pdf, .text, .plainText]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let pptx = UTType(filenameExtension: "pptx") { types.append(pptx) }
        return types
    }
}

// Helper Component for List Rows
struct ToolRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon Circle
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundColor(color)
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle()) // Make full row tappable
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .camera
    var onImagePicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    ToolsMenuView(selectedTool: .constant(.none), selectedPhotoItem: .constant(nil), onFileSelected: { _ in }, onCameraCaptured: { _ in })
}
