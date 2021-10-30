import argparse;
import automem;
import core.thread;
import std.concurrency;
import std.conv;
import std.file;
import std.random;
import std.stdio;
import std.string;

static struct Args
{
    enum Projection
    {
        parallel,
        camera
    }

    @(NamedArgument().Required())
    Projection projection;
    @NamedArgument()
    string directory = ".";
}

import sg;
import window;

auto cube(string name, Texture texture, float x, float y, float z, float rotationSpeed, bool indexed)
{
    auto translation = new TransformationNode("translation-" ~ name, mat4.translation(x, y, z));
    auto rotation = new TransformationNode("rotation-" ~ name, mat4.identity());
    // dfmt off
    auto shape =
        new Shape("cube-" ~ name,
                  indexed ?
                      new IndexedInterleavedCube("cube(size=1)", 1)
                      : new TriangleArrayCube("cube", 1),
                  new Appearance(Textures(texture))
        );
    // dfmt on
    rotation.addChild(shape);
    float rot = 0;
    // dfmt off
    rotation.addChild(
        new Behavior("rotY-" ~ name,
            {
                rotation.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)));
                rot = cast(float)(rot + rotationSpeed);
            }
        )
    );
    // dfmt on
    translation.addChild(rotation);
    return translation;
}

auto cube(string textureFile, float x, float y, float z, float rotationSpeed, bool indexed)
{
    auto translation = new TransformationNode("translation-" ~ textureFile,
            mat4.translation(x, y, z));
    auto rotation = new TransformationNode("rotation-" ~ textureFile, mat4.identity());
    auto image = read_image(textureFile, 3);
    if (image.e)
    {
        throw new Exception("%s".format(IF_ERROR[image.e]));
    }
    // dfmt off
    auto shape =
        new Shape("cube-" ~ textureFile,
                  indexed ?
                      new IndexedInterleavedCube("cube(size=1)", 1)
                      : new TriangleArrayCube("cube", 1),
                  new Appearance(Textures(Texture(image)))
        );
    // dfmt on
    rotation.addChild(shape);
    float rot = 0;
    // dfmt off
    rotation.addChild(
        new Behavior("rotY-" ~ textureFile,
            {
                rotation.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)));
                rot = cast(float)(rot + rotationSpeed);
            }
        )
    );
    // dfmt on
    translation.addChild(rotation);
    return translation;
}

auto cubeSlow(string textureFile, float x, float y, float z, float rotationSpeed, bool indexed)
{
    Thread.sleep(dur!"seconds"(2));
    return cube(textureFile, x, y, z, rotationSpeed, indexed);
}

Projection toProjection(Args.Projection projection)
{
    switch (projection)
    {
    case Args.Projection.parallel:
        return new ParallelProjection(1, 1000);
    case Args.Projection.camera:
        return new CameraProjection(1, 1000);
    default:
        throw new Exception("Unknown projection: %s".format(projection));
    }
}

void add100Nodes(shared(Node) observer)
{
    try
    {
        auto t = Texture(read_image("image1.jpg"));
        // dfmt off
        foreach (i; 0 .. 100)
        {
            () {
                auto cube = cube("cube %s".format(i), t, uniform(0, 10), uniform(0, 10), 0, uniform(0, 0.01), true);
                ownerTid.send(cast(shared) { (cast()observer).addChild(cube); });
            }(); // stupid ascii art see https://forum.dlang.org/thread/ckkswkkvhfojbcczijim@forum.dlang.org?page=2
        }
        // dfmt on
    }
    catch (Exception e)
    {
        writeln(e);
    }
}

class Files
{
    import std.array;

    DirEntry[] files;
    int currentIndex;
    this(string directory)
    {
        files = std.file.dirEntries(directory, "*.jpg", SpanMode.shallow).array;
        if (files.length == 0)
        {
            throw new Exception("no jpg files found");
        }
        currentIndex = 0;
    }

    bool empty()
    {
        return currentIndex < files.length;
    }

    auto front()
    {
        return files[currentIndex];
    }

    void popFront()
    {
        currentIndex++;
        if (currentIndex == files.length)
        {
            currentIndex = 0;
        }
    }
}

void showNextImage(DirEntry nextFile, shared(Node) observer)
{
    try
    {
        auto i = read_image(nextFile.name);
        if (i.e)
        {
            throw new Exception("Cannot read " ~ nextFile.name);
        }
        ownerTid.send(cast(shared) {
            auto o = cast() observer;
            (cast(Shape) o.getChild(0).getChild(0).getChild(0)).getAppearance()
                .setTexture(0, Texture(i));
        });
    }
    catch (Exception e)
    {
        writeln(e);
    }
}

mixin Main.parseCLIArgs!(Args, (Args args) {

    auto files = new Files(args.directory);
    auto scene = new Scene("scene");
    auto projection = args.projection.toProjection;
    auto observer = new Observer("observer", projection);
    scene.addChild(observer);
    observer.addChild(cube("image1.jpg", 0, 0, 0, 0.0001, true));

    auto mainTid = thisTid;
    auto window = new Window(scene, 800, 600, (int key, int, int action, int) {
        if (key == 'A')
        {
            observer.strafeLeft();
            return;
        }
        if (key == 'D')
        {
            observer.strafeRight();
            return;
        }
        if (key == 'W')
        {
            observer.forward();
            return;
        }
        if (key == 'S')
        {
            observer.backward();
            return;
        }
        if (key == 'P')
        {
            scene.accept(new PrintVisitor());
            return;
        }
        if ((key == 'N') && (action == GLFW_RELEASE))
        {
            files.popFront;
            spawn(&showNextImage, files.front, cast(shared) observer);
        }
        if ((key == '1') && (action == GLFW_RELEASE))
        {
            new Thread({
                try
                {
                    auto cube = cubeSlow("image1.jpg", uniform(0, 10), 0, 0, 0.05, false);
                    mainTid.send(cast(shared) { observer.addChild(cube); });
                }
                catch (Exception e)
                {
                    writeln(e);
                }
            }).start();
        }
        if ((key == '2') && (action == GLFW_RELEASE))
        {
            spawn(&add100Nodes, cast(shared) observer);
        }

    });

    PrintVisitor v = new PrintVisitor();
    scene.accept(v);

    Visitor[] visitors = [new OGL2RenderVisitor(window), new BehaviorVisitor()];

    while (!glfwWindowShouldClose(window.window))
    {
        foreach (visitor; visitors)
        {
            scene.accept(visitor);
        }

        glfwSwapBuffers(window.window);

        // poll glfw and scene graph "events"
        glfwPollEvents();
        receiveTimeout(msecs(-1), (shared void delegate() codeForOglThread) {
            codeForOglThread();
        });
    }

});
