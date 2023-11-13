module viewed.tags;

import std.algorithm : map, filter, joiner;
import std.array : split, array, join;
import std.conv : to;
import std.format : format;
import std.range : empty;
import thepath : Path;

version (unittest)
{
    import unit_threaded : should;
}

string identityTag(string identity) => format!("identity:%s")(identity);

auto toTagsPath(Path imagePath)
{
    return Path(imagePath.toString() ~ ".tags");
}

auto loadTags(Path imagePath)
{
    auto tagsPath = imagePath.toTagsPath();
    if (tagsPath.exists())
    {
        return tagsPath.readFileText.loadTagsFile();
    }
    auto propertiesFile = Path(imagePath.toString() ~ ".properties");
    if (propertiesFile.exists())
    {
        auto result = propertiesFile.readFileText.loadJavaProperties();
        tagsPath.storeTags(result);
        return result;
    }
    return null;
}

auto storeTags(Path imagePath, string[] tags)
{
    auto tagsPath = imagePath.toTagsPath();
    if (tags.empty)
    {
        tagsPath.remove();
    }
    else
    {
        tagsPath.writeFile(tags.toTagsFileContent());
    }
}

private auto loadTagsFile(string content)
{
    return content.split(",").array;
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

string toTagsFileContent(string[] args)
{
    return args.join(",");
}

string toJavaProperties(string[] tags)
{
    return tags.map!(t => format!("%s=true")(t)).joiner("\n").to!string ~ "\n";
}

@("convert to java properties") unittest
{
    ["a", "b", "c"].toJavaProperties.should == "a=true\nb=true\nc=true\n";
}
