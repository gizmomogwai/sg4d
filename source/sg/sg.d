// https://www.iquilezles.org/www/index.htm
// http://www.songho.ca/opengl/gl_sphere.html
// https://jsfiddle.net/tLyugeqw/14/
// https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_model_view_projection
// https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/Tutorial/Using_textures_in_WebGL
// http://www.lighthouse3d.com/tutorials/glsl-tutorial/hello-world/
module sg.sg;

import btl.autoptr.common : SharedControlBlock;
import btl.autoptr.intrusive_ptr : IntrusivePtr;
import btl.vector : Vector;
import gamut : Image;
import gl3n.linalg : mat4, vec2, vec3, vec4;
import std.concurrency : Tid, thisTid;
import std.exception : enforce;
import std.string : toStringz, format;
import std.typecons : BitFlags;

version (DEBUG_DESTRUCTORS)
{
    import core.stdc.stdio : printf;
}

alias CustomData = IntrusivePtr!CustomDataData;

class CustomDataData
{
    SharedControlBlock referenceCounter;
    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~CustomDataData\n");
        }
    }
}

alias Node = IntrusivePtr!NodeData;
class NodeData
{
    SharedControlBlock referenceCounter;

    Tid renderThread;
    bool live;

    private string name;
    private immutable(char)* stringZName;
    CustomData customData;

    this(string name)
    {
        this.name = name;
        this.stringZName = name.toStringz;
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~NodeData %s\n", stringZName);
        }
    }

    auto getName()
    {
        return name;
    }

    void ensureRenderThread()
    {
        if (live)
        {
            enforce(thisTid == renderThread, "methods on live object called from wrong thread");
        }
    }

    void accept(Visitor v)
    {
        v.visit(this);
    }

    void setRenderThread(Tid tid)
    {
        (!live).enforce("Node '%s' already attached to a tid".format(name));
        this.renderThread = tid;
        this.live = true;
    }
}

alias Group = IntrusivePtr!GroupData;
class GroupData : NodeData
{
    Vector!Node childs;

    this(string name)
    {
        super(name);
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~GroupData %s\n", stringZName);
        }
    }

    auto getChild(size_t idx)
    {
        ensureRenderThread;
        return childs[idx];
    }

    void addChild(T)(T child)
    {
        ensureRenderThread;

        Node n = child;
        childs.append(n);
        if (live)
        {
            n.get.setRenderThread(renderThread);
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
        (idx < childs.length).enforce("index out of bounds '%s' >= '%s'".format(idx,
                childs.length));
        childs[idx] = n;
        if (live)
        {
            n.get.setRenderThread(renderThread);
        }
    }

    override void setRenderThread(Tid tid)
    {
        super.setRenderThread(tid);
        foreach (child; childs)
        {
            child.get.setRenderThread(tid);
        }
    }
}

alias Scene = IntrusivePtr!SceneData;
class SceneData : GroupData
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

alias ProjectionGroup = IntrusivePtr!ProjectionGroupData;
class ProjectionGroupData : GroupData
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

class IdentityProjection : Projection
{
    this()
    {
        super(1, 2);
    }

    override mat4 getProjectionMatrix(int width, int height)
    {
        return mat4.identity();
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

alias Observer = IntrusivePtr!ObserverData;
class ObserverData : ProjectionGroupData
{
    private vec3 position = vec3(0, 0, 0);

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

alias TransformationGroup = IntrusivePtr!TransformationGroupData;
class TransformationGroupData : GroupData
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

alias Geometry = IntrusivePtr!GeometryData;
class GeometryData : NodeData
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

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~GeometryData %s\n", stringZName);
        }
    }
}

alias TriangleArray = IntrusivePtr!TriangleArrayData;
class TriangleArrayData : GeometryData
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

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~TriangleArray %s\n", stringZName);
        }
    }
}

alias Vertices = IntrusivePtr!VertexData;
class VertexData : NodeData
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

        initialize(components, size);
        data = new float[tupleSize * size];
    }

    this(string name, Components components, uint size, float[] data)
    {
        super(name);

        initialize(components, size);
        enforce(data.length == (tupleSize * size),
                "Expected %s float, but got %s floats".format(tupleSize * size, data.length));
        this.data = data;
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~VertexData %s\n", stringZName);
        }
    }

    private void initialize(Components components, uint)
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

alias IndexedInterleavedTriangleArray = IntrusivePtr!IndexedInterleavedTriangleArrayData;
class IndexedInterleavedTriangleArrayData : GeometryData
{
    Type type;
    Vertices data;
    uint[] indices;

    this(string name, Type type, Vertices data, uint[] indices)
    {
        super(name);
        this.type = type;
        this.data = data;
        this.indices = indices;
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~IndexedInterleavedTriangleArray %s\n", stringZName);
        }
    }
}

alias IndexedInterleavedCube = IntrusivePtr!IndexedInterleavedCubeData;
class IndexedInterleavedCubeData : IndexedInterleavedTriangleArrayData
{
    this(string name, float size)
    {
        auto s = size;
        // dfmt off
        super(name, Type.ARRAY,
              Vertices.make(name,
                            VertexData.Components(
                                VertexData.Component.VERTICES,
                                VertexData.Component.COLORS,
                                VertexData.Component.TEXTURE_COORDINATES,
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
        auto d = data.get;
        // back
        d.setVertex(0, -s, -s, -s);
        d.setVertex(1,  s, -s, -s);
        d.setVertex(2,  s,  s, -s);
        d.setVertex(3, -s,  s, -s);

        // front
        d.setVertex(4, -s, -s,  s);
        d.setVertex(5,  s, -s,  s);
        d.setVertex(6,  s,  s,  s);
        d.setVertex(7, -s,  s,  s);

        d.setColor(0, 0, 0, 0);
        d.setColor(1, 1, 0, 0);
        d.setColor(2, 1, 1, 0);
        d.setColor(3, 0, 1, 0);

        d.setColor(4, 0, 1, 1);
        d.setColor(5, 0, 0, 1);
        d.setColor(6, 1, 0, 1);
        d.setColor(7, 1, 1, 1);

        d.setTextureCoordinate(0, 0, 0);
        d.setTextureCoordinate(1, 1, 0);
        d.setTextureCoordinate(2, 1, 1);
        d.setTextureCoordinate(3, 0, 1);

        d.setTextureCoordinate(4, 0, 0);
        d.setTextureCoordinate(5, 1, 0);
        d.setTextureCoordinate(6, 1, 1);
        d.setTextureCoordinate(7, 0, 1);
        // dfmt on
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~IndexedInterleavedCube %s\n", stringZName);
        }
    }
}

alias Triangle = IntrusivePtr!TriangleArrayData;
class TriangleData : TriangleArrayData
{
    // dfmt off
    this(string name)
    {
        super(name, Type.ARRAY,
              [
                  vec3(-0.5, -0.5, 0.0), vec3(0.5, -0.5, 0.0), vec3(0.0, 0.5, 0.0),
              ],
              [
                  vec4(1.0, 0.0, 0.0, 1.0), vec4(0.0, 1.0, 0.0, 1.0), vec4(0.0, 0.0, 1.0, 1.0),
              ],
              [
                  vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0),
              ],
        );
    }
    // dfmt on
}

alias TriangleArrayCube = IntrusivePtr!TriangleArrayCubeData;
class TriangleArrayCubeData : TriangleArrayData
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

alias Appearance = IntrusivePtr!AppearanceData;
class AppearanceData : NodeData
{
    Vector!Texture textures;
    string shaderBase;

    this(string name, string shaderBase, Vector!Texture textures)
    {
        super(name);
        this.shaderBase = shaderBase;
        this.textures = textures;
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~AppearanceData(%s)\n", stringZName);
        }
    }
}

alias Texture = IntrusivePtr!TextureData;
class TextureData : NodeData
{
    Image* image;
    bool wrapS;
    bool wrapT;
    CustomData customData = null;
    this(Image* image, bool wrapS = false, bool wrapT = false)
    {
        super("texture");
        this.image = image;
        this.wrapS = wrapS;
        this.wrapT = wrapT;
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~TextureData(%s)\n", stringZName);
        }
    }
}

alias ShapeGroup = IntrusivePtr!ShapeGroupData;
class ShapeGroupData : GroupData
{
    Geometry geometry;
    Appearance appearance;
    this(string name, Geometry geometry, Appearance appearance)
    {
        super(name);
        this.geometry = geometry;
        this.appearance = appearance;
    }

    ~this() @nogc
    {
        version (DEBUG_DESTRUCTORS)
        {
            printf("~ShapeGroupData(%s)\n", stringZName);
        }
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

class Behavior : GroupData
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
    void visit(NodeData)
    {
    }

    void visit(GroupData g)
    {
        visitChilds(g);
    }

    void visit(SceneData n)
    {
        visitChilds(n);
    }

    void visit(ProjectionGroupData n)
    {
        visitChilds(n);
    }

    void visit(ObserverData n)
    {
        visitChilds(n);
    }

    void visit(TransformationGroupData n)
    {
        visitChilds(n);
    }

    void visit(ShapeGroupData n)
    {
        visitChilds(n);
    }

    void visit(Behavior n)
    {
        visitChilds(n);
    }

    protected void visitChilds(GroupData n)
    {
        foreach (child; n.childs)
        {
            child.get.accept(this);
        }
    }
}
