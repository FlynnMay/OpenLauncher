/// Who can reach a member of a node: one of its variables, actions or
/// modules, or a child.
enum NodeAccess {
  /// The node itself.
  private('Private'),

  /// The node and what is under it.
  protected('Protected'),

  /// Any node.
  public('Public');

  const NodeAccess(this.label);

  final String label;

  /// The level [name] names, or [otherwise].
  static NodeAccess named(Object? name, NodeAccess otherwise) =>
      NodeAccess.values.asNameMap()[name] ?? otherwise;
}
