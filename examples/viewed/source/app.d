import argparse;
import core.thread;
import sg.window;
import sg;
import std;

static struct Args
{
    @NamedArgument()
    string directory = ".";
}

vec2 currentImageDimension;

Projection getProjection(float zoom)
{
    return new ParallelProjection(1, 1000, zoom);
}

class Files
{
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

void loadNextImage(Tid tid, vec2 windowSize, DirEntry nextFile, shared(Observer) observer)
{
    try
    {
        auto i = read_image(nextFile.name);
        (!i.e).enforce("Cannot read " ~ nextFile.name);

        tid.send(cast(shared) {
            try
            {
                currentImageDimension = vec2(i.w, i.h);
                auto o = cast() observer;
                (cast(ParallelProjection)(o.getProjection())).zoom = min(
                    windowSize.x.to!float / currentImageDimension.x,
                    windowSize.y.to!float / currentImageDimension.y);
                if (o.childs.length > 0)
                {
                    auto shape = (cast(Shape) o.getChild(0));
                    shape.getAppearance().free;
                    o.replaceChild(0, createTile(nextFile.name, i));
                }
                else
                {
                    o.addChild(createTile(nextFile.name, i));
                }
            }
            catch (Exception e)
            {
                writeln(e);
            }
        });
    }
    catch (Exception e)
    {
        writeln(e);
    }
}

void loadNextImageSpawnable(vec2 windowSize, DirEntry nextFile, shared(Observer) observer)
{
    loadNextImage(ownerTid, windowSize, nextFile, observer);
}

void doZoom(int input, int key, ref float zoom, float newZoom, Observer observer, int action)
{
    if ((input == key) && (action == GLFW_RELEASE))
    {
        zoom = newZoom;
        observer.setProjection(getProjection(zoom));
    }
}

mixin Main.parseCLIArgs!(Args, (Args args) {
    float zoom = 1.0;
    float zoomDelta = 0.01;
    auto files = new Files(args.directory);
    auto scene = new Scene("scene");
    auto projection = getProjection(zoom);
    auto observer = new Observer("observer", projection);
    scene.addChild(observer);
    auto window = new Window(scene, 800, 600, (Window w, int key, int, int action, int) {
        auto clamp(float v, float minimum, float maximum)
        {
            return min(max(v, minimum), maximum);
        }

        void zoomImage(Window w, vec2 imageDimension, float oldZoom, float newZoom)
        {
            auto windowSize = vec2(w.getWidth, w.getHeight);
            auto position = observer.getPosition.xy;
            auto originalPosition = ((position * oldZoom) + (windowSize / 2.0)) / oldZoom;
            auto newPosition = ((originalPosition * newZoom) - windowSize / 2.0) / newZoom;
            observer.setPosition(vec3(newPosition.x, newPosition.y, observer.getPosition.z));
        }

        void move(int dx, int dy, Window w, vec2 imageDimension, float zoom)
        {
            auto scaledImage = imageDimension * zoom;
            auto position = observer.getPosition + vec3(dx, dy, 0);

            if (scaledImage.x <= w.getWidth)
            {
                position.x = (scaledImage.x - w.getWidth) / 2.0 / zoom;
            }
            else
            {
                position.x = clamp(position.x, 0, (scaledImage.x - w.getWidth) / zoom);
            }

            if (scaledImage.y <= w.getHeight)
            {
                position.y = (scaledImage.y - w.getHeight) / 2.0 / zoom;
            }
            else
            {
                position.y = clamp(position.y, 0, (scaledImage.y - w.getHeight) / zoom);
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
            observer.setProjection(getProjection(zoom));
            zoomImage(w, currentImageDimension, oldZoom, zoom);
            return;
        }
        if (key == GLFW_KEY_SLASH)
        {
            auto oldZoom = zoom;
            zoom -= zoomDelta;
            observer.setProjection(getProjection(zoom));
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
            spawn(&loadNextImageSpawnable, vec2(w.width, w.height),
            files.front, cast(shared) observer);
            return;
        }
        doZoom(key, '1', zoom, 1.0 / 16, observer, action);
        doZoom(key, '2', zoom, 1.0 / 8, observer, action);
        doZoom(key, '3', zoom, 1.0 / 4, observer, action);
        doZoom(key, '4', zoom, 1.0 / 3, observer, action);
        doZoom(key, '5', zoom, 1.0, observer, action);
        doZoom(key, '6', zoom, 1.0 * 2, observer, action);
        doZoom(key, '7', zoom, 1.0 * 4, observer, action);
        doZoom(key, '8', zoom, 1.0 * 8, observer, action);
        doZoom(key, '9', zoom, 1.0 * 16, observer, action);
        doZoom(key, '0', zoom, 1.0 * 32, observer, action);
    });

    auto v = new PrintVisitor();
    scene.accept(v);
    loadNextImage(thisTid, vec2(window.width, window.height), files.front, cast(shared) observer);

    import sg.visitors;

    Visitor renderVisitor = new TheRenderVisitor(window);

    auto visitors = [renderVisitor, new BehaviorVisitor(),];

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
