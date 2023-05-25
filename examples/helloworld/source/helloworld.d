import core.thread;
import sg.window;
import sg;
import std;

import btl.autoptr.common;
import btl.autoptr.intrusive_ptr;
import btl.vector;

class Buffer(T)
{
    T[] data;
    public size_t lastWriteIndex;
    size_t writeIndex;
    public size_t readIndex;
    size_t fillCount;
    this(int capacity)
    {
        data.length = capacity;
        lastWriteIndex = 0;
        writeIndex = 0;
        readIndex = 0;
        fillCount = 0;
    }

    size_t capacity()
    {
        return data.length;
    }

    auto push(T t)
    {
        data[writeIndex] = t;
        if (full())
        {
            lastWriteIndex = writeIndex;
            writeIndex = increment(writeIndex, data.length);
            readIndex = increment(readIndex, data.length);
        }
        else
        {
            lastWriteIndex = writeIndex;
            writeIndex = increment(writeIndex, data.length);
            ++fillCount;
        }
        return this;
    }

    bool full()
    {
        return fillCount == data.length;
    }

    auto oldest()
    {
        return data[readIndex];
    }

    auto newest()
    {
        return data[lastWriteIndex];
    }

    private auto increment(size_t index, size_t capacity)
    {
        return (index + 1) % capacity;
    }
}

class Stats
{
    auto buffer = new Buffer!(SysTime)(140);
    public int count = 0;
    void tick()
    {
        buffer.push(Clock.currTime());
        count++;
    }

    override string toString()
    {
        auto delta = buffer.newest - buffer.oldest;
        return "%s %s delta: %s count: %s one-frame: %s %s %s".format(buffer.oldest, buffer.newest, delta,
                buffer.capacity, delta / buffer.capacity, buffer.readIndex, buffer.lastWriteIndex);
    }
}

auto triangle(float rotationSpeed)
{
    /*
    auto rotation = TransformationGroup.make("rotation", mat4.identity);
    auto appearance = Appearance.make("filename", "position_color_texture", Vector!Texture.build(Texture.make()));
    auto shape = ShapeGroup.make("triangle", new Triangle("tri"), appearance);
    rotation.get.addChild(shape);
    float rot = 0.5;
    rotation.get.addChild(IntrusivePtr!Behavior.make("rotY-%s".format(rotationSpeed), {
            //auto xScale = (sin(rot)+1)*0.5+0.2;
            //auto yScale = (sin(rot)+1)*0.5+0.2;
            rotation.get.setTransformation(mat4.rotation(rot, vec3(1, 1, 1))); //.scale(xScale, yScale, 1));
            rot = cast(float)(rot + rotationSpeed);
        }));
    return rotation;
    */
}

auto cube(string name, Texture texture, float x, float y, float z, float rotationSpeed, bool indexed)
{
    auto translation = TransformationGroup.make("translation-" ~ name, mat4.translation(x, y, z));
    auto rotation = TransformationGroup.make("rotation-" ~ name, mat4.identity());
    // dfmt off
    auto textures = Vector!(Texture).build(texture);
    Geometry g = IndexedInterleavedCube.make("cube(size=1)", 100);
    auto shape =
        ShapeGroup.make("cube-" ~ name,
                        //indexed ?
                        g,
                        //: TriangleArrayCube.make("cube", 100),
                        Appearance.make("blub", "position_texture", textures)
        );
    // dfmt on
    rotation.get.addChild(shape);
    float rot = 0.5;
    // dfmt off
    rotation.get.addChild(
        IntrusivePtr!Behavior.make("rotY-" ~ name,
            {
                auto xScale = (sin(rot)+1)*0.5+0.2;
                auto yScale = (sin(rot)+1)*0.5+0.2;
                rotation.get.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)).scale(xScale, yScale, 1));
                rot = cast(float)(rot + rotationSpeed);
            }
        )
    );
    // dfmt on
    translation.get.addChild(rotation);
    return translation;
}

Projection getProjection(string[] args)
{
    if (args.length > 1)
    {
        switch (args[1])
        {
        case "parallel":
            return new ParallelProjection(1, 1000, 1);
        case "camera":
            return new CameraProjection(1, 1000);
        case "id":
        default:
            return new IdentityProjection();
        }
    }
    return new IdentityProjection();
}

auto loadImage()
{
    auto result = read_image("image1.jpg");
    (!result.e).enforce("Cannot load image1.jpg");
    return result;
}

void main(string[] args)
{
    auto scene = Scene.make("scene");
    auto projection = getProjection(args);
    auto observer = Observer.make("observer", projection);
    scene.get.addChild(observer);
    scope window = new Window(scene, 800, 600, (Window w, int key, int, int action, int) {
        auto o = observer.get;
        auto oldPosition = o.getPosition;
        if (key == 'W')
        {
            o.setPosition(vec3(oldPosition.xy, o.getPosition.z - 1));
        }
        if (key == 'S')
        {
            o.setPosition(vec3(oldPosition.xy, o.getPosition.z + 1));
        }
        if (key == 'A')
        {
            o.setPosition(vec3(oldPosition.x - 1, oldPosition.yz));
        }
        if (key == 'D')
        {
            o.setPosition(vec3(oldPosition.x + 1, oldPosition.yz));
        }
    });

    if (cast(ParallelProjection) projection)
    {
        observer.get.setPosition(vec3(-window.getWidth() / 2, -window.getHeight() / 2, 300));
        auto image1 = loadImage();
        observer.get.addChild(cube("cube", Texture.make(image1), 0, 0, 0, 0.001, true));
        observer.get.addChild(cube("cube", Texture.make(image1), -200, 0, 0, 0.0005, false));
    }
    else if (cast(CameraProjection) projection)
    {
        observer.get.setPosition(vec3(0, 0, 300));
        auto image1 = loadImage();
        for (int i = 0; i < 1; ++i)
        {
            observer.get.addChild(cube("cube %s-true".format(i),
                    Texture.make(image1), 0, 0, 0, 0.001, true));
            observer.get.addChild(cube("cube %s-false".format(i),
                    Texture.make(image1), -200, 0, 0, 0.0005, false));
        }
        writeln("observer before gc usecount: ", observer.useCount);
        import core.memory;

        GC.collect();
        writeln("observer after gc usecount: ", observer.useCount);
    }
    else if (cast(IdentityProjection) projection)
    {
        //observer.get.addChild(triangle(0.001));
    }

    scene.get.accept(new PrintVisitor);

    scope renderVisitor = new RenderVisitor(window);
    auto visitors = [renderVisitor, new BehaviorVisitor(),];
    auto stats = new Stats();
    while (!glfwWindowShouldClose(window.window))
    {
        try
        {
            stats.tick;
            if (stats.count % 999 == 0)
            {
                stats.toString.writeln;
            }
            foreach (visitor; visitors)
            {
                scene.get.accept(visitor);
            }

            glfwSwapBuffers(window.window);

            // poll glfw and scene graph "events"
            glfwPollEvents();
            receiveTimeout(msecs(-1), (shared void delegate() codeForOglThread) {
                codeForOglThread();
            });
        }
        catch (Exception e)
        {
            writeln(e);
        }
    }
    writeln("done");
}
