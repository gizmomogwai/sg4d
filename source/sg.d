module sg;
import std.string;
import std.math;
import window;

public import gl3n.linalg;

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

class Projection {
    mat4 transformation;
    this(mat4 transformation) {
        this.transformation = transformation;
    }
}
class ParallelProjection : Projection {
    this(float near, float far) {
        super(mat4.identity());
    }
}
class CameraProjection : Projection {
    this() {
        super(mat4.identity());
    }
}
class Observer : ProjectionNode {
    this(string name, Projection projection) {
        super(name, projection);
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
    mat4 getCameraTransform() {
        return projection.transformation.inverse();
    }
    void strafeLeft() {
    }
    void strafeRight() {
    }
}
class TransformationNode : Node {
    mat4 transformation;
    this(string _name, mat4 transformation) {
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
        //glEnable(GL_CULL_FACE);
        glDisable(GL_CULL_FACE);
        glDisable(GL_DITHER);
        glDisable(GL_DEPTH_TEST);
        //  glDepthFunc(GL_LESS);
        glDisable(GL_LIGHTING);
        glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
        glViewport(0, 0, window.getWidth, window.getHeight);
        visit(cast(Node)(n));
    }

    override void visit(ProjectionNode n) {
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        if (auto parallel = cast(ParallelProjection)(n.projection)) {
            float f = 1;
            float halfWidth =  window.getWidth / 2.0f / f;
            float halfHeight = window.getHeight / 2.0f / f;
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
        glMultMatrixf(cast(const(GLfloat*))(cameraTransform.value_ptr));

        visit(cast(ProjectionNode)n);
    }
    override void visit(TransformationNode n) {
        glPushMatrix();
        glMultMatrixf(cast(const(GLfloat*))(n.transformation.value_ptr));
        foreach (child; n.childs) {
            child.accept(this);
        }
        glPopMatrix();
    }
    override void visit(Shape n) {
        glBegin(GL_TRIANGLES); {
            int size = 100;
            glColor3f(1, 0, 0);
            glVertex3f(0, 0, 0);

            glColor3f(0, 1, 0);
            glVertex3f(size, 0, 0);

            glColor3f(0, 0, 1);
            glVertex3f(size/2, size, 0);
        } glEnd();
    }
    override void visit(Behavior n) {
    }
}
