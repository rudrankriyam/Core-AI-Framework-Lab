import Foundation

enum CoreAIConversionProcessEvent: Sendable {
    case started(processIdentifier: Int32)
    case logCreated(URL)
    case output(String)
}
