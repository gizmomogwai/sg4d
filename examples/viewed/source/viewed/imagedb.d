module viewed.imagedb;

import args : Args;
import viewed.deepface : deepface, Face, calcDeepfaceCachePath, calcDeepfaceJsonPath;
import imgui : Editor;
import mir.serde : serdeIgnoreUnexpectedKeys, serdeOptional, serdeKeys;
import progressbar : withTextUi;
import std.algorithm : sort, remove, find, filter, map, countUntil, joiner;
import std.array : join, array, replace;
import std.conv : to;
import std.datetime.stopwatch : StopWatch, AutoStart, msecs;
import std.exception : enforce;
import std.file : SpanMode;
import std.format : format;
import std.process : execute;
import std.range : empty;
import std.regex : replaceFirst, regex, matchFirst, ctRegex;
import std.stdio : writeln;
import thepath : Path;
import viewed.expression : predicateForExpression;
import viewed.tags : identityTag, loadCache, storeCache;

version (unittest)
{
    import unit_threaded : should, shouldApproxEqual;
}
else
{
    import mir.deser.json : deserializeJson;
    import mir.ser.json : serializeJson;
}


Path shorten(Path file, Args args)
{
    enum firstSlash = ctRegex!("^/");
    return Path(file.toString.replace(args.directory != Path.init
            ? args.directory.toString() : "", "").replace(args.album != Path.init
            ? args.album.parent.toString() : "", "").replaceFirst(firstSlash, ""));
}

class ImageFile
{
    Path file;
    Path baseDirectory;
    string[] tags;

    float[] gps; // lat, lon, alt

    Face[] faces;
    string allNames;
    /// is exifdata read in
    bool metadataRead;
    /// exifdata if available
    Metadata metadata;

    this(Path baseDirectory, Path file)
    {
        this.file = file;
        this.baseDirectory = baseDirectory;
        auto cacheData = file.loadCache(baseDirectory);
        this.tags = cacheData.tags;
        this.gps = cacheData.gps;
        if (!cacheData.found // in a transition period it could be that old caches are used, that do not yet contain existing gps.
            // out of a transition period the cache data should always be complete
            // || this.gps == null
            )
        {
            if (hasMetadata)
            {
                auto metadata = getMetadata;
                this.gps = parseGps(metadata.position, metadata.altitude);
                if (this.gps != null)
                {
                    file.storeCache(baseDirectory, this.tags, this.gps);
                }
            }
        }
    }

    void addTag(string tag)
    {
        if (!hasTag(tag))
        {
            tags ~= tag;
            tags.sort;
            file.storeCache(baseDirectory, tags, gps);
        }
    }

    void removeTag(string tag)
    {
        if (hasTag(tag))
        {
            tags = tags.remove!(i => i == tag);
            file.storeCache(baseDirectory, tags, gps);
        }
    }

    bool hasTag(string tag)
    {
        return !tags.find(tag).empty;
    }

    auto deepface(Args args) const
    {
        return file.deepface(args);
    }

    void setFaces(Face[] faces)
    {
        this.faces = faces;
        this.allNames = faces.filter!(f => f.name)
            .map!(f => f.name)
            .join(", ");
    }

    bool hasMetadata()
    {
        if (metadataRead == false)
        {
            metadata = Metadata.read(file);
            metadataRead = true;
        }
        return metadata != Metadata.init;
    }

    auto getMetadata()
    {
        return metadata;
    }

    auto storeFaceInfo(Args args)
    {
        version (unittest)
        {
        }
        else
        {
            Path deepfaceJson = file.calcDeepfaceCachePath(args).calcDeepfaceJsonPath();
            Path newFile = deepfaceJson.withExt("new");
            newFile.writeFile(serializeJson(faces));
            auto result = ["mv", newFile.toString, deepfaceJson.toString].execute;
            if (result.status != 0)
            {
                writeln("Cannot rename ", newFile, " to ", deepfaceJson);
            }
        }
    }
}

float[] parseGps(string latLonString, string altitudeString)
{
    float[] result;
    auto latLon = latLonString.matchFirst(regex(`(?P<lat>[\d\.]+) ., (?P<lon>[\d\.]+) .`));
    if (!latLon.empty)
    {
        result ~= latLon["lat"].to!float;
        result ~= latLon["lon"].to!float;
        auto alt = altitudeString.matchFirst(regex(`(?P<altitude>\d+) m`));
        if (!alt.empty)
        {
            result ~= alt["altitude"].to!float;
        }
    }
    return result;
}

@("parseGps") unittest
{
    float[] result = parseGps("48.14211389 N, 11.58691944 E", "557 m Above Sea Level");
    result[0].should ~ 48.142;
    result[1].should ~ 11.586;
    result[2].should ~ 557.0;
}

@serdeIgnoreUnexpectedKeys struct Metadata
{
    @serdeKeys("CreateDate") @serdeOptional @("Creation Date")
    string creationDate;

    @serdeKeys("GPSPosition") @serdeOptional @("GPS Position")
    string position;

    @serdeKeys("GPSAltitude") @serdeOptional @("GPS Altitude")
    string altitude;

    public static auto read(Path file)
    {
        auto exiftool = execute([
            "exiftool", "-coordFormat", "%.8f", "-json", file.toString()
        ]);
        if (exiftool.status != 0)
        {
            writeln("exiftool failed");
            return Metadata.init;
        }

        version (unittest)
        {
            return Metadata.init;
        }
        else
        {
            // writeln(exiftool.output);
            auto result = deserializeJson!(Metadata[])(exiftool.output);
            return result[0];
        }
    }
}

class Files
{
    public ImageFile[] files;
    public Editor filter;
    public bool filterState;
    public ImageFile[] filteredFiles;
    size_t currentIndex;
    enum IMAGE_PATTERN = "{*.jpg,*.JPG,*.jpeg,*.JPEG*.png,*.PNG}";
    Face[] faces;
    this(Path directory)
    {
        // dfmt off
        files = directory
            .walk(IMAGE_PATTERN, SpanMode.depth)
            .filter!(f => f.toString().find(".deepface").empty)
            .array
            .sort
            .array
            .withTextUi("%>20P%>3p")
            .map!(entry => new ImageFile(directory, entry))
            .array;
        // dfmt on
        runFilter();
        init();
    }

    private void init()
    {
        (files.length > 0).enforce("no images found");
        currentIndex = 0;
    }

    this(Path[] directories)
    {
        // dfmt off
        files = directories.map!(
            dir => dir
                .walk(IMAGE_PATTERN, SpanMode.depth)
                .filter!(f => f.toString().find(".deepface").empty)
                .array
                .sort
                .array
                .withTextUi("%>20P%>3p")
                .map!(entry => new ImageFile(dir, entry))
            )
            .joiner
            .array;
        // dfmt on
        runFilter();
        init();
    }

    void runFilter()
    {
        if (filter.buffer.empty)
        {
            filteredFiles = files;
            filterState = true;
        }
        else
        {
            try
            {
                auto predicate = filter.buffer.predicateForExpression;
                filteredFiles = files.filter!(f => predicate.test(f)).array;
                filterState = true;
            }
            catch (Exception e)
            {
                writeln(e);
                filteredFiles = files;
                filterState = false;
            }
        }
    }

    void select(ImageFile file)
    {
        currentIndex = filteredFiles.countUntil(file);
    }

    bool empty()
    {
        return filteredFiles.length == 0;
    }

    auto front()
    {
        try
        {
            if (filteredFiles.empty)
            {
                throw new Exception("filtered files empty");
            }
        }
        catch (Exception e)
        {
            writeln(e.info.toString);
        }
        return filteredFiles[currentIndex];
    }

    void popFront()
    {
        currentIndex++;
        if (currentIndex == filteredFiles.length)
        {
            currentIndex = 0;
        }
    }

    auto back()
    {
        return filteredFiles[currentIndex];
    }

    void popBack()
    {
        if (currentIndex > 0)
        {
            currentIndex--;
        }
        else
        {
            enforce(!filteredFiles.empty, "No images");
            currentIndex = filteredFiles.length + -1;
        }
    }

    void jumpTo(in Path s)
    {
        const h = filteredFiles.countUntil!(v => v.file == s);
        if (h != -1)
        {
            currentIndex = h;
        }
    }

    void update()
    {
        if (empty)
        {
            runFilter();
            currentIndex = 0;
        }
        else
        {
            auto current = front;
            runFilter();
            currentIndex = filteredFiles.countUntil(current);
            if (currentIndex == -1)
            {
                currentIndex = 0;
            }
        }
    }

    void updateImage(ulong index, immutable(Face)[] faces)
    {
        files[index].setFaces(cast(Face[]) faces);
    }
}

auto getFiles(ref Args args)
{
    const sw = StopWatch(AutoStart.yes);
    scope (exit)
    {
        writeln("getFiles took: %s".format(sw.peek));
    }
    if (args.album != Path.init)
    {
        version (unittest)
        {
            assert(0);
        }
        else
        {
            args.album = args.album.expandTilde;
            // dfmt off
            auto directories = args
                .album
                .readFileText
                .deserializeJson!(string[])
                .map!(d => args.album.parent.join(d))
                .array;
            // dfmt on
            return new Files(directories);
        }
    }
    else
    {
        args.directory = args.directory.expandTilde;
        return new Files(args.directory);
    }
}
