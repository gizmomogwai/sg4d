module sg.visitors;

import sg;
import sg.window;
import std.concurrency;

version (Default)
{
    public import sg.visitors.ogl2rendervisitor : TheRenderVisitor = OGL2RenderVisitor;
}
version (GL_33)
{
    public import sg.visitors.ogl33rendervisitor : TheRenderVisitor = OGL33RenderVisitor;
}

class BehaviorVisitor : Visitor
{
    alias visit = Visitor.visit;
    override void visit(Behavior n)
    {
        n.run();
        foreach (child; n.childs)
        {
            child.accept(this);
        }
    }
}

class PrintVisitor : Visitor
{
    import std.stdio;

    string indent = "";
    override void visit(Node node)
    {
        writeNode("Node", node);
    }

    override void visit(Scene n)
    {
        writeNode("Scene", n);
    }

    override void visit(ProjectionNode n)
    {
        writeNode("ProjectonNode", n);
    }

    override void visit(Observer n)
    {
        writeNode("Observer", n, (string indent) => writeln(indent, "position=", n.getPosition));
    }

    override void visit(TransformationNode n)
    {
        writeNode("TransformationNode", n);
    }

    override void visit(Shape n)
    {
        writeNode("Shape", n);
    }

    override void visit(Behavior n)
    {
        writeNode("Behavior", n);
    }

    private void writeNode(string type, Node node, void delegate(string) more = null)
    {
        writeln(indent, type);
        const oldIndent = indent;
        indent ~= "  ";
        writeln(indent, "name=", node.getName);
        writeln(indent, "live=", node.live);
        if (more)
        {
            more(indent);
        }
        writeln(indent, "#childs=", node.childs.length);
        foreach (child; node.childs)
        {
            child.accept(this);
        }
        indent = oldIndent;
    }
}
