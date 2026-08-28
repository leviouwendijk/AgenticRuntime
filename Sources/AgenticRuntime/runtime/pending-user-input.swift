public struct PendingUserInput: Sendable, Codable, Hashable {
    public var prompt: String
    public var reason: String?
    public var input: UserInputSpec
    public var presentation: UserInputPresentation?
    public var metadata: [String: String]

    public init(
        prompt: String,
        reason: String? = nil,
        input: UserInputSpec = .text(
            .init()
        ),
        presentation: UserInputPresentation? = nil,
        metadata: [String: String] = [:]
    ) {
        self.prompt = prompt
        self.reason = reason
        self.input = input
        self.presentation = presentation
        self.metadata = metadata
    }
}

public enum UserInputSpec: Sendable, Codable, Hashable {
    case text(TextUserInput)
    case single_choice(SingleChoiceUserInput)
    case multi_choice(MultiChoiceUserInput)
    case confirmation(ConfirmationUserInput)
    case form(FormUserInput)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case single_choice
        case multi_choice
        case confirmation
        case form
    }

    private enum Kind: String, Codable {
        case text
        case single_choice
        case multi_choice
        case confirmation
        case form
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let kind = try container.decode(
            Kind.self,
            forKey: .kind
        )

        switch kind {
        case .text:
            self = .text(
                try container.decode(
                    TextUserInput.self,
                    forKey: .text
                )
            )

        case .single_choice:
            self = .single_choice(
                try container.decode(
                    SingleChoiceUserInput.self,
                    forKey: .single_choice
                )
            )

        case .multi_choice:
            self = .multi_choice(
                try container.decode(
                    MultiChoiceUserInput.self,
                    forKey: .multi_choice
                )
            )

        case .confirmation:
            self = .confirmation(
                try container.decode(
                    ConfirmationUserInput.self,
                    forKey: .confirmation
                )
            )

        case .form:
            self = .form(
                try container.decode(
                    FormUserInput.self,
                    forKey: .form
                )
            )
        }
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        switch self {
        case .text(let value):
            try container.encode(
                Kind.text,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .text
            )

        case .single_choice(let value):
            try container.encode(
                Kind.single_choice,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .single_choice
            )

        case .multi_choice(let value):
            try container.encode(
                Kind.multi_choice,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .multi_choice
            )

        case .confirmation(let value):
            try container.encode(
                Kind.confirmation,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .confirmation
            )

        case .form(let value):
            try container.encode(
                Kind.form,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .form
            )
        }
    }
}

public struct TextUserInput: Sendable, Codable, Hashable {
    public var placeholder: String?
    public var defaultText: String?
    public var multiline: Bool
    public var validation: UserInputValidation?

    public init(
        placeholder: String? = nil,
        defaultText: String? = nil,
        multiline: Bool = false,
        validation: UserInputValidation? = nil
    ) {
        self.placeholder = placeholder
        self.defaultText = defaultText
        self.multiline = multiline
        self.validation = validation
    }
}

public struct SingleChoiceUserInput: Sendable, Codable, Hashable {
    public var choices: [UserInputChoice]
    public var defaultChoiceID: String?
    public var allowsCustomValue: Bool

    public init(
        choices: [UserInputChoice],
        defaultChoiceID: String? = nil,
        allowsCustomValue: Bool = false
    ) {
        self.choices = choices
        self.defaultChoiceID = defaultChoiceID
        self.allowsCustomValue = allowsCustomValue
    }
}

public struct MultiChoiceUserInput: Sendable, Codable, Hashable {
    public var choices: [UserInputChoice]
    public var defaultChoiceIDs: [String]
    public var minimumSelectionCount: Int
    public var maximumSelectionCount: Int?

    public init(
        choices: [UserInputChoice],
        defaultChoiceIDs: [String] = [],
        minimumSelectionCount: Int = 0,
        maximumSelectionCount: Int? = nil
    ) {
        self.choices = choices
        self.defaultChoiceIDs = defaultChoiceIDs
        self.minimumSelectionCount = max(
            0,
            minimumSelectionCount
        )
        self.maximumSelectionCount = maximumSelectionCount.map {
            max(
                0,
                $0
            )
        }
    }
}

public struct ConfirmationUserInput: Sendable, Codable, Hashable {
    public var defaultValue: Bool?
    public var confirmLabel: String
    public var cancelLabel: String

    public init(
        defaultValue: Bool? = nil,
        confirmLabel: String = "Confirm",
        cancelLabel: String = "Cancel"
    ) {
        self.defaultValue = defaultValue
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
    }
}

public struct FormUserInput: Sendable, Codable, Hashable {
    public var fields: [UserInputField]
    public var submitLabel: String?

    public init(
        fields: [UserInputField],
        submitLabel: String? = nil
    ) {
        self.fields = fields
        self.submitLabel = submitLabel
    }
}

public struct UserInputChoice: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var value: String
    public var description: String?
    public var isDefault: Bool
    public var isDestructive: Bool
    public var metadata: [String: String]

    public init(
        id: String,
        label: String,
        value: String,
        description: String? = nil,
        isDefault: Bool = false,
        isDestructive: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.description = description
        self.isDefault = isDefault
        self.isDestructive = isDestructive
        self.metadata = metadata
    }
}

public struct UserInputField: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var placeholder: String?
    public var defaultText: String?
    public var multiline: Bool
    public var validation: UserInputValidation?
    public var metadata: [String: String]

    public init(
        id: String,
        label: String,
        placeholder: String? = nil,
        defaultText: String? = nil,
        multiline: Bool = false,
        validation: UserInputValidation? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.defaultText = defaultText
        self.multiline = multiline
        self.validation = validation
        self.metadata = metadata
    }
}

public struct UserInputValidation: Sendable, Codable, Hashable {
    public var required: Bool
    public var minimumLength: Int?
    public var maximumLength: Int?
    public var patternDescription: String?

    public init(
        required: Bool = true,
        minimumLength: Int? = nil,
        maximumLength: Int? = nil,
        patternDescription: String? = nil
    ) {
        self.required = required
        self.minimumLength = minimumLength.map {
            max(
                0,
                $0
            )
        }
        self.maximumLength = maximumLength.map {
            max(
                0,
                $0
            )
        }
        self.patternDescription = patternDescription
    }
}

public struct UserInputPresentation: Sendable, Codable, Hashable {
    public var title: String?
    public var help: String?
    public var preferredControl: UserInputControl?
    public var ordering: UserInputOrdering

    public init(
        title: String? = nil,
        help: String? = nil,
        preferredControl: UserInputControl? = nil,
        ordering: UserInputOrdering = .provided
    ) {
        self.title = title
        self.help = help
        self.preferredControl = preferredControl
        self.ordering = ordering
    }
}

public enum UserInputControl: String, Sendable, Codable, Hashable, CaseIterable {
    case text_field
    case text_area
    case radio_list
    case checkbox_list
    case confirmation
    case form
}

public enum UserInputOrdering: String, Sendable, Codable, Hashable, CaseIterable {
    case provided
    case alphabetical
    case grouped
}

public enum UserInputAnswer: Sendable, Codable, Hashable {
    case text(String)
    case single_choice(SingleChoiceUserInputAnswer)
    case multi_choice(MultiChoiceUserInputAnswer)
    case confirmation(Bool)
    case form(FormUserInputAnswer)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case single_choice
        case multi_choice
        case confirmation
        case form
    }

    private enum Kind: String, Codable {
        case text
        case single_choice
        case multi_choice
        case confirmation
        case form
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let kind = try container.decode(
            Kind.self,
            forKey: .kind
        )

        switch kind {
        case .text:
            self = .text(
                try container.decode(
                    String.self,
                    forKey: .text
                )
            )

        case .single_choice:
            self = .single_choice(
                try container.decode(
                    SingleChoiceUserInputAnswer.self,
                    forKey: .single_choice
                )
            )

        case .multi_choice:
            self = .multi_choice(
                try container.decode(
                    MultiChoiceUserInputAnswer.self,
                    forKey: .multi_choice
                )
            )

        case .confirmation:
            self = .confirmation(
                try container.decode(
                    Bool.self,
                    forKey: .confirmation
                )
            )

        case .form:
            self = .form(
                try container.decode(
                    FormUserInputAnswer.self,
                    forKey: .form
                )
            )
        }
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        switch self {
        case .text(let value):
            try container.encode(
                Kind.text,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .text
            )

        case .single_choice(let value):
            try container.encode(
                Kind.single_choice,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .single_choice
            )

        case .multi_choice(let value):
            try container.encode(
                Kind.multi_choice,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .multi_choice
            )

        case .confirmation(let value):
            try container.encode(
                Kind.confirmation,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .confirmation
            )

        case .form(let value):
            try container.encode(
                Kind.form,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .form
            )
        }
    }
}

public enum SingleChoiceUserInputAnswer: Sendable, Codable, Hashable {
    case choice(String)
    case custom(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case choice
        case custom
    }

    private enum Kind: String, Codable {
        case choice
        case custom
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let kind = try container.decode(
            Kind.self,
            forKey: .kind
        )

        switch kind {
        case .choice:
            self = .choice(
                try container.decode(
                    String.self,
                    forKey: .choice
                )
            )

        case .custom:
            self = .custom(
                try container.decode(
                    String.self,
                    forKey: .custom
                )
            )
        }
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        switch self {
        case .choice(let id):
            try container.encode(
                Kind.choice,
                forKey: .kind
            )
            try container.encode(
                id,
                forKey: .choice
            )

        case .custom(let value):
            try container.encode(
                Kind.custom,
                forKey: .kind
            )
            try container.encode(
                value,
                forKey: .custom
            )
        }
    }
}

public struct MultiChoiceUserInputAnswer: Sendable, Codable, Hashable {
    public var choiceIDs: [String]

    public init(
        choiceIDs: [String]
    ) {
        self.choiceIDs = choiceIDs
    }
}

public struct FormUserInputAnswer: Sendable, Codable, Hashable {
    public var values: [String: String]

    public init(
        values: [String: String]
    ) {
        self.values = values
    }
}
