module viewed.tags;

import std.array : split, array, join;
import std.conv : to;
import std.format : format;
import thepath : Path;
import std.algorithm : map, filter, joiner;

string identityTag(string identity) => format!("identity:%s")(identity);

auto loadTags(Path image)
{
    auto tagsFile = Path(image.toString() ~ ".tags");
    if (tagsFile.exists())
    {
        return tagsFile.readFileText.loadTagsFile();
    }
    auto propertiesFile = Path(image.toString() ~ ".properties");
    if (propertiesFile.exists())
    {
        auto result = propertiesFile.readFileText.loadJavaProperties();
        tagsFile.storeTags(result);
        return result;
    }
    return null;
}

auto storeTags(Path tagsFile, string[] tags)
{
    tagsFile.writeFile(tags.toTagsFile());
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

string toTagsFile(string[] args)
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
