module deepface;

import std.process : executeShell, pipeShell, Redirect, ProcessPipes;
import std.stdio : writeln; // TODO
import std.string : format, strip, toStringz;
import std.array : split;
import std.array : join;
import std.regex : ctRegex, regex, matchAll;
import gamut : Image, ImageFormat, PixelType;
import std.conv : to;
import std.path : buildPath;
import args : Args;
import imagedb : shorten;
import std.stdio : File;
import std.file : mkdirRecurse, DirEntry, exists, readText, write;
import std.algorithm : map;
import std.concurrency : initOnce;

version (unittest)
{
}
else
{
    import mir.deser.json : deserializeJson;
    import mir.ser.json : serializeJson;
}

string calcDeepfacePath(DirEntry file, Args args)
{
    return args.deepfaceDirectory.buildPath(file.shorten(args));
}

struct Face {
    string face;
    string rectangle;
    string name; /// null if not recognized
}

class DeepfaceProcess
{
    __gshared DeepfaceProcess instance;

    private ProcessPipes pipes;

    public static auto getInstance(string identitiesPath)
    {
        return initOnce!instance(new DeepfaceProcess(identitiesPath));
    }

    private this(string identitiesPath)
    {
        pipes = pipeShell("./mydeepface.py %s".format(identitiesPath), Redirect.stdin | Redirect.stdout);
    }
    Face[] extractFaces(DirEntry file, Args args)
    {
        auto cachePath = file.calcDeepfacePath(args);
        if (!cachePath.exists)
        {
            cachePath.mkdirRecurse;
        }
        auto deepfaceCache = cachePath.buildPath("deepface.json");
        string response;
        if (deepfaceCache.exists)
        {
            response = deepfaceCache.readText;
        }
        else
        {
            auto msg = "%s,%s".format(file, cachePath);
            writeln("Writing to deepface process %s".format(msg));
            pipes.stdin.writeln(msg);
            pipes.stdin.flush();
            response = pipes.stdout.readln();
            deepfaceCache.write(response);
        }
        writeln("Deepface info: ", response);
        return null;
    }
    void finish()
    {
        pipes.stdin.writeln("quit");
        pipes.stdin.flush();
        string response = pipes.stdout.readln();
        writeln("DeepfaceProcess ", response);
        instance = null;
    }
}

void finishDeepface(Args args)
{
    DeepfaceProcess.getInstance(args.deepfaceIdentities).finish;
}

auto deepface(DirEntry file, Args args)
{

    return DeepfaceProcess
        .getInstance(args.deepfaceIdentities)
        .extractFaces(file, args);
}

void deepface2(string dir)
{
    auto command = "deepface extract_faces %s".format(dir);
    auto output = command.executeShell;
    if (output.status != 0)
    {
        throw new Exception("Cannot run " ~ command);
    }
    auto faces = output.output.matchAll(regex(
                                            ", 'facial_area': \\{'x': (?P<x>\\d+), 'y': (?P<y>\\d+), 'w': (?P<width>\\d+), 'h': (?P<height>\\d+)\\}, 'confidence': (?P<confidence>.+)\\}"));
    if (!faces.empty)
    {
        Image image;
        image.loadFromFile(dir);
        if (!image.isValid)
        {
            throw new Exception("Cannot load image");
        }

        int idx = 0;
        foreach (face; faces)
        {
            const x = face["x"].to!int;
            const y = face["y"].to!int;
            const w = face["width"].to!int;
            const h = face["height"].to!int;
            Image part = Image(w, h, PixelType.rgb8);
            for (int j=0; j<h; ++j)
            {
                for (int i=0; i<w; ++i)
                {
                    *((cast(ubyte*)part.scanptr(j))+3*i+0) = *((cast(ubyte*)image.scanptr(j+y))+3*(i+x)+0);
                    *((cast(ubyte*)part.scanptr(j))+3*i+1) = *((cast(ubyte*)image.scanptr(j+y))+3*(i+x)+1);
                    *((cast(ubyte*)part.scanptr(j))+3*i+2) = *((cast(ubyte*)image.scanptr(j+y))+3*(i+x)+2);
                }
            }
            part.saveToFile(ImageFormat.JPEG, "%s-%s.jpg".format(dir, idx++));
        }
    }
}
