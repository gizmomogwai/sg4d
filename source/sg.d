module sg;
import std.string;
import std.math;
import window;
class Node {
    Node[] childs;
    private string name;
    this(string _name) {
        name = _name;
    }
    void accept(Visitor v) {
        v.visit(this);
    }
    void addChild(Node n) {
        childs ~= n;
    }
};

class Root : Node {
    this(string _name) {
        super(_name);
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
}
class ProjectionNode : Node {
    Projection projection;
    this(string _name, Projection projection) {
        super(_name);
        this.projection = projection;
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
}
/++
 0 4  8 12
 1 5  9 13
 2 6 10 14
 3 7 11 15
 +/
class Transformation {
    float[16] m;
    this() {
        setId();
    }
    void setId() {
        m[ 0] = 1;
        m[ 1] = 0;
        m[ 2] = 0;
        m[ 3] = 0;
        m[ 4] = 0;
        m[ 5] = 1;
        m[ 6] = 0;
        m[ 7] = 0;
        m[ 8] = 0;
        m[ 9] = 0;
        m[10] = 1;
        m[11] = 0;
        m[12] = 0;
        m[13] = 0;
        m[14] = 0;
        m[15] = 1;
    }
    void rotX(float rad) {
        float s = sin(rad);
        float c = cos(rad);

        m[ 0] = 1;
        m[ 1] = 0;
        m[ 2] = 0;
        m[ 4] = 0;
        m[ 5] = c;
        m[ 6] = -s;
        m[ 8] = 0;
        m[ 9] = s;
        m[10] = c;
    }
    void rotY(float rad) {
        float s = sin(rad);
        float c = cos(rad);

        m[ 0] = c;
        m[ 1] = 0;
        m[ 2] = -s;
        m[ 4] = 0;
        m[ 5] = 1;
        m[ 6] = 0;
        m[ 8] = s;
        m[ 9] = 0;
        m[10] = c;
    }
    void rotZ(float rad) {
        float s = sin(rad);
        float c = cos(rad);

        m[ 0] = c;
        m[ 1] = -s;
        m[ 2] = 0;
        m[ 4] = s;
        m[ 5] = c;
        m[ 6] = 0;
        m[ 8] = 0;
        m[ 9] = 0;
        m[10] = 1;
    }
    float getData(int col, int row) {
        return m[col*4+row];
    }
    Transformation invertAffine() {
        Transformation res = new Transformation();
        res.m[ 0] = m[ 0];
        res.m[ 5] = m[ 5];
        res.m[10] = m[10];
        res.m[15] = m[15];

        res.m[ 1] = m[ 4];
        res.m[ 4] = m[ 1];

        res.m[ 2] = m[ 8];
        res.m[ 8] = m[ 2];

        res.m[ 6] = m[ 9];
        res.m[ 9] = m[ 6];

        res.m[12] = -m[12];
        res.m[13] = -m[13];
        res.m[14] = -m[14];

        res.m[ 3] = 0;
        res.m[ 7] = 0;
        res.m[11] = 0;

        return res;
    }
    void setTranslation(float x, float y, float z) {
        m[13] = x;
        m[14] = x;
        m[15] = x;
    }
    override string toString() {
        return "Transformation\n%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\n".format(
            m[ 0], m[ 4], m[ 8], m[12],
            m[ 1], m[ 5], m[ 9], m[13],
            m[ 2], m[ 6], m[10], m[14],
            m[ 3], m[ 7], m[11], m[15],
        );
    }
}

class Projection {
    Transformation transformation;
    this(Transformation transformation) {
        this.transformation = transformation;
    }
}
class ParallelProjection : Projection {
    this() {
        super(new Transformation());
    }
}
class CameraProjection : Projection {
    this() {
        super(new Transformation());
    }
}
class Observer : ProjectionNode {
    this(string name, Projection projection) {
        super(name, projection);
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
    Transformation getCameraTransform() {
        return projection.transformation.invertAffine();
    }
    void left() {
        projection.transformation.m[12] -= .1;
    }
    void right() {
        projection.transformation.m[12] += .1;
    }
}
class TransformationNode : Node {
    Transformation transformation;
    this(string _name, Transformation transformation) {
        super(_name);
        this.transformation = transformation;
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
}
class Shape : Node {
    this(string _name) {
        super(_name);
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
}
class Behavior : Node {
    void delegate() behavior;
    this(string name, void delegate() b) {
        super(name);
        this.behavior = b;
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
    void run() {
        behavior();
    }
}
class Visitor {
    void visit(Node n) {visitChilds(n);}
    void visit(Root n) {visitChilds(n);}
    void visit(ProjectionNode n) {visitChilds(n);}
    void visit(Observer n) {visitChilds(n);}
    void visit(TransformationNode n) {visitChilds(n);}
    void visit(Shape n) {visitChilds(n);}
    void visit(Behavior n) {visitChilds(n);}
    protected void visitChilds(Node n) {
        foreach(child ; n.childs) {child.accept(this);}
    }
}
class BehaviorVisitor : Visitor {
    alias visit = Visitor.visit;
    override void visit(Behavior n) {
        n.run();
        foreach (child; n.childs) {
            child.accept(this);
        }
    }
}

class PrintVisitor : Visitor {
    import std.stdio;
    string indent = "";
    override void visit(Node node) {
        writeNode("Node", node);
    }
    override void visit(Root n) {
        writeNode("Root", n);
    }
    override void visit(ProjectionNode n) {
        writeNode("ProjectonNode", n);
    }
    override void visit(Observer n) {
        writeNode("Observer", n);
    }
    override void visit(TransformationNode n) {
        writeNode("TransformationNode", n);
    }
    override void visit(Shape n) {
        writeNode("Shape", n);
    }
    override void visit(Behavior n) {
        writeNode("Behavior", n);
    }
    private void writeNode(string type, Node node) {
        writeln(indent, type, " {");
        auto oldIndent = indent;
        indent ~= "  ";
        writeln(indent, "name=", node.name);
        writeln(indent, "#childs=", node.childs.length);
        foreach (child; node.childs) {
            child.accept(this);
        }
        indent = oldIndent;
        writeln(indent, "}");
    }
}

class OGLRenderVisitor : Visitor {
    import bindbc.opengl;
    Window window;
    this(Window window) {
        this.window = window;
    }
    override void visit(Node n) {
        foreach (child; n.childs) {
            child.accept(this);
        }
    }
    override void visit(Root n) {
        glClearColor(0, 0, 0, 1);
        glColor3f(1, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glFrontFace(GL_CCW);
        glCullFace(GL_BACK);
        glEnable(GL_CULL_FACE);
        glDisable(GL_DITHER);
        glDisable(GL_DEPTH_TEST);
        //  glDepthFunc(GL_LESS);
        glDisable(GL_LIGHTING);
        glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);

        visit(cast(Node)(n));
    }

    override void visit(ProjectionNode n) {
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        if (auto parallel = cast(ParallelProjection)(n.projection)) {
            float f = 1;
            float halfWidth =  window.width / 2.0f / f;
            float halfHeight = window.height / 2.0f / f;
            glOrtho(-halfWidth, halfWidth, -halfHeight, halfHeight, -100, 100); // TODO
        } else if (auto camera = cast(CameraProjection)(n.projection)) {
        } else {
            throw new Exception("nyi");
        }
        glMatrixMode(GL_MODELVIEW);

        visit(cast(Node)n);
    }
    override void visit(Observer n) {
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        auto cameraTransform = n.getCameraTransform();
        glMultMatrixf(cast(const(GLfloat*))(cameraTransform.m));

        visit(cast(ProjectionNode)n);
    }
    override void visit(TransformationNode n) {
        glPushMatrix();
        glMultMatrixf(cast(const(GLfloat*))(n.transformation.m));
        foreach (child; n.childs) {
            child.accept(this);
        }
        glPopMatrix();
    }
    override void visit(Shape n) {
        glBegin(GL_TRIANGLES); {
            glColor3f(1, 0, 0);
            glVertex3f(0, 0, 0);

            glColor3f(0, 1, 0);
            glVertex3f(10, 0, 0);

            glColor3f(0, 0, 1);
            glVertex3f(5, 10, 0);
        } glEnd();
    }
    override void visit(Behavior n) {
    }
}
