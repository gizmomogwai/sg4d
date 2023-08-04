module args;

import argparse : NamedArgument;

public struct Args
{
    @NamedArgument("directory", "dir", "d")
    string directory;

    @NamedArgument("album", "a")
    string album;
}
