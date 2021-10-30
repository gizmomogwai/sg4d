// https://www.iquilezles.org/www/index.htm
// http://www.songho.ca/opengl/gl_sphere.html

module sg;

import automem;
import optional;
import std.concurrency;
import std.math;
import std.stdio;
import std.string;
import std.typecons : BitFlags;
import window;

public import gl3n.linalg;
public import imagefmt;

void checkOglError()
{
    GLenum err = glGetError();
    if (err != GL_NO_ERROR)
    {
        throw new Exception("ogl error %s".format(err));
    }
}

int glGetInt(GLenum what)
{
    int result;
    glGetIntegerv(what, &result);
    checkOglError();
    return result;
}

class Node
{
    protected Optional!Scene scene;
    Node[] childs;
    private string name;
    this(string _name)
    {
        name = _name;
    }

    auto getChild(size_t idx)
    {
        ensureRenderThread;
        return childs[idx];
    }

    auto getName()
    {
        return name;
    }

    void ensureRenderThread()
    {
        oc(scene).ensureRenderThread;
    }

    void accept(Visitor v)
    {
        v.visit(this);
    }

    void addChild(Node n)
    {
        ensureRenderThread;
        childs ~= n;
        if (!scene.empty)
        {
            n.setScene(scene.front);
        }
    }

    size_t childCount()
    {
        ensureRenderThread;
        return childs.length;
    }

    void replaceChild(size_t idx, Node n)
    {
        ensureRenderThread;
        if (idx >= childs.length)
        {
            throw new Exception("index out of bounds");
        }
        childs[idx] = n;
        if (!scene.empty)
        {
            n.setScene(scene.front);
        }
    }

    void setScene(Scene scene)
    {
        if (live)
        {
            throw new Exception("Node '%s' already attached to a scene".format(name));
        }
        this.scene = scene;
        foreach (child; childs)
        {
            child.setScene(scene);
        }
    }

    Node findByName(string name)
    {
        if (name == this.name)
        {
            return this;
        }
        foreach (child; childs)
        {
            auto h = child.findByName(name);
            if (h !is null)
            {
                return h;
            }
        }
        return null;
    }

    bool live()
    {
        return !scene.empty;
    }
}

class Scene : Node
{
    private Optional!Tid renderThread;
    this(string _name)
    {
        super(_name);
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }

    auto bind(Tid tid)
    {
        renderThread = tid;
        setScene(this);
        return this;
    }

    override void ensureRenderThread()
    {
        if (!renderThread.empty)
        {
            import std.concurrency;

            if (thisTid != renderThread)
            {
                throw new Exception("methods on live object called from wrong thread");
            }
        }
    }
}

class ProjectionNode : Node
{
    private Projection projection;
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
    private vec3 position = vec3(0, 0, 10);
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
        ensureRenderThread;
        position.z -= delta;
    }

    void backward()
    {
        ensureRenderThread;
        position.z += delta;
    }

    void strafeLeft()
    {
        ensureRenderThread;
        position.x -= delta;
    }

    void strafeRight()
    {
        ensureRenderThread;
        position.x += delta;
    }
}

class TransformationNode : Node
{
    private mat4 transformation;
    this(string _name, mat4 transformation)
    {
        super(_name);
        this.transformation = transformation;
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }

    auto setTransformation(mat4 transformation)
    {
        ensureRenderThread;
        this.transformation = transformation;
        return this;
    }
}

class Geometry : Node
{
    enum Type
    {
        ARRAY,
        STRIP,
        FAN
    }

    this(string name)
    {
        super(name);
    }
}

class TriangleArray : Geometry
{
    private Type type;
    private vec3[] coordinates;
    private vec4[] colors;
    private vec2[] textureCoordinates;
    // TODO normals
    this(string name, Type type, vec3[] coordinates, vec4[] colors, vec2[] textureCoordinates)
    {
        super(name);
        this.type = type;
        this.coordinates = coordinates;
        this.colors = colors;
        this.textureCoordinates = textureCoordinates;
    }
}

class VertexData : Node
{
    enum Component
    {
        VERTICES = 1,
        COLORS = 2,
        TEXTURE_COORDINATES = 4,
        NORMALS = 8,
    }

    alias Components = BitFlags!Component;
    private Components components;
    private float[] data;

    private uint tupleSize;
    private uint colorsOffset = 0;
    private uint textureCoordinatesOffset = 0;
    private uint normalsOffset = 0;

    this(string name, Components components, uint size)
    {
        super(name);
        this.components = components;
        uint offset = 0;
        if (components.VERTICES == false)
        {
            throw new Exception("At least vertices need to be given");
        }
        tupleSize = 3;
        offset += 3;
        if (components.COLORS)
        {
            tupleSize += 4;
            colorsOffset = offset;
            offset += 4;
        }

        if (components.TEXTURE_COORDINATES)
        {
            tupleSize += 2;
            textureCoordinatesOffset = offset;
            offset += 2;
        }

        if (components.NORMALS)
        {
            tupleSize += 3;
            normalsOffset = offset;
            offset += 3;
        }
        data = new float[tupleSize * size];
    }

    void setVertex(uint idx, float x, float y, float z)
    {
        ensureRenderThread;
        data[idx * tupleSize + 0] = x;
        data[idx * tupleSize + 1] = y;
        data[idx * tupleSize + 2] = z;
    }

    void setColor(uint idx, float r, float g, float b, float a = 1.0f)
    {
        if (!components.COLORS)
        {
            throw new Exception("colors not specified");
        }
        ensureRenderThread;
        data[idx * tupleSize + colorsOffset + 0] = r;
        data[idx * tupleSize + colorsOffset + 1] = g;
        data[idx * tupleSize + colorsOffset + 2] = b;
        data[idx * tupleSize + colorsOffset + 3] = a;
    }

    void setTextureCoordinate(uint idx, float u, float v)
    {
        ensureRenderThread;
        data[idx * tupleSize + textureCoordinatesOffset + 0] = u;
        data[idx * tupleSize + textureCoordinatesOffset + 1] = v;
    }
}

class IndexedInterleavedTriangleArray : Geometry
{
    private Type type;
    private VertexData data;
    private uint[] indices;
    this(string name, Type type, VertexData data, uint[] indices)
    {
        super(name);
        this.type = type;
        this.data = data;
        this.indices = indices;
    }
}

class IndexedInterleavedCube : IndexedInterleavedTriangleArray
{
    this(string name, float size)
    {
        auto s = size;
        // dfmt off
        super(name, Type.ARRAY,
              new VertexData(name,
                  VertexData.Components(
                      VertexData.Component.VERTICES,
                      VertexData.Component.TEXTURE_COORDINATES
                  ), 8),
              [
                  // back
                  0, 2, 1, 0, 3, 2,
                  // front
                  4, 5, 6, 4, 6, 7,
                  // left
                  0, 4, 7, 0, 7, 3,
                  // right
                  5, 1, 2, 5, 2, 6,
                  // top
                  7, 6, 2, 7, 2, 3,
                  // bottom
                  4, 0, 1, 4, 1, 5,
              ]);
        // back
        data.setVertex(0, -s, -s, -s);
        data.setVertex(1,  s, -s, -s);
        data.setVertex(2,  s,  s, -s);
        data.setVertex(3, -s,  s, -s);

        // front
        data.setVertex(4, -s, -s,  s);
        data.setVertex(5,  s, -s,  s);
        data.setVertex(6,  s,  s,  s);
        data.setVertex(7, -s,  s,  s);

        // data.setColor(0, 0, 0, 0);
        // data.setColor(1, 1, 0, 0);
        // data.setColor(2, 1, 1, 0);
        // data.setColor(3, 0, 1, 0);
        // data.setColor(4, 0, 1, 1);
        // data.setColor(5, 0, 0, 1);
        // data.setColor(6, 1, 0, 1);
        // data.setColor(7, 1, 1, 1);

        data.setTextureCoordinate(0, 0, 0);
        data.setTextureCoordinate(1, 1, 0);
        data.setTextureCoordinate(2, 1, 1);
        data.setTextureCoordinate(3, 0, 1);

        data.setTextureCoordinate(4, 0, 0);
        data.setTextureCoordinate(5, 1, 0);
        data.setTextureCoordinate(6, 1, 1);
        data.setTextureCoordinate(7, 0, 1);
        // dfmt on
    }
}

class TriangleArrayCube : TriangleArray
{
    this(string name, float size)
    {
        auto s = size;
        // dfmt off
        super(name, Type.ARRAY, [
                  // back
                  vec3(-s, -s, -s),
                  vec3(-s, s, -s),
                  vec3(s, s, -s),

                  vec3(-s, -s, -s),
                  vec3(s, s, -s),
                  vec3(s, -s, -s),

                  // front
                  vec3(-s, -s, s),
                  vec3(s, -s, s),
                  vec3(s, s, s),

                  vec3(-s, -s, s),
                  vec3(s, s, s),
                  vec3(-s, s, s),

                  // top
                  vec3(-s, s, -s),
                  vec3(-s, s, s),
                  vec3(s, s, s),

                  vec3(-s, s,-s),
                  vec3(s, s, s),
                  vec3(s, s, -s),

                  // bottom
                  vec3(-s, -s, -s),
                  vec3(s, -s, -s),
                  vec3(s, -s, s),

                  vec3(-s, -s, -s),
                  vec3(s, -s, s),
                  vec3(-s, -s, s),

                  // left
                  vec3(-s, -s, -s),
                  vec3(-s, -s, s),
                  vec3(-s, s, s),

                  vec3(-s, -s, -s),
                  vec3(-s, s, s),
                  vec3(-s, s, -s),

                  // right
                  vec3(s, -s, -s),
                  vec3(s, s, -s),
                  vec3(s, s, s),

                  vec3(s, -s, -s),
                  vec3(s, s, s),
                  vec3(s, -s, s),
              ], [
                  // back
                  vec4(1, 0, 0, 1),
                  vec4(1, 0, 0, 1),
                  vec4(1, 0, 0, 1),

                  vec4(1, 0, 0, 1),
                  vec4(1, 0, 0, 1),
                  vec4(1, 0, 0, 1),

                  // front
                  vec4(1, 1, 0, 1),
                  vec4(1, 1, 0, 1),
                  vec4(1, 1, 0, 1),

                  vec4(1, 1, 0, 1),
                  vec4(1, 1, 0, 1),
                  vec4(1, 1, 0, 1),

                  // top
                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),

                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),

                  // bottom
                  vec4(0, 1, 0, 1),
                  vec4(0, 1, 0, 1),
                  vec4(0, 1, 0, 1),

                  vec4(0, 1, 0, 1),
                  vec4(0, 1, 0, 1),
                  vec4(0, 1, 0, 1),

                  // left
                  vec4(0, 1, 1, 1),
                  vec4(0, 1, 1, 1),
                  vec4(0, 1, 1, 1),

                  vec4(0, 1, 1, 1),
                  vec4(0, 1, 1, 1),
                  vec4(0, 1, 1, 1),

                  // right
                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),

                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),
                  vec4(1, 0, 1, 1),
              ], [
                  // back
                  vec2(0, 0),
                  vec2(1, 0),
                  vec2(1, 1),

                  vec2(0, 0),
                  vec2(1, 1),
                  vec2(0, 1),

                  // front
                  vec2(0, 0),
                  vec2(1, 0),
                  vec2(1, 1),

                  vec2(0, 0),
                  vec2(1, 1),
                  vec2(0, 1),

                  // bottom
                  vec2(0, 0),
                  vec2(1, 0),
                  vec2(1, 1),

                  vec2(0, 0),
                  vec2(1, 1),
                  vec2(0, 1),

                  // top
                  vec2(0, 0),
                  vec2(1, 0),
                  vec2(1, 1),

                  vec2(0, 0),
                  vec2(1, 1),
                  vec2(0, 1),

                  // left
                  vec2(0, 0),
                  vec2(1, 0),
                  vec2(1, 1),

                  vec2(0, 0),
                  vec2(1, 1),
                  vec2(0, 1),

                  // right
                  vec2(0, 0),
                  vec2(1, 0),
                  vec2(1, 1),

                  vec2(0, 0),
                  vec2(1, 1),
                  vec2(0, 1),
              ]);
        // dfmt on
    }
}

alias Textures = Vector!Texture;
class Appearance : Node
{
    Textures textures;
    this(Textures textures)
    {
        super("app");
        this.textures = textures;
    }

    void setTexture(size_t index, Texture t)
    {
        this.textures[index] = t;
    }
}

class CustomData
{
    abstract void cleanup();
}

class _Texture
{
    IFImage image;
    bool wrapS;
    bool wrapT;
    CustomData customData = null;
    this(IFImage image, bool wrapS = false, bool wrapT = false)
    {
        this.image = image;
        this.wrapS = wrapS;
        this.wrapT = wrapT;
    }

    ~this()
    {
        if (customData)
        {
            customData.cleanup;
            customData = null;
        }
    }
}

alias Texture = RefCounted!(_Texture);

class Shape : Node
{
    Geometry geometry;
    Appearance appearance;
    this(string name, Geometry geometry, Appearance appearance)
    {
        super(name);
        this.geometry = geometry;
        this.appearance = appearance;
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }

    auto getAppearance()
    {
        ensureRenderThread;
        return appearance;
    }

    auto getGeometry()
    {
        ensureRenderThread;
        return geometry;
    }

    void setAppearance(Appearance appearance)
    {
        ensureRenderThread;
        this.appearance = appearance;
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

    void visit(Scene n)
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
        writeln(indent, type);
        const oldIndent = indent;
        indent ~= "  ";
        writeln(indent, "name=", node.name);
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

/++
 + https://austinmorlan.com/posts/opengl_matrices/
 + gl3n stores row major -> all matrices need to be transposed either
 + manually for opengl2 or with setting GL_TRUE when passing to a shader
 +/
class OGL2RenderVisitor : Visitor
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

    override void visit(Scene n)
    {
        n.ensureRenderThread;

        glClearColor(0, 0, 0, 1);
        glColor3f(1, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glFrontFace(GL_CCW);
        glCullFace(GL_BACK);
        glEnable(GL_CULL_FACE);
        // glDisable(GL_CULL_FACE);
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

    class TextureName : CustomData
    {
        Tid renderThread;
        GLuint textureName;
        this(Tid renderThread, GLuint textureName)
        {
            this.renderThread = renderThread;
            this.textureName = textureName;
        }

        override void cleanup()
        {
            renderThread.send(cast(shared)() {
                glDeleteTextures(1, &textureName);
            });
        }
    }

    private TextureName createAndLoadTexture(Texture texture)
    {
        auto image = texture.image;
        GLuint textureName;
        glGenTextures(1, &textureName);
        checkOglError();
        glBindTexture(GL_TEXTURE_2D, textureName);
        checkOglError();
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        checkOglError();
        glTexImage2D(GL_TEXTURE_2D, // target
                0, // level
                GL_RGB, // internalFormat
                image.w, // width
                image.h, // height
                0, // border
                GL_RGB, // format
                GL_UNSIGNED_BYTE, // type
                image.buf8.ptr // pixels
                );
        checkOglError();
        glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
        checkOglError();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        checkOglError();
        auto result = new TextureName(thisTid, textureName);
        texture.customData = result;
        return result;
    }

    private void activate(Texture texture)
    {
        glEnable(GL_TEXTURE_2D);
        checkOglError();

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, texture.wrapS ? GL_REPEAT : GL_CLAMP);
        checkOglError();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, texture.wrapT ? GL_REPEAT : GL_CLAMP);
        checkOglError();
        // dfmt off
        auto textureName = cast(TextureName) texture.customData is null ?
            createAndLoadTexture(texture)
            : cast(TextureName) texture.customData;
        // dfmt on
        glBindTexture(GL_TEXTURE_2D, textureName.textureName);
        checkOglError();
    }

    override void visit(Shape n)
    {
        if (auto appearance = n.appearance)
        {
            activate(appearance.textures[0]);
        }

        /+ immediate mode
        if (auto triangleArray = cast(TriangleArray) n.geometry)
        {
            glBegin(GL_TRIANGLES);
            for (int i = 0; i < triangleArray.coordinates.length; ++i)
            {
                auto color = triangleArray.colors[i];
                auto coordinates = triangleArray.coordinates[i];

                if (triangleArray.textureCoordinates.length > i)
                {
                    auto textureCoordinates = triangleArray.textureCoordinates[i];
                    glTexCoord2f(textureCoordinates.x, textureCoordinates.y);
                }
                glColor3f(color.x, color.y, color.z);
                glVertex3f(coordinates.x, coordinates.y, coordinates.z);
            }
            glEnd();
        }
        +/
        if (auto g = cast(TriangleArray) n.geometry)
        {
            glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
            {
                glEnableClientState(GL_VERTEX_ARRAY);
                glVertexPointer(3, GL_FLOAT, 0, g.coordinates.ptr);

                glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                glTexCoordPointer(2, GL_FLOAT, 0, g.textureCoordinates.ptr);

                glEnableClientState(GL_COLOR_ARRAY);
                glColorPointer(4, GL_FLOAT, 0, g.colors.ptr);

                glDrawArrays(GL_TRIANGLES, 0, cast(int) g.coordinates.length);
            }
            glPopClientAttrib();
        }

        if (auto g = cast(IndexedInterleavedTriangleArray) n.geometry)
        {
            int stride = cast(int)(g.data.tupleSize * float.sizeof);
            glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
            {
                glEnableClientState(GL_VERTEX_ARRAY);
                glVertexPointer(3, GL_FLOAT, stride, g.data.data.ptr);

                glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                glTexCoordPointer(2, GL_FLOAT, stride,
                        g.data.data.ptr + g.data.textureCoordinatesOffset);

                if (g.data.components.COLORS)
                {
                    glEnableClientState(GL_COLOR_ARRAY);
                    glColorPointer(4, GL_FLOAT, stride, g.data.data.ptr + g.data.colorsOffset);
                }
                glDrawElements(GL_TRIANGLES, cast(int) g.indices.length,
                        GL_UNSIGNED_INT, g.indices.ptr);
            }
            glPopClientAttrib();
        }
    }

    override void visit(Behavior n)
    {
    }
}
