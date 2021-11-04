import argparse;
import automem;
import core.thread;
import sg.window;
import sg;
import std.algorithm;
import std.concurrency;
import std.conv;
import std.exception;
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

vec2 currentImageDimension;

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

Projection toProjection(Args.Projection projection, float zoom)
{
    switch (projection)
    {
    case Args.Projection.parallel:
        return new ParallelProjection(1, 1000, zoom);
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

Shape createTile(string filename, IFImage i)
{
    // dfmt off
    return new Shape(
        filename,
        new IndexedInterleavedTriangleArray(
            filename,
            Geometry.Type.ARRAY,
            new VertexData(
                filename,
                VertexData.Components(
                    VertexData.Component.VERTICES,
                    VertexData.Component.TEXTURE_COORDINATES),
                4,
                [
                    0,   0,   1,  0.0f, 1.0f,
                    i.w, 0,   1,  1.0f, 1.0f,
                    i.w, i.h, 1,  1.0f, 0.0f,
                    0,   i.h, 1,  0.0f, 0.0f,
                ],
            ),
            [0, 1, 2, 0, 2, 3,],
        ),
        new Appearance(Textures(Texture(i))),
    );
    // dfmt on
}

void showNextImage(DirEntry nextFile, shared(Node) observer)
{
    try
    {
        auto i = read_image(nextFile.name);
        (!i.e).enforce("Cannot read " ~ nextFile.name);

        ownerTid.send(cast(shared) {
            currentImageDimension = vec2(i.w, i.h);
            auto o = cast() observer;
            // cleanup texture of old node (manually)
            auto shape = (cast(Shape) o.getChild(0).getChild(0).getChild(0));
            shape.getAppearance().free;

            o.replaceChild(0, createTile(nextFile.name, i));
            /+
                 // auto shape = (cast(Shape) o.getChild(0).getChild(0).getChild(0));

                 // replace reference counted texture
                 shape.getAppearance().setTexture(0, Texture(i));
                 /+
                 // free appearance manually and set a new one
                 shape.getAppearance().free;
                 shape.setAppearance(new Appearance(Textures(Texture(i))));
                 +/
                 +/
        });
    }
    catch (Exception e)
    {
        writeln(e);
    }
}

mixin Main.parseCLIArgs!(Args, (Args args) {
    float zoom = 1.0;
    float zoomDelta = 0.01;
    auto files = new Files(args.directory);
    auto scene = new Scene("scene");
    auto projection = args.projection.toProjection(zoom);
    auto observer = new Observer("observer", projection);
    scene.addChild(observer);
    observer.addChild(cube("image1.jpg", 0, 0, 0, 0.0001, true));
    auto mainTid = thisTid;
    auto window = new Window(scene, 800, 600, (Window w, int key, int, int action, int) {
        auto clamp(float v, float minimum, float maximum)
        {
            return min(max(v, minimum), maximum);
        }

        void zoomImage(Window w, vec2 imageDimension, float oldZoom, float newZoom)
        {
            auto windowSize = vec2(w.width, w.height);
            auto position = observer.getPosition.xy;
            auto originalPosition = ((position * oldZoom) + (windowSize / 2.0)) / oldZoom;
            auto newPosition = ((originalPosition * newZoom) - windowSize / 2.0) / newZoom;
            observer.setPosition(vec3(newPosition.x, newPosition.y, observer.getPosition.z));
        }

        void move(int dx, int dy, Window w, vec2 imageDimension, float zoom)
        {
            auto scaledImage = imageDimension * zoom;
            auto position = observer.getPosition + vec3(dx, dy, 0);

            if (scaledImage.x <= w.width)
            {
                position.x = (scaledImage.x - w.width) / 2.0 / zoom;
            }
            else
            {
                position.x = clamp(position.x, 0, (scaledImage.x - w.width) / zoom);
            }

            if (scaledImage.y <= w.height)
            {
                position.y = (scaledImage.y - w.height) / 2.0 / zoom;
            }
            else
            {
                position.y = clamp(position.y, 0, (scaledImage.y - w.height) / zoom);
            }
            observer.setPosition(position);
        }

        if (key == 'A')
        {
            move(-10, 0, w, currentImageDimension, zoom);
            return;
        }
        if (key == 'D')
        {
            move(10, 0, w, currentImageDimension, zoom);
            return;
        }
        if (key == 'W')
        {
            move(0, 10, w, currentImageDimension, zoom);
            return;
        }
        if (key == 'S')
        {
            move(0, -10, w, currentImageDimension, zoom);
            return;
        }
        if (key == GLFW_KEY_RIGHT_BRACKET)
        {
            auto oldZoom = zoom;
            zoom += zoomDelta;
            observer.setProjection(args.projection.toProjection(zoom));
            zoomImage(w, currentImageDimension, oldZoom, zoom);
            return;
        }
        if (key == GLFW_KEY_SLASH)
        {
            auto oldZoom = zoom;
            zoom -= zoomDelta;
            observer.setProjection(args.projection.toProjection(zoom));
            zoomImage(w, currentImageDimension, oldZoom, zoom);
            return;
        }
        if (key == 'R')
        {
            observer.forward();
            return;
        }
        if (key == 'F')
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
            return;
        }
        if ((key == '1') && (action == GLFW_RELEASE))
        {
            zoom = 1.0;
            observer.setProjection(args.projection.toProjection(zoom));
            return;
            /+
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
            +/
        }
        if ((key == '2') && (action == GLFW_RELEASE))
        {
            zoom = 2.0;
            observer.setProjection(args.projection.toProjection(zoom));
            return;
            //spawn(&add100Nodes, cast(shared) observer);
        }

    });

    auto v = new PrintVisitor();
    scene.accept(v);

    auto visitors = [new OGL2RenderVisitor(window), new BehaviorVisitor()];

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
