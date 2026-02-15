import SwiftUI
import UIKit

struct ProjectIconView: View {
    let icon: String
    var font: Font = .caption
    var color: Color = .primary
    
    var body: some View {
        if UIImage(systemName: icon) != nil {
            Image(systemName: icon)
                .font(font)
                .foregroundColor(color)
        } else {
            Text(icon)
                .font(font)
                .foregroundColor(color)
        }
    }
}
