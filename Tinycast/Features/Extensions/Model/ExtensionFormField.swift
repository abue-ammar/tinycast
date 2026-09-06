/// What a `Form.*` node is, in the terms the form's keyboard navigation needs.
enum ExtensionFormField: Equatable {
    case text
    case textArea
    case checkbox
    case dropdown
    case tagPicker
    case datePicker
    case filePicker
    /// A separator, a description, an accessory — drawn, but never landed on.
    case inert

    init(type: String) {
        switch type {
        case "Form.TextField", "Form.PasswordField": self = .text
        case "Form.TextArea": self = .textArea
        case "Form.Checkbox": self = .checkbox
        case "Form.Dropdown": self = .dropdown
        case "Form.TagPicker": self = .tagPicker
        case "Form.DatePicker": self = .datePicker
        case "Form.FilePicker": self = .filePicker
        default: self = .inert
        }
    }

    var isFocusable: Bool { self != .inert }

    /// A text area edits with ↑/↓, so the form leaves them to it and Tab is the way out.
    var ownsVerticalKeys: Bool { self == .textArea }
}
