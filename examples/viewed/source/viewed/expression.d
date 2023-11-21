module viewed.expression;

import pc4d.parser : Parser;
import pc4d.parsers : alnum, lazyParser, regex, Regex;
import std.algorithm : all, any, map, find;
import std.algorithm : countUntil, any, startsWith;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.functional : toDelegate;
import std.math : sqrt;
import std.range : ElementType, empty;
import std.string : format;
import std.variant : Variant, variantArray;
import viewed : ImageFile, Path;

version (unittest)
{
    import unit_threaded : should, shouldThrow;
}

alias StringParser = Parser!(immutable(char));
alias PredicateDelegate = bool delegate(ImageFile, Variant[]);
alias Delegates = PredicateDelegate[string];

abstract class Predicate
{
    abstract bool test(ImageFile image);
}

class TagPredicate : Predicate
{
    string tag;
    this(string tag)
    {
        this.tag = tag;
    }

    override bool test(ImageFile image)
    {
        foreach (tag; image.tags)
        {
            if (this.tag == tag)
            {
                return true;
            }
        }
        return false;
    }
}

class DelegateCallPredicate : Predicate
{
    Delegates delegates;
    string delegateName;
    Variant[] arguments;
    this(Delegates delegates, string delegateName, Variant[] arguments)
    {
        this.delegates = delegates;
        this.delegateName = delegateName;
        this.arguments = arguments;
    }

    override bool test(ImageFile imageFile)
    {
        if (delegateName !in delegates)
        {
            throw new Exception(format!("Unknown function '%s'")(delegateName));
        }
        return delegates[delegateName](imageFile, arguments);
    }
}

auto alnumWithSlash()
{
    return new Regex(`-?[\.\w\d/\\-]+`, true) ^^ (data) {
        return variantArray(data[0]);
    };
}

class ExpressionParser
{
    Delegates delegates;
    this(Delegates delegates)
    {
        this.delegates = delegates;
    }

    StringParser expression()
    {
        return delegateCall() | terminal();
    }

    StringParser lazyExpression()
    {
        return lazyParser(&expression);
    }

    StringParser terminal()
    {
        return (regex("\\s*", false) ~ alnumWithSlash() ~ regex("\\s*", false)) ^^ (data) {
            return variantArray(new TagPredicate(data[0].get!string));
        };
    }

    StringParser delegateCall()
    {
        return (regex("\\s*\\(\\s*",
                false) ~ alnum!(immutable(char)) ~ (-arguments()) ~ regex("\\s*\\)\\s*", false)) ^^ (
                data) {
            return variantArray(new DelegateCallPredicate(delegates, data[0].get!string, data[1 .. $]));
        };
    }

    StringParser arguments()
    {
        return *(regex("\\s*", false) ~ lazyExpression());
    }
}

bool andPredicate(ImageFile imageFile, Predicate[] arguments)
{
    enforce(arguments.length > 0, "and needs at least one argument");
    return arguments.all!(p => p.test(imageFile));
}

bool orPredicate(ImageFile imageFile, Predicate[] arguments)
{
    enforce(arguments.length > 0, "or needs at least one argument");
    return arguments.any!(p => p.test(imageFile));
}

bool notPredicate(ImageFile imageFile, Predicate argument)
{
    return !argument.test(imageFile);
}

bool tagStartsWith(ImageFile imageFile, TagPredicate tagPredicate)
{
    return imageFile.tags.any!(t => t.startsWith(tagPredicate.tag));
}

bool hasFaces(ImageFile imageFile)
{
    return imageFile.faces !is null;
}

bool hasUnreviewedFaces(ImageFile imageFile)
{
    if (imageFile.faces is null)
    {
        return false;
    }
    return imageFile.faces.any!(face => !face.done);
}

bool pathIncludes(ImageFile imageFile, TagPredicate tagPredicate)
{
    return !imageFile.file.toString.find(tagPredicate.tag).empty;
}

bool hasGps(ImageFile imageFile)
{
    return imageFile.gps != null;
}

bool nearLatLon(ImageFile imageFile, TagPredicate[] arguments)
{
    import std.stdio : writeln;
    if (imageFile.gps == null)
    {
        return false;
    }

    if (arguments.length >= 2)
    {
        float lat = arguments[0].tag.to!float;
        float lon = arguments[1].tag.to!float;
        float distance = 0.1;
        if (arguments.length == 3)
        {
            distance = arguments[2].tag.to!float;
        }

        return calcDistance(imageFile.gps, [lat, lon]) < distance;
    }
    return true;
}

float calcDistance(float[] from, float[] to)
{
    float dx = to[0] -from[0];
    float dy = to[1] -from[1];
    return sqrt(dx*dx + dy*dy);
}
                      
string delegateBody(T...)()
{
    import std.format : format;
    import std.traits : isArray;

    static if ((T.length == 2) && (isArray!(T[1])))
    {
        return format("return f(file, args.map!(i => i.get!(%s)).array);",
                ElementType!(T[1]).stringof);
    }
    else
    {
        string result = format("enforce(args.length == %s, \"'\" ~ name ~ \"' needs exactly %s arguments\");",
                T.length - 1, T.length - 1);
        result ~= "return f(file";
        static foreach (i; 1 .. T.length)
        {
            result ~= format(", args[%s].get!(%s)", i - 1, T[i].stringof);
        }
        result ~= ");";
        return result;
    }
}

/++
 + The parser calls registerd delegates with (ImageFile, Variant[]). The Variants contain subclasses of Predicate.
 + Register a "normal" delegates whose arguments are automatically extracted from the variants.
 + The mapping from variants to normal types follows the following strategy:
 + - all delegates need to take at least ImageFile as first parameter
 + - then they can take 0..n other non array types which are automatically taken out of the variant array
 + - or take one array type which elements are taken out of the variant array
 + If you want more control over the conversion add normal delegates to "delegates".
 +/
void wire(string name, Arguments...)(ref Delegates delegates, bool delegate(Arguments) f)
{
    const s = "delegates[name] = delegate(ImageFile file, Variant[] args) {"
        ~ delegateBody!(Arguments)() ~ "};";
    // pragma(msg, name~ ":");
    // pragma(msg, s);
    mixin(s);
}

Delegates registerDelegates()
{
    Delegates delegates;
    delegates.wire!("or")(toDelegate(&orPredicate));
    delegates.wire!("and")(toDelegate(&andPredicate));
    delegates.wire!("not")(toDelegate(&notPredicate));
    delegates.wire!("tagStartsWith")(toDelegate(&tagStartsWith));
    delegates.wire!("hasFaces")(toDelegate(&hasFaces));
    delegates.wire!("hasUnreviewedFaces")(toDelegate(&hasUnreviewedFaces));
    delegates.wire!("pathIncludes")(toDelegate(&pathIncludes));
    delegates.wire!("hasGps")(toDelegate(&hasGps));
    delegates.wire!("nearLatLon")(toDelegate(&nearLatLon));
    return delegates;
}

/++
 + Convenience function to parse an expression and return the matcher.
 +/
auto predicateForExpression(string s)
{
    return new ExpressionParser(registerDelegates()).expression().parse(s).results[0].get!Predicate;
}

@("expression parser") unittest
{
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));

    auto p = predicateForExpression("abc");
    imageFile.tags = ["abc"];
    p.test(imageFile).should == true;

    p = predicateForExpression("(or abc def)");
    imageFile.tags = ["abc"];
    p.test(imageFile).should == true;
    imageFile.tags = ["def"];
    p.test(imageFile).should == true;
    imageFile.tags = ["ghi"];
    p.test(imageFile).should == false;

    p = predicateForExpression("(and abc def)");
    imageFile.tags = ["abc"];
    p.test(imageFile).should == false;
    imageFile.tags = ["def"];
    p.test(imageFile).should == false;
    imageFile.tags = ["abc", "def"];
    p.test(imageFile).should == true;
    imageFile.tags = ["abc", "def", "ghi"];
    p.test(imageFile).should == true;

    p = predicateForExpression("(and a (or b c))");
    imageFile.tags = ["a", "b"];
    p.test(imageFile).should == true;
    imageFile.tags = ["a", "c"];
    p.test(imageFile).should == true;
    imageFile.tags = ["c"];
    p.test(imageFile).should == false;
    imageFile.tags = ["a"];
    p.test(imageFile).should == false;

    p = predicateForExpression("(not a)");
    imageFile.tags = ["a"];
    p.test(imageFile).should == false;
    imageFile.tags = ["a", "b"];
    p.test(imageFile).should == false;
    imageFile.tags = ["b"];
    p.test(imageFile).should == true;
    imageFile.tags = [];
    p.test(imageFile).should == true;

    p = predicateForExpression("(tagStartsWith abc)");
    imageFile.tags = ["abcd"];
    p.test(imageFile).should == true;
    imageFile.tags = ["ab"];
    p.test(imageFile).should == false;

    p = predicateForExpression("(hasFaces)");
    p.test(imageFile).should == false;

    import deepface : Face;

    imageFile.faces = [Face()];
    p.test(imageFile).should == true;

    p = predicateForExpression("(hasUnreviewedFaces)");
    // faces are not done
    imageFile.faces[0].done = false;
    p.test(imageFile).should == true;

    // faces are done
    imageFile.faces[0].done = true;
    p.test(imageFile).should == false;

    // no faces
    imageFile.faces = null;
    p.test(imageFile).should == false;
}

@("pathIncludes") unittest
{
    ImageFile imageFile = new ImageFile(Path("abc/def-1/test"));
    auto p = predicateForExpression("(pathIncludes abc/def-1)");
    p.test(imageFile).should == true;

    p = predicateForExpression("(pathIncludes abc/def-2)");
    p.test(imageFile).should == false;
}

@("not without arguments raises expection") unittest
{
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));

    auto p = predicateForExpression("(not)");
    p.test(imageFile).shouldThrow;
}

@("tagStartsWith without arguments raises exception") unittest
{
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));

    auto p = predicateForExpression("(tagStartsWith)");
    p.test(imageFile).shouldThrow;
}

@("tagStartsWith with too many arguments raises exception") unittest
{
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));

    auto p = predicateForExpression("(tagStartsWith a b)");
    p.test(imageFile).shouldThrow;
}

@("parseExpression") unittest
{
    ImageFile imageFile = new ImageFile(Path("gibts nicht"));

    auto p = predicateForExpression("abc");
    imageFile.tags = ["abc", "def"];
    p.test(imageFile).should == true;
    imageFile.tags = ["def"];
    p.test(imageFile).should == false;
}

@("calling unknown function") unittest
{
    ImageFile imageFile = new ImageFile(Path("gibts nicht"));

    auto p = predicateForExpression("(unknown)");
    p.test(imageFile).shouldThrow;
}
