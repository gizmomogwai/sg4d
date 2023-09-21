module deepface;

import std.process : executeShell, pipeShell, Redirect, ProcessPipes;
import std.stdio : writeln; // TODO
import std.string : format, strip, toStringz, replace;
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
import mir.serde : serdeIgnoreUnexpectedKeys, serdeOptional, serdeKeys;
version (unittest)
{
    import unit_threaded : should;
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
    //string rectangle;
    @serdeOptional
    string name; /// null if not recognized
    Match[] match;
    Region region;
    void calcName(Args args)
    {
        foreach (m; match)
        {
            name = m.identity.calcIdentityName(args.deepfaceIdentities); // TODO this looks only at first identity
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
        version (unittest)
        {
            return null;
        }
        else
        {
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

Face[] deepface(DirEntry file, Args args)
{

    return DeepfaceProcess
        .getInstance(args.deepfaceIdentities)
        .extractFaces(file, args);
}
