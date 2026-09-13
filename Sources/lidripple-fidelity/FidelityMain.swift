import Darwin
import Foundation

@main
enum FidelityMain {
    static func main() async {
        do {
            let options = try FidelityOptions.parse(
                Array(CommandLine.arguments.dropFirst()),
                currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            try await FidelityRun.execute(options: options)
            print("Wrote fidelity comparison to \(options.outputDirectory.path)")
        } catch FidelityError.helpRequested {
            print(FidelityOptions.usage)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            FileHandle.standardError.write(Data("\(FidelityOptions.usage)\n".utf8))
            exit(2)
        }
    }
}
