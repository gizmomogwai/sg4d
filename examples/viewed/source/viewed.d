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

ShapeGroup createTile(string filename, IFImage i)
{
    // dfmt off
    auto app = Appearance.make("position_texture", Textures(Texture(i)));
    return ShapeGroup.make(
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
                    0,   0,   0,  0.0f, 1.0f,
                    i.w, 0,   0,  1.0f, 1.0f,
                    i.w, i.h, 0,  1.0f, 0.0f,
                    0,   i.h, 0,  0.0f, 0.0f,
                ],
            ),
            [0, 1, 2, 0, 2, 3,],
        ),
        app,
    );
    // dfmt on
}

void loadNextImage(Tid tid, vec2 windowSize, DirEntry nextFile)
{
    try
    {
        auto i = read_image(nextFile.name);
        (!i.e).enforce("Cannot read '%s'".format(nextFile.name));
        tid.send(cast(shared) (ObserverData o, ref vec2 currentImageDimension)  {
            try
            {
                currentImageDimension = vec2(i.w, i.h);

                (cast(ParallelProjection)(o.getProjection())).zoom = min(
                    windowSize.x.to!float / currentImageDimension.x,
                    windowSize.y.to!float / currentImageDimension.y);
                Node newNode = createTile(nextFile.name, i);
                if (o.childs.length > 0)
                {
                    o.replaceChild(0, newNode);
                }
                else
                {
                    o.addChild(newNode);
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

void loadNextImageSpawnable(vec2 windowSize, DirEntry nextFile)
{
    loadNextImage(ownerTid, windowSize, nextFile);
}

void doZoom(int input, int key, ref float zoom, float newZoom, Observer observer, int action)
{
    if ((input == key) && (action == GLFW_RELEASE))
    {
        zoom = newZoom;
        observer.get.setProjection(getProjection(zoom));
    }
}

mixin Main.parseCLIArgs!(Args, (Args args) {
    vec2 currentImageDimension;
    float zoom = 1.0;
    float zoomDelta = 0.01;
    auto files = new Files(args.directory);
    auto scene = Scene.make("scene");
    auto projection = getProjection(zoom);
    auto observer = Observer.make("observer", projection);
    observer.get.setPosition(vec3(0, 0, 100));
    scene.get.addChild(observer);
    auto window = new Window(scene, 800, 600, (Window w, int key, int, int action, int) {
        auto clamp(float v, float minimum, float maximum)
        {
            return min(max(v, minimum), maximum);
        }

        void zoomImage(Window w, vec2 imageDimension, float oldZoom, float newZoom)
        {
            auto windowSize = vec2(w.getWidth, w.getHeight);
            auto position = observer.get.getPosition.xy;
            auto originalPosition = ((position * oldZoom) + (windowSize / 2.0)) / oldZoom;
            auto newPosition = ((originalPosition * newZoom) - windowSize / 2.0) / newZoom;
            observer.get.setPosition(vec3(newPosition.x, newPosition.y, observer.get.getPosition.z));
        }

        void move(int dx, int dy, Window w, vec2 imageDimension, float zoom)
        {
            auto scaledImage = imageDimension * zoom;
            auto position = observer.get.getPosition + vec3(dx, dy, 0);

            if (scaledImage.x <= w.getWidth)
            {
                position.x = (scaledImage.x - w.getWidth) / 2.0 / zoom;
            }
            else
            {
                position.x = clamp(position.x, 0, imageDimension.x - w.getWidth/zoom);
            }

            if (scaledImage.y <= w.getHeight)
            {
                position.y = (scaledImage.y - w.getHeight) / 2.0 / zoom;
            }
            else
            {
                position.y = clamp(position.y, 0, imageDimension.y - w.getHeight/zoom);
            }
            observer.get.setPosition(position);
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
            observer.get.setProjection(getProjection(zoom));
            zoomImage(w, currentImageDimension, oldZoom, zoom);
            return;
        }
        if (key == GLFW_KEY_SLASH)
        {
            auto oldZoom = zoom;
            zoom -= zoomDelta;
            observer.get.setProjection(getProjection(zoom));
            zoomImage(w, currentImageDimension, oldZoom, zoom);
            return;
        }
        if (key == 'R')
        {
            observer.get.forward();
            return;
        }
        if (key == 'F')
        {
            observer.get.backward();
            return;
        }
        if (key == 'P')
        {
            scene.get.accept(new PrintVisitor());
            return;
        }
        if ((key == 'N') && (action == GLFW_RELEASE))
        {
            files.popFront;
            spawn(&loadNextImageSpawnable,
                  vec2(w.width, w.height),
                  files.front);
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

    loadNextImage(thisTid, vec2(window.width, window.height), files.front);

    import sg.visitors;

    // dfmt off
    Visitor renderVisitor = new TheRenderVisitor(window);
    auto visitors = [
        renderVisitor,
        new BehaviorVisitor(),
    ];
    // dfmt on

    while (!glfwWindowShouldClose(window.window))
    {
        foreach (visitor; visitors)
        {
            scene.get.accept(visitor);
        }

        glfwSwapBuffers(window.window);

        // poll glfw and scene graph "events"
        glfwPollEvents();
        receiveTimeout(msecs(-1),

                       (shared void delegate(ObserverData o, ref vec2 imageDimension) codeForOglThread) {
                           codeForOglThread(observer.get, currentImageDimension);
                       },

                       (shared void delegate() codeForOglThread) {
                           codeForOglThread();
                       },
        );
    }
});
