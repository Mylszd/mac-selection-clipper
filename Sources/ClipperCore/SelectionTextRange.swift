import Foundation

public enum SelectionTextRange {
    /// AX ranges use UTF-16 code units. Never derive a selection from the whole
    /// value unless a valid nonempty public AX range was provided by the target.
    public static func extract(from text: String, ranges: [NSRange]) -> String? {
        guard !ranges.isEmpty, ranges.count <= 32 else { return nil }
        let source = text as NSString, count = (text as NSString).length
        func boundary(_ offset: Int) -> Bool {
            if offset == 0 || offset == count { return true }
            let current = source.character(at: offset), previous = source.character(at: offset - 1)
            return !((0xDC00...0xDFFF).contains(current) && (0xD800...0xDBFF).contains(previous))
        }
        var pieces = [String]()
        for range in ranges {
            guard range.location >= 0, range.length > 0, range.location <= count,
                  range.length <= count - range.location,
                  boundary(range.location), boundary(range.location + range.length) else { return nil }
            pieces.append(source.substring(with: range))
        }
        return pieces.joined(separator: "\n")
    }
}
