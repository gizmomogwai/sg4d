module sg;
import std.string;

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
    CameraProjection camera;
    ParallelProjection parallel;
    this(string _name, CameraProjection camera, ParallelProjection parallel) {
        super(_name);
        this.camera = camera;
        this.parallel = parallel;
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
    Transformation invertAffine() {
        return this;
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
    this(string name, CameraProjection camera, ParallelProjection parallel) {
        super(name, camera, parallel);
    }
    override void accept(Visitor v) {
        v.visit(this);
    }
    Transformation getCameraTransform() {
        if (parallel !is null) {
            return parallel.transformation.invertAffine();
        } else {
            throw new Exception("nyi");
        }
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
class Visitor {
    void visit(Node n) {visitChilds(n);}
    void visit(Root n) {visitChilds(n);}
    void visit(ProjectionNode n) {visitChilds(n);}
    void visit(Observer n) {visitChilds(n);}
    void visit(TransformationNode n) {visitChilds(n);}
    void visit(Shape n) {visitChilds(n);}
    protected void visitChilds(Node n) {
        foreach(child ; n.childs) {child.accept(this);}
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

    override void visit(Node n) {
        foreach (child; n.childs) {
            child.accept(this);
        }
    }
    override void visit(Root n) {
        import bindbc.opengl.bind.dep.dep11;
        glClearColor(0, 0, 1, 1);
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
        if (n.parallel !is null) {
            float f = 1;
            float halfWidth = 100 / 2.0f / f; // TODO
            float halfHeight = 100 / 2.0f / f;
            glOrtho(-halfWidth, halfWidth, -halfHeight, halfHeight, -100, 100); // TODO
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
}
