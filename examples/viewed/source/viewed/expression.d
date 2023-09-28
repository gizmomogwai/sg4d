module viewed.expression;

import pc4d.parsers : alnum, lazyParser, regex;
import pc4d.parser : Parser;
import std.string : format;
import std.algorithm : all, any;
import std.functional : toDelegate;
import std.variant : Variant, variantArray;
import std.algorithm : countUntil, any, startsWith;
import viewed : ImageFile;
import std.exception : enforce;

version (unittest)
{
    import unit_threaded : should;
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

bool andPredicate(ImageFile imageFile, Variant[] arguments)
{
    enforce(arguments.length > 0, "and needs at least one argument");
    return arguments.all!(m => m.get!Matcher.matches(imageFile));
}

bool orPredicate(ImageFile imageFile, Variant[] arguments)
{
    enforce(arguments.length > 0, "or needs at least one argument");
    return arguments.any!(m => m.get!Matcher.matches(imageFile));
}

bool notPredicate(ImageFile imageFile, Variant[] arguments)
{
    enforce(arguments.length == 1, "not needs one argument");
    return !arguments[0].get!Matcher.matches(imageFile);
}

bool tagStartsWith(ImageFile imageFile, Variant[] arguments)
{
    enforce(arguments.length == 1, "tagStartsWith needs one argument");
    const tagMatcher = arguments[0].get!TagMatcher;
    return imageFile.tags.any!(t => t.startsWith(tagMatcher.tag));
}

bool hasFaces(ImageFile imageFile, Variant[] arguments)
{
    enforce(arguments.length == 0, "hasFaces must not have arguments");
    return imageFile.faces !is null;
}

Functions registerFunctions()
{
    Functions functions;
    functions["or"] = toDelegate(&orPredicate);
    functions["and"] = toDelegate(&andPredicate);
    functions["not"] = toDelegate(&notPredicate);
    functions["tagStartsWith"] = toDelegate(&tagStartsWith);
    functions["hasFaces"] = toDelegate(&hasFaces);
    return functions;
}

@("expression parser") unittest
{
    auto parser = new ExpressionParser(registerFunctions());
    auto result = parser.expression.parse("abc");
    result.success.should == true;
    ImageFile imageFile = new ImageFile("gibt nicht");
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
    imageFile.tags= ["a", "b"];
    m.matches(imageFile).should == true;
    imageFile.tags = ["a", "c"];
    m.matches(imageFile).should == true;
    imageFile.tags= ["c"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["a"];
    m.matches(imageFile).should == false;

    result = parser.expression.parse("(not a)");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    imageFile.tags = ["a"];
    m.matches(imageFile).should == false;
    imageFile.tags= ["a", "b"];
    m.matches(imageFile).should == false;
    imageFile.tags = ["b"];
    m.matches(imageFile).should == true;
    imageFile.tags = [];
    m.matches(imageFile).should == true;
}

auto matcherForExpression(string s)
{
    return new ExpressionParser(registerFunctions()).expression().parse(s).results[0].get!Matcher;
}

@("parseExpression") unittest
{
    ImageFile imageFile = new ImageFile("gibts nicht");
    auto e = matcherForExpression("abc");
    imageFile.tags = ["abc", "def"];
    e.matches(imageFile).should == true;
    imageFile.tags = ["def"];
    e.matches(imageFile).should == false;
}
