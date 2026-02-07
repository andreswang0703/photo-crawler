import Foundation
import PhotoCrawlerCore

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "help"

await { @MainActor in
    switch command {
    case "scan":
        await Commands.runScan()
    case "watch":
        await Commands.runWatch()
    case "init":
        Commands.runInit()
    case "status":
        await Commands.runStatus()
    case "config":
        Commands.runShowConfig()
    case "test":
        let imagePath = Array(args).dropFirst().first
        await Commands.runTest(imagePath: imagePath)
    case "help", "--help", "-h":
        Commands.printUsage()
    case "version", "--version":
        print("photo-crawler 1.0.0")
    default:
        printError("Unknown command: \(command)")
        Commands.printUsage()
        exit(1)
    }
}()
