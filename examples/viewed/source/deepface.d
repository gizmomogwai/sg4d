module deepface;

import std.process : pipeShell, Redirect, ProcessPipes;
import args : Args;
import gamut : Image, ImageFormat, PixelType;
import imagedb : shorten;
import mir.serde : serdeIgnoreUnexpectedKeys, serdeOptional, serdeKeys;
import std.algorithm : map, filter;
import std.array : split, join, array;
import std.concurrency : initOnce;
import std.conv : to;
import std.file : mkdirRecurse, exists, readText, write;
import std.regex : ctRegex, regex, matchAll;
import std.stdio : File, writeln;
import std.string : format, strip, toStringz, replace;
import thepath : Path;

version (unittest)
{
    import unit_threaded : should;
}
else
{
    import mir.deser.json : deserializeJson;
    import mir.ser.json : serializeJson;
}

Path calcDeepfaceCachePath(Path file, Args args)
{
    auto deepfaceDirectory = args.directory != Path.init
        ? args.directory.join(".deepfaceCache") : args.album.parent.join(".deepfaceCache");
    return deepfaceDirectory.join(file.shorten(args));
}

auto calcIdentityName(string s, Path suffix)
{
    auto h = s.replace(suffix.toString ~ "/", "");
    return h.split("/")[0];
}

@("calcIdentityName from path") unittest
{
    "abc/ME/def".calcIdentityName(Path("abc")).should == "ME";
}

@serdeIgnoreUnexpectedKeys struct Face
{
    float confidence;
    @serdeKeys("file_name")
    string face;
    @serdeOptional string name; /// null if not recognized
    Match[] match;
    Region region;
    void calcName(Args args)
    {
        foreach (m; match)
        {
            this.name = m.identity.calcIdentityName(args.deepfaceIdentities); // TODO this looks only at first identity
            break;
        }
    }
}

@serdeIgnoreUnexpectedKeys struct Match
{
    string identity;
}

struct Region
{
    int x;
    int y;
    @serdeKeys("w")
    int width;
    @serdeKeys("h")
    int height;
}

class DeepfaceProcess
{
    __gshared DeepfaceProcess instance;

    private ProcessPipes pipes;

    public static auto getInstance(Path identitiesPath)
    {
        return initOnce!instance(new DeepfaceProcess(identitiesPath));
    }

    private this(Path identitiesPath)
    {
        pipes = pipeShell("./mydeepface.py %s".format(identitiesPath),
                Redirect.stdin | Redirect.stdout);
    }

    Face[] extractFaces(Path file, Args args)
    {
        writeln(file);
        auto cachePath = file.calcDeepfaceCachePath(args);
        if (!cachePath.exists)
        {
            cachePath.mkdir(true);
        }
        writeln(1);
        auto deepfaceCache = cachePath.join("deepface.json");
        string response;
        if (deepfaceCache.exists)
        {
            response = deepfaceCache.readFileText();
        }
        else
        {
            auto msg = "%s,%s".format(file, cachePath);
            writeln("Writing to deepface process %s".format(msg));
            pipes.stdin.writeln(msg);
            pipes.stdin.flush();
            response = pipes.stdout.readln();
            deepfaceCache.writeFile(response);
        }
        writeln("Deepface info: ", response);
        version (unittest)
        {
            return null;
        }
        else
        {
            if (response == null)
            {
                return null;
            }
            Face[] faces = deserializeJson!(Face[])(response).filter!(f => f.confidence > 0.5f).array;
            foreach (ref face; faces)
            {
                face.calcName(args);
            }
            return faces;
        }
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

Face[] deepface(Path file, Args args)
{

    return DeepfaceProcess.getInstance(args.deepfaceIdentities).extractFaces(file, args);
}
