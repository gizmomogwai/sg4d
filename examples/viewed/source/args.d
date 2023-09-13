module args;

import argparse : NamedArgument;

public struct Args
{
    @NamedArgument("deepfaceDirectory")
    string deepfaceDirectory;

    @NamedArgument("deepfaceIdentities")
    string deepfaceIdentities;

    @NamedArgument("directory", "dir", "d")
    string directory;

    @NamedArgument("album", "a")
    string album;
}
