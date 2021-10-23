module sg;
import std.stdio;
import std.string;
import std.math;
import window;

public import gl3n.linalg;

class Node
{
    Node[] childs;
    private string name;
    this(string _name)
    {
        name = _name;
    }

    void accept(Visitor v)
    {
        v.visit(this);
    }

    void addChild(Node n)
    {
        childs ~= n;
    }
};

class Root : Node
{
    this(string _name)
    {
        super(_name);
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }
}

class ProjectionNode : Node
{
    Projection projection;
    this(string _name, Projection projection)
    {
        super(_name);
        this.projection = projection;
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }
}

abstract class Projection
{
    float near;
    float far;
    this(float near, float far)
    {
        this.near = near;
        this.far = far;
    }

    abstract mat4 getProjectionMatrix(int width, int height);
}

class ParallelProjection : Projection
{
    this(float near, float far)
    {
        super(near, far);
    }

    override mat4 getProjectionMatrix(int width, int height)
    {
        return mat4.orthographic(-width / 2, width / 2, -height / 2, height / 2, near, far);
    }
}

class CameraProjection : Projection
{
    this(float near, float far)
    {
        super(near, far);
    }

    override mat4 getProjectionMatrix(int width, int height)
    {
        return mat4.perspective(width, height, 60, near, far);
    }
}

class Observer : ProjectionNode
{
    vec3 position = vec3(0, 0, 10);
    this(string name, Projection projection)
    {
        super(name, projection);
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }

    mat4 getCameraTransformation()
    {
        // return mat4.look_at(vec3(0, 1, -10), vec3(0, 0, 0), vec3(0, 1, 0)).inverse;
        return mat4.translation(-position);
        // return mat4.look_at(position, vec3(0, 0, 0), vec3(0, 1, 0));
    }

    enum delta = 1;
    void forward()
    {
        position.z -= delta;
    }

    void backward()
    {
        position.z += delta;
    }

    void strafeLeft()
    {
        position.x -= delta;
    }

    void strafeRight()
    {
        position.x += delta;
    }
}

class TransformationNode : Node
{
    mat4 transformation;
    this(string _name, mat4 transformation)
    {
        super(_name);
        this.transformation = transformation;
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }
}

class Shape : Node
{
    this(string _name)
    {
        super(_name);
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }
}

class Behavior : Node
{
    void delegate() behavior;
    this(string name, void delegate() b)
    {
        super(name);
        this.behavior = b;
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }

    void run()
    {
        behavior();
    }
}

class Visitor
{
    void visit(Node n)
    {
        visitChilds(n);
    }

    void visit(Root n)
    {
        visitChilds(n);
    }

    void visit(ProjectionNode n)
    {
        visitChilds(n);
    }

    void visit(Observer n)
    {
        visitChilds(n);
    }

    void visit(TransformationNode n)
    {
        visitChilds(n);
    }

    void visit(Shape n)
    {
        visitChilds(n);
    }

    void visit(Behavior n)
    {
        visitChilds(n);
    }

    protected void visitChilds(Node n)
    {
        foreach (child; n.childs)
        {
            child.accept(this);
        }
    }
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

    override void visit(Root n)
    {
        writeNode("Root", n);
    }

    override void visit(ProjectionNode n)
    {
        writeNode("ProjectonNode", n);
    }

    override void visit(Observer n)
    {
        writeNode("Observer", n, (string indent) => writeln(indent, "position=", n.position));
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
        writeln(indent, type, " {");
        auto oldIndent = indent;
        indent ~= "  ";
        writeln(indent, "name=", node.name);
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
        writeln(indent, "}");
    }
}

/++
 + https://austinmorlan.com/posts/opengl_matrices/
 + gl3n stores row major -> all matrices need to be transposed either
 + manually for opengl2 or with setting GL_TRUE when passing to a shader
 +/
class OGLRenderVisitor : Visitor
{
    import bindbc.opengl;

    Window window;
    this(Window window)
    {
        this.window = window;
    }

    override void visit(Node n)
    {
        foreach (child; n.childs)
        {
            child.accept(this);
        }
    }

    override void visit(Root n)
    {
        glClearColor(0, 0, 0, 1);
        glColor3f(1, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glFrontFace(GL_CCW);
        glCullFace(GL_BACK);
        glEnable(GL_CULL_FACE);
        //glDisable(GL_CULL_FACE);
        glDisable(GL_DITHER);
        glDisable(GL_DEPTH_TEST);
        //  glDepthFunc(GL_LESS);
        glDisable(GL_LIGHTING);
        //      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
        glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
        glViewport(0, 0, window.getWidth, window.getHeight);

        visit(cast(Node)(n));
    }

    override void visit(ProjectionNode n)
    {
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glMultMatrixf(n.projection.getProjectionMatrix(window.getWidth,
                window.getHeight).transposed.value_ptr);

        glMatrixMode(GL_MODELVIEW);
        visit(cast(Node) n);
    }

    override void visit(Observer n)
    {
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glMultMatrixf(n.getCameraTransformation.transposed.value_ptr);

        visit(cast(ProjectionNode) n);
    }

    override void visit(TransformationNode n)
    {
        glPushMatrix();
        glMultMatrixf(n.transformation.transposed.value_ptr);
        foreach (child; n.childs)
        {
            child.accept(this);
        }
        glPopMatrix();
    }

    override void visit(Shape n)
    {
        glBegin(GL_QUADS);
        {
            enum s = 1;
            // back
            glColor3f(1, 0, 0);
            glVertex3f(-s, -s, -s);
            glVertex3f(-s, s, -s);
            glVertex3f(s, s, -s);
            glVertex3f(s, -s, -s);

            // front
            glColor3f(0, 1, 0);
            glVertex3f(-s, -s, s);
            glVertex3f(s, -s, s);
            glVertex3f(s, s, s);
            glVertex3f(-s, s, s);

            // top
            glColor3f(0, 0, 1);
            glVertex3f(-s, s, -s);
            glVertex3f(-s, s, s);
            glVertex3f(s, s, s);
            glVertex3f(s, s, -s);

            // bottom
            glColor3f(1, 1, 0);
            glVertex3f(-s, -s, -s);
            glVertex3f(s, -s, -s);
            glVertex3f(s, -s, s);
            glVertex3f(-s, -s, s);

            // left
            glColor3f(1, 0, 1);
            glVertex3f(-s, -s, -s);
            glVertex3f(-s, -s, s);
            glVertex3f(-s, s, s);
            glVertex3f(-s, s, -s);

            // right
            glColor3f(0, 1, 1);
            glVertex3f(s, -s, -s);
            glVertex3f(s, s, -s);
            glVertex3f(s, s, s);
            glVertex3f(s, -s, s);
        }
        glEnd();
    }

    override void visit(Behavior n)
    {
    }
}
