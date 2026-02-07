import Foundation

func printInfo(_ message: String) {
    print("\u{1B}[34m>\u{1B}[0m \(message)")
}

func printSuccess(_ message: String) {
    print("\u{1B}[32m✓\u{1B}[0m \(message)")
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("\u{1B}[31m✗\u{1B}[0m \(message)\n".utf8))
}

func printDim(_ message: String) {
    print("\u{1B}[2m\(message)\u{1B}[0m")
}
