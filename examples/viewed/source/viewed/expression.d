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
import std.range : ElementType, empty, front;
import std.string : format;
import std.variant : Variant, variantArray;
import thepath : Path;
import viewed.deepface : Face;
import viewed.imagedb : ImageFile;

version (unittest)
{
    import unit_threaded : should, shouldThrow;
}

alias StringParser = Parser!(immutable(char));

abstract class Predicate
{
    void init(Variant[] args)
    {
    }

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

class CallPredicate : Predicate
{
    Variant[] arguments;
    Predicate predicate;
    static string[string] names;
    static this()
    {
        names = [
            "and": "viewed.expression.AndPredicate",
            "hasFaces": "viewed.expression.HasFacesPredicate",
            "hasGps": "viewed.expression.HasGpsPredicate",
            "hasUnreviewedFaces": "viewed.expression.HasUnreviewedFacesPredicate",
            "nearLatLon": "viewed.expression.NearLatLonPredicate",
            "not": "viewed.expression.NotPredicate",
            "or": "viewed.expression.OrPredicate",
            "tagStartsWith": "viewed.expression.TagStartsWithPredicate",
            "pathIncludes": "viewed.expression.PathIncludesPredicate",
        ];
    }

    this(string shortName, Variant[] arguments)
    {
        this.arguments = arguments;
        (shortName in names).enforce("'" ~ shortName ~ "' not registered");
        predicate = cast(Predicate) Object.factory(names[shortName]);
        predicate.init(arguments);
    }

    override bool test(ImageFile imageFile)
    {
        return predicate.test(imageFile);
    }
}

float calcDistance(float[] from, float[] to)
{
    float dx = to[0] - from[0];
    float dy = to[1] - from[1];
    return sqrt(dx * dx + dy * dy);
}

class NearLatLonPredicate : Predicate
{
    float latitude;
    float longitude;
    float distance = 0.1;
    override void init(Variant[] args)
    {
        if (args.length >= 2)
        {
            latitude = args[0].get!TagPredicate
                .tag
                .to!float;
            longitude = args[1].get!TagPredicate
                .tag
                .to!float;
            if (args.length == 3)
            {
                distance = args[2].get!TagPredicate
                    .tag
                    .to!float;
            }
        }
    }

    override bool test(ImageFile imageFile)
    {
        if (imageFile.gps is null)
        {
            return false;
        }
        return calcDistance(imageFile.gps, [latitude, longitude]) < distance;
    }
}

class HasGpsPredicate : Predicate
{
    override bool test(ImageFile imageFile)
    {
        return imageFile.gps !is null;
    }
}

class AndPredicate : Predicate
{
    Predicate[] predicates;
    override void init(Variant[] args)
    {
        (args.length > 0).enforce("'and' needs at least one argument");
        foreach (arg; args)
        {
            predicates ~= arg.get!Predicate;
        }
    }

    override bool test(ImageFile imageFile)
    {
        return predicates.all!(p => p.test(imageFile));
    }
}

class OrPredicate : Predicate
{
    Predicate[] predicates;
    override void init(Variant[] args)
    {
        (args.length > 0).enforce("'or' needs at least one argument");
        foreach (arg; args)
        {
            predicates ~= arg.get!Predicate;
        }
    }

    override bool test(ImageFile imageFile)
    {
        return predicates.any!(p => p.test(imageFile));
    }
}

class NotPredicate : Predicate
{
    Predicate predicate;
    override void init(Variant[] args)
    {
        (args.length == 1).enforce("'not' needs exactly one argument");
        predicate = args.front.get!Predicate;
    }

    override bool test(ImageFile imageFile)
    {
        return !predicate.test(imageFile);
    }
}

class TagStartsWithPredicate : Predicate
{
    string prefix;
    override void init(Variant[] args)
    {
        (args.length == 1).enforce("'tagStartsWith' needs exactly one argument");
        prefix = args.front.get!TagPredicate.tag;
    }

    override bool test(ImageFile imageFile)
    {
        return imageFile.tags.any!(t => t.startsWith(prefix));
    }
}

class HasFacesPredicate : Predicate
{
    override bool test(ImageFile imageFile)
    {
        return imageFile.faces !is null;
    }
}

class HasUnreviewedFacesPredicate : Predicate
{
    override bool test(ImageFile imageFile)
    {
        if (imageFile.faces is null)
        {
            return false;
        }
        return imageFile.faces.any!(face => !face.done);
    }
}

class PathIncludesPredicate : Predicate
{
    string part;
    override void init(Variant[] args)
    {
        (args.length == 1).enforce("'pathIncludes' needs exactly one argument");
        part = args.front.get!TagPredicate.tag;
    }

    override bool test(ImageFile imageFile)
    {
        return !imageFile.file.toString.find(part).empty;
    }
}

class ExpressionParser
{
    static auto alnumWithSlash()
    {
        return new Regex(`-?[\.\w\d/\\-]+`, true) ^^ (data) {
            return variantArray(data[0]);
        };
    }

    StringParser expression()
    {
        return call() | terminal();
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

    StringParser call()
    {
        return (regex("\\s*\\(\\s*",
                false) ~ alnum!(immutable(char)) ~ (-arguments()) ~ regex("\\s*\\)\\s*", false)) ^^ (
                data) {
            return variantArray(new CallPredicate(data[0].get!string, data[1 .. $]));
        };
    }

    StringParser arguments()
    {
        return *(regex("\\s*", false) ~ lazyExpression());
    }
}

/++
 + Convenience function to parse an expression and return the predicate.
 +/
auto predicateForExpression(string s)
{
    return new ExpressionParser().expression().parse(s).results[0].get!Predicate;
}

@("expression parser") unittest
{
    ImageFile imageFile = dummyFile;

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
    ImageFile imageFile = dummyFile;
    auto p = predicateForExpression("(pathIncludes gib)");
    p.test(imageFile).should == true;

    p = predicateForExpression("(pathIncludes abc/def-2)");
    p.test(imageFile).should == false;
}

@("not without arguments raises expection") unittest
{
    ImageFile imageFile = dummyFile;

    predicateForExpression("(not)").shouldThrow;
}

@("tagStartsWith without arguments raises exception") unittest
{
    ImageFile imageFile = dummyFile;

    predicateForExpression("(tagStartsWith)").shouldThrow;
}

@("tagStartsWith with too many arguments raises exception") unittest
{
    ImageFile imageFile = dummyFile;

    predicateForExpression("(tagStartsWith a b)").shouldThrow;
}

version (unittest)
{
    auto dummyFile()
    {
        return new ImageFile(Path("."), Path("gibts nicht.jpg"));
    }
}
@("parseExpression") unittest
{
    ImageFile imageFile = dummyFile;

    auto p = predicateForExpression("abc");
    imageFile.tags = ["abc", "def"];
    p.test(imageFile).should == true;
    imageFile.tags = ["def"];
    p.test(imageFile).should == false;
}

@("calling unknown function") unittest
{
    ImageFile imageFile = dummyFile;

    predicateForExpression("(unknown)").shouldThrow;
}

@("nearLatLon") unittest
{
    ImageFile imageFile = dummyFile;

    auto p = predicateForExpression("(nearLatLon 1.1 2.2 0.1)");
    p.test(imageFile).should == false;

    imageFile.gps = [1.1, 2.2];
    p.test(imageFile).should == true;

    imageFile.gps = [2.0, 3.0];
    p.test(imageFile).should == false;

    imageFile.gps = [2.0, 3.0, 5.0];
    p.test(imageFile).should == false;
}
