module args;

import argparse : NamedArgument, Parse, Description, AllowedValues;
import thepath : Path;

public struct Args
{
    @(NamedArgument("deepfaceIdentities").Parse!((string s) { return Path(s); }))
    Path deepfaceIdentities = Path("~/.config/viewed/deepfaceIdentities");

    @(NamedArgument("directory", "dir", "d").Parse!((string s) { return Path(s); }))
    Path directory;

    @(NamedArgument("album", "a").Parse!((string s) { return Path(s); }))
    Path album;

    @(NamedArgument("deepface", "d").Description("Enable deepface"))
    bool deepface = false;
}
