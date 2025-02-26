module args;

import argparse : NamedArgument, Parse, Description, AllowedValues;
import thepath : Path;

public struct Args
{
    @(NamedArgument("deepfaceIdentities").Parse!((string s) { return Path(s); }))
    Path deepfaceIdentities = Path("~/.config/viewed/deepfaceIdentities");

    @(NamedArgument("directory", "dir").Parse!((string s) { return Path(s); }))
    Path directory;

    @(NamedArgument("album", "a").Parse!((string s) { return Path(s); }))
    Path album;

    @(NamedArgument("deepface").Description("Enable deepface"))
    bool deepface = false;
}
