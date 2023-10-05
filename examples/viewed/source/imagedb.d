module imagedb;

import args : Args;
import std.array : replace;
import std.conv : to;
import std.regex : ctRegex, replaceFirst;
import thepath : Path;

Path shorten(Path file, Args args)
{
    enum firstSlash = ctRegex!("^/");
    return Path(
        file
            .toString
            .replace(args.directory != Path.init ? args.directory.toString() : "", "")
            .replace(args.album != Path.init ? args.album.parent.toString() : "", "")
            .replaceFirst(firstSlash, "")
    );
}
