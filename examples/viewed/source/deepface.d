module deepface;

import std.process : pipeShell, Redirect, ProcessPipes;
import args : Args;
import gamut : Image, ImageFormat, PixelType;
import imagedb : shorten;
import mir.serde : serdeIgnoreUnexpectedKeys, serdeOptional, serdeKeys;
import std.algorithm : map;
import std.array : split, join;
import std.concurrency : initOnce;
import std.conv : to;
import std.file : mkdirRecurse, exists, readText, write;
import std.path : buildPath, dirName;
import std.regex : ctRegex, regex, matchAll;
import std.stdio : File, writeln;
import std.string : format, strip, toStringz, replace;

version (unittest)
{
    import unit_threaded : should;
}
else
{
    import mir.deser.json : deserializeJson;
    import mir.ser.json : serializeJson;
}

string calcDeepfaceCachePath(string file, Args args)
{
    auto deepfaceDirectory =
        args.directory ? args.directory.buildPath(".deepfaceCache") : args.album.dirName.buildPath(".deepfaceCache");
    return deepfaceDirectory.buildPath(file.shorten(args));
}

string calcIdentityName(string s, string suffix)
{
    string h = s.replace(suffix ~ "/", "");
    string result = "";
    foreach (c; h)
    {
        if (c == '/')
        {
            break;
        }
        result ~= c;
    }
    return result;
}
@("calcIdentityName from path") unittest {
    "abc/ME/def".calcIdentityName("abc").should == "ME";
}

@serdeIgnoreUnexpectedKeys
struct Face {
    @serdeKeys("file_name")
    string face;
    @serdeOptional
    string name; /// null if not recognized
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

@serdeIgnoreUnexpectedKeys
struct Match
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

    public static auto getInstance(string identitiesPath)
    {
        return initOnce!instance(new DeepfaceProcess(identitiesPath));
    }

    private this(string identitiesPath)
    {
        pipes = pipeShell("./mydeepface.py %s".format(identitiesPath), Redirect.stdin | Redirect.stdout);
    }
    Face[] extractFaces(string file, Args args)
    {
        auto cachePath = file.calcDeepfaceCachePath(args);
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
            Face[] faces = deserializeJson!(Face[])(response);
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

Face[] deepface(string file, Args args)
{

    return DeepfaceProcess
        .getInstance(args.deepfaceIdentities)
        .extractFaces(file, args);
}
