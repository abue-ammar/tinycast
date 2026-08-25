import Foundation

/// Pins `AIInstructions`: enabled, the preamble always rides along, the user's text lands after it,
/// and whitespace alone never counts as a prompt; disabled, a turn carries nothing at all. The
/// preamble's own content is pinned too, since it ships to every model on every turn.
@main
struct AIInstructionsTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        check(
            "no user prompt still sends the preamble",
            AIInstructions.compose(userPrompt: nil, isEnabled: true) == AIPreamble.text)
        check(
            "an empty prompt sends the preamble alone",
            AIInstructions.compose(userPrompt: "", isEnabled: true) == AIPreamble.text)
        check(
            "whitespace is not a prompt",
            AIInstructions.compose(userPrompt: "   \n\t ", isEnabled: true) == AIPreamble.text)

        let composed = AIInstructions.compose(userPrompt: "  Answer only in haiku.  ", isEnabled: true)
        check("the preamble comes first", composed?.hasPrefix(AIPreamble.text) == true)
        check("the user's text comes last", composed?.hasSuffix("Answer only in haiku.") == true)
        check("the user's text is trimmed", composed?.hasSuffix(" ") == false)
        check(
            "the two are separated by a blank line",
            composed?.contains("\n\nAnswer only in haiku.") == true)

        // Off has to reach the preamble too, or the setting only turns off the half the user typed.
        check(
            "turned off, a turn carries no instructions",
            AIInstructions.compose(userPrompt: nil, isEnabled: false) == nil)
        check(
            "turned off, the user's own text is withheld as well",
            AIInstructions.compose(userPrompt: "Answer only in haiku.", isEnabled: false) == nil)

        check(
            "the preamble names the app so the model can answer for it",
            AIPreamble.text.contains("Tinycast"))
        check(
            "the preamble tells the model to be honest in comparisons",
            AIPreamble.text.lowercased().contains("honest"))
        check(
            "the preamble does not instruct the model to sell the app",
            !AIPreamble.text.lowercased().contains("prefer tinycast"))

        check(
            "the preamble refuses to guess another launcher's numbers",
            AIPreamble.text.lowercased().contains("no measurements for any other launcher"))

        // Every line is billed on every turn, so the preamble has to stay a preamble.
        check("the preamble stays short", AIPreamble.text.count < 1_800)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
