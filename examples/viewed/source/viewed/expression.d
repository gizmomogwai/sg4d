module viewed.expression;

import pc4d.parsers : alnum, lazyParser, regex;
import pc4d.parser : Parser;
import std.string : format;
import std.algorithm : all, any, map;
import std.range : ElementType;
import std.array : array;
import std.functional : toDelegate;
import std.variant : Variant, variantArray;
import std.algorithm : countUntil, any, startsWith;
import viewed : ImageFile;
import std.exception : enforce;

version (unittest)
{
    import unit_threaded : should, shouldThrow;
}

alias StringParser = Parser!(immutable(char));
alias Predicate = bool delegate(ImageFile, Variant[]);
alias Functions = Predicate[string];

abstract class Matcher
{
    abstract bool matches(ImageFile image);
}

class TagMatcher : Matcher
{
    string tag;
    this(string tag)
    {
        this.tag = tag;
    }

    override bool matches(ImageFile image)
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

class FunctionCallMatcher : Matcher
{
    Functions functions;
    string functionName;
    Variant[] arguments;
    this(Functions functions, string functionName, Variant[] arguments)
    {
        this.functions = functions;
        this.functionName = functionName;
        this.arguments = arguments;
    }

    override bool matches(ImageFile imageFile)
    {
        if (functionName !in functions)
        {
            throw new Exception(format!("Unknown function '%s'")(functionName));
        }
        return functions[functionName](imageFile, arguments);
    }
}

class ExpressionParser
{
    Functions functions;
    this(Functions functions)
    {
        this.functions = functions;
    }

    StringParser expression()
    {
        return functionCall() | terminal();
    }

    StringParser lazyExpression()
    {
        return lazyParser(&expression);
    }

    StringParser terminal()
    {
        return (regex("\\s*", false) ~ alnum!(immutable(char)) ~ regex("\\s*", false)) ^^ (data) {
            return variantArray(new TagMatcher(data[0].get!string));
        };
    }

    StringParser functionCall()
    {
        return (regex("\\s*\\(\\s*",
                      false) ~ alnum!(immutable(char)) ~ (-arguments()) ~ regex("\\s*\\)\\s*", false)) ^^ (
                          data) {
            return variantArray(new FunctionCallMatcher(functions, data[0].get!string, data[1 .. $]));
        };
    }

    StringParser arguments()
    {
        return *(regex("\\s*", false) ~ lazyExpression());
    }
}

bool andPredicate(ImageFile imageFile, Matcher[] arguments)
{
    enforce(arguments.length > 0, "and needs at least one argument");
    return arguments.all!(m => m.matches(imageFile));
}

bool orPredicate(ImageFile imageFile, Matcher[] arguments)
{
    enforce(arguments.length > 0, "or needs at least one argument");
    return arguments.any!(m => m.matches(imageFile));
}

bool notPredicate(ImageFile imageFile, Matcher argument)
{
    return !argument.matches(imageFile);
}

bool tagStartsWith(ImageFile imageFile, TagMatcher tagMatcher)
{
    return imageFile.tags.any!(t => t.startsWith(tagMatcher.tag));
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

/+
 + Creaate a delegate body for 3 cases:
 +  1. function does not take any arguments from the expression (e.g. hasFaces)
 +  2. function takes variable number of arguments (all the same) (mapped to an array of this type) (e.g. or)
 +  3. function takes several arguments (always the same count) (e.g. not or tagStartsWith)
 +/
string delegateBody(T...)()
{
    import std.format : format;
    import std.traits : isArray;
    static if (T.length == 1) // case 1
    {
        return format("enforce(args.length == 0, \"'\" ~ name ~ \"' must not have arguments\"); return f(file);");
    }
    else static if (T.length >= 2)
    {
        static if (isArray!(T[1])) // case 2
        {
            return format("return f(file, args.map!(i => i.get!(%s)).array);", ElementType!(T[1]).stringof);
        }
        else // case 3
        {
            string result = format("enforce(args.length == %s, \"'\" ~ name ~ \"' needs exactly %s arguments\");", T.length - 1, T.length - 1);
            result ~= "return f(file, ";
            static foreach (i; 1 .. T.length)
            {
                result ~= format("args[%s].get!(%s), ", i-1, T[i].stringof);
            }

            result = result[0..$-2];
            result ~= ");";
            return result;
        }
    }
}

void wire(string name, Arguments...)(ref Functions functions, bool delegate(Arguments) f)
{
    const s = "functions[name] = delegate(ImageFile file, Variant[] args) {" ~ delegateBody!(Arguments)() ~ "};";
//    pragma(msg, name~ ":");
//    pragma(msg, s);
    mixin(s);
}


Functions registerFunctions()
{
    Functions functions;
    functions.wire!("or")(toDelegate(&orPredicate));
    functions.wire!("and")(toDelegate(&andPredicate));
    functions.wire!("not")(toDelegate(&notPredicate));
    functions.wire!("tagStartsWith")(toDelegate(&tagStartsWith));
    functions.wire!("hasFaces")(toDelegate(&hasFaces));
    functions.wire!("hasUnreviewedFaces")(toDelegate(&hasUnreviewedFaces));
    return functions;
}

@("expression parser") unittest
{
    import thepath : Path;

    auto parser = new ExpressionParser(registerFunctions());
    auto result = parser.expression.parse("abc");
    result.success.should == true;
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));
    imageFile.tags = ["abc"];
    result.results[0].get!Matcher.matches(imageFile).should == true;

    result = parser.expression.parse("(or abc def)");
    result.success.should == true;
    auto m = result.results[0].get!Matcher;
    imageFile.tags = ["abc"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["def"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["ghi"];
    m.matches(imageFile).should == false;

    result = parser.expression.parse("(and abc def)");
    m = result.results[0].get!Matcher;
    imageFile.tags = ["abc"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["def"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["abc", "def"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["abc", "def", "ghi"];
    m.matches(imageFile).should == true;

    result = parser.expression.parse("(and a (or b c))");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    imageFile.tags = ["a", "b"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["a", "c"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["c"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["a"];
    m.matches(imageFile).should == false;

    result = parser.expression.parse("(not a)");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    imageFile.tags = ["a"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["a", "b"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["b"];
    m.matches(imageFile).should == true;
    imageFile.tags = [];
    m.matches(imageFile).should == true;

    result = parser.expression.parse("(tagStartsWith abc)");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    imageFile.tags = ["abcd"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["ab"];
    m.matches(imageFile).should == false;

    result = parser.expression.parse("(hasFaces)");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    m.matches(imageFile).should == false;

    import deepface : Face;
    imageFile.faces = [Face()];
    m.matches(imageFile).should == true;

    result = parser.expression.parse("(hasUnreviewedFaces)");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    imageFile.faces[0].done = false;
    m.matches(imageFile).should == true;

    imageFile.faces[0].done = true;
    m.matches(imageFile).should == false;
}

@("not without arguments raises expection") unittest {
    import thepath : Path;
    auto parser = new ExpressionParser(registerFunctions());
    auto result = parser.expression.parse("(not)");
    result.success.should == true;
    auto m = result.results[0].get!Matcher;
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));
    m.matches(imageFile).shouldThrow;
}

@("tagStartsWith without arguments raises exception") unittest {
    import thepath : Path;
    auto parser = new ExpressionParser(registerFunctions());
    auto result = parser.expression.parse("(tagStartsWith)");
    result.success.should == true;
    auto m = result.results[0].get!Matcher;
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));
    m.matches(imageFile).shouldThrow;
}

@("tagStartsWith with too many arguments raises exception") unittest {
    import thepath : Path;
    auto parser = new ExpressionParser(registerFunctions());
    auto result = parser.expression.parse("(tagStartsWith a b)");
    result.success.should == true;
    auto m = result.results[0].get!Matcher;
    ImageFile imageFile = new ImageFile(Path("gibt nicht"));
    m.matches(imageFile).shouldThrow;
}

auto matcherForExpression(string s)
{
    return new ExpressionParser(registerFunctions()).expression().parse(s).results[0].get!Matcher;
}

@("parseExpression") unittest
{
    import thepath : Path;

    ImageFile imageFile = new ImageFile(Path("gibts nicht"));
    auto e = matcherForExpression("abc");
    imageFile.tags = ["abc", "def"];
    e.matches(imageFile).should == true;
    imageFile.tags = ["def"];
    e.matches(imageFile).should == false;
}
