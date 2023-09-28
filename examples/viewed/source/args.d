module args;

import argparse : NamedArgument;

public struct Args
{
    @NamedArgument("deepfaceIdentities")
    string deepfaceIdentities = "~/.config/viewed/deepfaceIdentities";

    @NamedArgument("directory", "dir", "d")
    string directory;

    @NamedArgument("album", "a")
    string album;
}
