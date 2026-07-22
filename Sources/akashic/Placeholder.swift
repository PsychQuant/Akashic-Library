import ArgumentParser

@main
struct AkashicCLI: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "akashic", abstract: "Akashic-Library CLI")
}
