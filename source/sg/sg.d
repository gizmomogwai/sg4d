// https://www.iquilezles.org/www/index.htm
// http://www.songho.ca/opengl/gl_sphere.html

module sg.sg;

import automem;
import optional;
import std.concurrency;
import std.exception;
import std.math;
import std.stdio;
import std.string;
import std.typecons : BitFlags;
import sg.window;

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
    /// Can be called if one wants to cleanup manually (and earlier
    /// than the gc)
    void free()
    {
        foreach (child; childs)
        {
            child.free;
        }
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
            enforce(thisTid == renderThread, "methods on live object called from wrong thread");
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

    auto getProjection()
    {
        ensureRenderThread;
        return projection;
    }

    auto setProjection(Projection p)
    {
        ensureRenderThread;
        this.projection = p;
        return this;
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

/++
 + Parallel Projection. Normally the projection is setup in a way that
 + one unit in world space maps to one pixel. This can be changed by
 + zoom. E.g. zoom factor 2 maps one unit in world coordinates to two pixels
 +/
class ParallelProjection : Projection
{
    float zoom;
    this(float near, float far, float zoom)
    {
        super(near, far);
        this.zoom = zoom;
    }

    override mat4 getProjectionMatrix(int width, int height)
    {
        return mat4.orthographic(0, width / zoom, 0, height / zoom, near, far);
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

    auto getPosition()
    {
        ensureRenderThread;
        return position;
    }

    auto setPosition(vec3 position)
    {
        ensureRenderThread;
        this.position = position;
        return this;
    }

    mat4 getCameraTransformation()
    {
        // return mat4.look_at(vec3(0, 1, -10), vec3(0, 0, 0), vec3(0, 1, 0)).inverse;
        return mat4.translation(-position);
        // return mat4.look_at(position, vec3(0, 0, 0), vec3(0, 1, 0));
    }

    enum delta = 10;
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

    auto getTransformation()
    {
        ensureRenderThread;
        return transformation;
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
    Type type;
    vec3[] coordinates;
    vec4[] colors;
    vec2[] textureCoordinates;
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
    Components components;
    float[] data;

    uint tupleSize;
    uint colorsOffset = 0;
    uint textureCoordinatesOffset = 0;
    uint normalsOffset = 0;

    this(string name, Components components, uint size)
    {
        super(name);
        init(components, size);
        data = new float[tupleSize * size];
    }

    this(string name, Components components, uint size, float[] data)
    {
        super(name);
        init(components, size);
        enforce(data.length == (tupleSize * size),
                "Expected %s float, but got %s floats".format(tupleSize * size, data.length));
        this.data = data;
    }

    private void init(Components components, uint size)
    {
        this.components = components;
        uint offset = 0;
        enforce(components.VERTICES, "At least vertices need to be given");

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
        enforce(components.COLORS, "colors not specified");

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
    Type type;
    VertexData data;
    uint[] indices;
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

    override void free()
    {
        textures.free;
    }
}

class CustomData
{
    abstract void free();
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
            customData.free;
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

    override void free()
    {
        appearance.free;
        geometry.free;
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
