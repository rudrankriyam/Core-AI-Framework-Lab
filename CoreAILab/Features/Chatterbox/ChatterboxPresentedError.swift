import Foundation

struct ChatterboxPresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
