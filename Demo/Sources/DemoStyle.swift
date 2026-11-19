import UIKit

enum DemoStyle {
    static let canvas = UIColor(red: 0.045, green: 0.047, blue: 0.065, alpha: 1)
    static let surface = UIColor(red: 0.078, green: 0.082, blue: 0.111, alpha: 1)
    static let raised = UIColor(red: 0.115, green: 0.119, blue: 0.157, alpha: 1)
    static let accent = UIColor(red: 0.76, green: 0.71, blue: 1, alpha: 1)
    static let secondary = UIColor(red: 0.66, green: 0.68, blue: 0.75, alpha: 1)
    static let divider = UIColor.white.withAlphaComponent(0.09)

    static func label(_ text: String? = nil, style: UIFont.TextStyle = .body, weight: UIFont.Weight = .regular,
                      color: UIColor = .label) -> UILabel {
        let label = UILabel()
        let size = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style,
                                                            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        label.font = UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = color
        label.text = text
        return label
    }

    static func panel(_ children: [UIView], spacing: CGFloat = 8, inset: CGFloat = 14) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: children)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: inset, leading: inset, bottom: inset, trailing: inset)
        styleSurface(stack, radius: 16)
        return stack
    }

    static func styleSurface(_ view: UIView, radius: CGFloat = 18, color: UIColor = surface) {
        view.backgroundColor = color
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = divider.cgColor
        view.clipsToBounds = true
    }

    static func styleButton(_ button: UIButton, filled: Bool = false) {
        var configuration = filled ? UIButton.Configuration.filled() : .tinted()
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = filled ? canvas : accent
        configuration.baseBackgroundColor = filled ? accent : raised
        configuration.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
        button.configuration = configuration
    }
}
