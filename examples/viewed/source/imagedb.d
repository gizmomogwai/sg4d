module imagedb;

import std.file : DirEntry;
import std.path : dirName;
import args : Args;
import std.array : replace;
import std.conv : to;
import std.regex : ctRegex, replaceFirst;

string shorten(DirEntry file, Args args)
{
    enum firstSlash = ctRegex!("^/");
    return file.to!string
        .replace(args.directory !is null ? args.directory : "", "")
        .replace(args.album !is null? args.album.dirName : "", "")
        .replaceFirst(firstSlash, "");
}
