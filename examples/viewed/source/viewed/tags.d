module viewed.tags;

import std.algorithm : map, filter, joiner;
import std.array : split, array, join;
import std.conv : to;
import std.format : format;
import std.range : empty;
import thepath : Path;
import std.typecons : Tuple;

version (unittest)
{
    import unit_threaded : should;
}

string identityTag(string identity) => format!("identity:%s")(identity);

auto toTagsPath(Path imagePath)
{
    return Path(imagePath.toString() ~ ".cache");
}

auto loadCache(Path imagePath)
{
    if (!imagePath.exists)
    {
        CacheData result;
        return result;
    }

    auto tagsPath = imagePath.toTagsPath();
    if (tagsPath.exists())
    {
        return tagsPath.readFileText.loadCacheFile();
    }

    auto propertiesFile = Path(imagePath.toString() ~ ".properties");
    if (propertiesFile.exists())
    {
        auto fromFile = propertiesFile.readFileText.loadJavaProperties();
        imagePath.storeCache(fromFile, []);
        CacheData result;
        result.found = true;
        result.tags = fromFile;
        return result;
    }
    CacheData result;
    imagePath.storeCache(result.tags, result.gps);
    return result;
}

auto storeCache(Path imagePath, string[] tags, float[] gps)
{
    auto tagsPath = imagePath.toTagsPath();
    /+
    if (tags.empty && gps.empty)
    {
        if (tagsPath.exists)
        {
            //tagsPath.remove();
        }
    }
    else
    {
    +/
        tagsPath.writeFile(toCacheFileContent(tags, gps));
        //}
}

alias CacheData = Tuple!(bool, "found", string[], "tags", float[], "gps");

private auto loadCacheFile(string content)
{
    auto lines = content.split("\n");
    string[] tags;
    if (lines.length > 0)
    {
        tags = lines[0].split(",").array;
    }
    float[] gps;
    if (lines.length > 1)
    {
        gps = lines[1].split(",").map!(i => i.to!(float)).array;
    }
    CacheData result;
    result.found = true;
    result.tags = tags;
    result.gps = gps;

    return result;
}

private auto loadJavaProperties(string content)
{
    return content.split("\n").map!(line => line.split("="))
        .filter!(keyValue => keyValue.length == 2 && keyValue[1] == "true")
        .map!(keyValue => keyValue[0])
        .array;
}

@("load java properties") unittest
{
    "iotd=true\n".loadJavaProperties.should == ["iotd"];
    "iotd=true\niotd2=true\n".loadJavaProperties.should == ["iotd", "iotd2"];
    "iotd=false\niotd2=true\n".loadJavaProperties.should == ["iotd2"];
}

string toCacheFileContent(string[] tags, float[] gps)
{
    return format!("%s\n%s\n")(
        tags.join(","),
        gps.map!("a.to!string").join(",")
    );
}

string toJavaProperties(string[] tags)
{
    return tags.map!(t => format!("%s=true")(t)).joiner("\n").to!string ~ "\n";
}

@("convert to java properties") unittest
{
    ["a", "b", "c"].toJavaProperties.should == "a=true\nb=true\nc=true\n";
}
