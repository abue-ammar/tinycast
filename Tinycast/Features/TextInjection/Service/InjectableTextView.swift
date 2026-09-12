import AppKit

/// Opt-in: a view that adopts this accepts injected text written straight into it, in process.
protocol InjectableTextView where Self: NSTextView {}

extension InjectableTextView {
    var injectableSelection: String {
        (string as NSString).substring(with: selectedRange())
    }
}
