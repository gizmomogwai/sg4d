module sg.visitors;

import sg;
import sg.window;
import std.concurrency;

version (Default)
{
    public import sg.visitors.ogl2rendervisitor : RenderVisitor = OGL2RenderVisitor;
}
version (GL_33)
{
    public import sg.visitors.ogl33rendervisitor : RenderVisitor = OGL33RenderVisitor;
}

class BehaviorVisitor : Visitor
{
    alias visit = Visitor.visit;
    override void visit(Behavior n)
    {
        n.run();
        foreach (child; n.childs)
        {
            child.get.accept(this);
        }
    }
}

class PrintVisitor : Visitor
{
    import std.stdio;

    string indent = "";
    override void visit(NodeData node)
    {
        writeNode("NodeData", node);
    }

    override void visit(GroupData g)
    {
        writeNode("GroupData", g);
    }

    override void visit(SceneData n)
    {
        writeNode("SceneData", n);
    }

    override void visit(ProjectionGroupData n)
    {
        writeNode("ProjectonGroupData", n);
    }

    override void visit(ObserverData n)
    {
        writeNode("ObserverData", n, (string indent) => writeln(indent, "position=", n.getPosition));
    }

    override void visit(TransformationGroupData n)
    {
        writeNode("TransformationGroupData", n);
    }

    override void visit(ShapeGroupData n)
    {
        writeNode("ShapeGroupData", n);
    }

    override void visit(Behavior n)
    {
        writeNode("Behavior", n);
    }

    private void writeNode(string type, NodeData node, void delegate(string) more = null)
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
        if (auto group = cast(GroupData) node)
        {
            writeln(indent, "#childs=", group.childs.length);
            foreach (child; group.childs)
            {
                child.get.accept(this);
            }
        }
        indent = oldIndent;
    }
}
