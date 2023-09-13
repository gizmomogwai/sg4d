module viewed.expression;

import pc4d.parsers : alnum, lazyParser, regex;
import pc4d.parser : Parser;
import std.string : format;
import std.algorithm : all, any;
import std.functional : toDelegate;
import std.variant : Variant, variantArray;

version (unittest)
{
    import unit_threaded : should;
}

alias StringParser = Parser!(immutable(char));
alias Predicate = bool delegate(string[], Variant[]);
alias Functions = Predicate[string];

abstract class Matcher
{
    abstract bool matches(string[] s);
}

class TagMatcher : Matcher
{
    string tag;
    this(string tag)
    {
        this.tag = tag;
    }

    override bool matches(string[] tags)
    {
        foreach (tag; tags)
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

    override bool matches(string[] tags)
    {
        if (functionName !in functions)
        {
            throw new Exception(format!("Unknown function '%s'")(functionName));
        }
        return functions[functionName](tags, arguments);
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
                false) ~ alnum!(immutable(char)) ~ arguments() ~ regex("\\s*\\)\\s*", false)) ^^ (
                data) {
            return variantArray(new FunctionCallMatcher(functions, data[0].get!string, data[1 .. $]));
        };
    }

    StringParser arguments()
    {
        return *(regex("\\s*", false) ~ lazyExpression());
    }
}

bool andPredicate(string[] tags, Variant[] matchers)
{
    return matchers.all!(m => m.get!Matcher.matches(tags));
}

bool orPredicate(string[] tags, Variant[] matchers)
{
    return matchers.any!(m => m.get!Matcher.matches(tags));
}

bool notPredicate(string[] tags, Variant[] matchers)
{
    if (matchers.length > 1)
    {
        throw new Exception("not only supports one argument");
    }
    return !matchers[0].get!Matcher.matches(tags);
}

Functions registerFunctions()
{
    Functions functions;
    functions["or"] = toDelegate(&orPredicate);
    functions["and"] = toDelegate(&andPredicate);
    functions["not"] = toDelegate(&notPredicate);
    return functions;
}

@("expression parser") unittest
{
    auto parser = new ExpressionParser(registerFunctions);
    auto result = parser.expression.parse("abc");
    result.success.should == true;
    result.results[0].get!Matcher.matches(["abc"]).should == true;

    result = parser.expression.parse("(or abc def)");
    result.success.should == true;
    auto m = result.results[0].get!Matcher;
    m.matches(["abc"]).should == true;
    m.matches(["def"]).should == true;
    m.matches(["ghi"]).should == false;

    result = parser.expression.parse("(and abc def)");
    m = result.results[0].get!Matcher;
    m.matches(["abc"]).should == false;
    m.matches(["def"]).should == false;
    m.matches(["abc", "def"]).should == true;
    m.matches(["abc", "def", "ghi"]).should == true;

    result = parser.expression.parse("(and a (or b c))");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    m.matches(["a", "b"]).should == true;
    m.matches(["a", "c"]).should == true;
    m.matches(["c"]).should == false;
    m.matches(["a"]).should == false;

    result = parser.expression.parse("(not a)");
    result.success.should == true;
    m = result.results[0].get!Matcher;
    m.matches(["a"]).should == false;
    m.matches(["a", "b"]).should == false;
    m.matches(["b"]).should == true;
    m.matches([]).should == true;
}

auto matcherForExpression(string s)
{
    return new ExpressionParser(registerFunctions()).expression().parse(s).results[0].get!Matcher;
}

@("parseExpression") unittest
{
    auto e = matcherForExpression("abc");
    e.matches(["abc", "def"]).should == true;
    e.matches(["def"]).should == false;
}
