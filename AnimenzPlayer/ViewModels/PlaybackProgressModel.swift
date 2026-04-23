import Foundation
import Combine

@MainActor
final class PlaybackProgressModel: ObservableObject {
    @Published var progress: Double = 0
}
