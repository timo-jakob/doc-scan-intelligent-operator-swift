/// Determines whether a user-supplied VLM identifier refers to a concrete
/// HuggingFace model (e.g. "mlx-community/Qwen2-VL-2B-Instruct-4bit") or
/// a model family name (e.g. "Qwen3-VL") that requires discovery.
public enum VLMModelResolver {
    /// Returns `true` when the name looks like a concrete HuggingFace model ID
    /// in `org/repo` format — i.e. contains exactly one `/` with non-empty parts
    /// on both sides.
    public static func isConcreteModel(_ name: String) -> Bool {
        let parts = name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return !parts[0].isEmpty && !parts[1].isEmpty && !parts[1].contains("/")
    }

    /// If `name` is a concrete model ID, returns it wrapped in a single-element
    /// array. Returns `nil` when the name is a family that needs HuggingFace
    /// discovery.
    public static func resolveImmediate(_ name: String) -> [String]? {
        isConcreteModel(name) ? [name] : nil
    }
}
