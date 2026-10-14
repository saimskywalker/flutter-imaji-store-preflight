/// Joins a display prefix (the project root relative to the working
/// directory, `/`-separated, possibly empty) with a project-relative path.
String displayPath(String prefix, String path) =>
    prefix.isEmpty ? path : '$prefix/$path';
