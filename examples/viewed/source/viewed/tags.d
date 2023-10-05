module viewed.tags;

import std.array : split, array;
import std.conv : to;
import std.format : format;
import thepath : Path;
import std.algorithm : map, filter, joiner;

string identityTag(string identity) => format!("identity:%s")(identity);

auto loadTags(Path image)
{
    auto propertiesFile = Path(image.toString() ~ ".properties");
    if (propertiesFile.exists)
    {
        return propertiesFile.readFileText.loadJavaProperties;
    }
    return null;
}

auto storeTags(Path imageFile, string[] tags)
{
    auto propertiesFile = Path(imageFile.toString() ~ ".properties");
    propertiesFile.writeFile(tags.toJavaProperties());
}

auto loadJavaProperties(string content)
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

string toJavaProperties(string[] tags)
{
    return tags.map!(t => format!("%s=true")(t)).joiner("\n").to!string ~ "\n";
}

@("convert to java properties") unittest
{
    ["a", "b", "c"].toJavaProperties.should == "a=true\nb=true\nc=true\n";
}
