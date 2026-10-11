/// The value all of [values] share, or null.
T? shared<T>(Iterable<T> values) =>
    values.toSet().length == 1 ? values.first : null;
