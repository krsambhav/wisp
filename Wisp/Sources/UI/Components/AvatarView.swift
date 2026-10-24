import AppKit
import SwiftUI

struct AvatarView: View {
    let account: Account
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if let file = account.avatarFileName, let img = NSImage(contentsOf: Paths.avatarsDirectory.appendingPathComponent(file)) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                account.avatarColor.color
                Text(account.initials)
                    .font(WispUI.font(size * 0.4, .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
