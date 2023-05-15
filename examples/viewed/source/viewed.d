import argparse : NamedArgument, CLI;
import btl.vector : Vector;
import sg.window;
import sg;

import std.algorithm : min, max, map, joiner, countUntil;
import std.math.traits : isNaN;
import std.array : array;
import std.concurrency : Tid, send, ownerTid, spawn, thisTid, receiveTimeout;
import std.conv : to;
import std.datetime.stopwatch;
import std.exception : enforce;
import std.file : DirEntry, dirEntries, SpanMode, readText;
import std.format : format;
import std.stdio : writeln;
import std.path : dirName;
import gl3n.linalg;
import imagefmt;

import mir.deser.json : deserializeJson;

static struct Args
{
    @NamedArgument("directory", "dir", "d")
    string directory = ".";

    @NamedArgument("album", "a")
    string album;
}

Projection getProjection(float zoom)
{
    return new ParallelProjection(1, 1000, zoom);
}

class Files
{
    DirEntry[] files;
    size_t currentIndex;
    this(string directory)
    {
        files = directory.dirEntries("*.jpg", SpanMode.depth).array;
        (files.length > 0).enforce("no jpg files found");
        currentIndex = 0;
    }
    this(string[] directories)
    {
        files = directories.map!(dir => dir.dirEntries("*.jpg", SpanMode.depth)).joiner.array;
    }

    void select(DirEntry file)
    {
        currentIndex = files.countUntil(file);
    }

    bool empty()
    {
        return files.length == 0;
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

    auto back()
    {
        return files[currentIndex];
    }

    void popBack() {
        currentIndex--;
        if (currentIndex < 0) {
            currentIndex = (files.length-1).to!int;
        }
    }
    auto array()
    {
        return files;
    }
}

ShapeGroup createTile(string filename, IFImage i)
{
    // dfmt off
    Geometry geometry = IndexedInterleavedTriangleArray.make(
        filename,
        GeometryData.Type.ARRAY,
        Vertices.make(
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
        [0u, 1u, 2u, 0u, 2u, 3u,],
    );
    return ShapeGroup.make(
        filename,
        geometry,
        Appearance.make(
            filename,
            "position_texture",
            Vector!(Texture).build(Texture.make(i))
        ),
    );
    // dfmt on
}

class LoadException : Exception
{
    string errorMessage;
    this(string message, string errorMessage)
    {
        super(message);
        this.errorMessage = errorMessage;
    }
}
void loadNextImage(Tid tid, vec2 windowSize, DirEntry nextFile)
{
    try
    {
        auto sw = StopWatch(AutoStart.yes);
        auto i = read_image(nextFile.name);
        (!i.e).enforce(new LoadException("Cannot read '%s' because %s".format(nextFile.name, IF_ERROR[i.e]), IF_ERROR[i.e]));
        writeln("Image %s loaded in %sms".format(nextFile.name, sw.peek.total!("msecs")));

        tid.send(cast(shared)(ObserverData o, ref vec2 currentImageDimension, ref float zoom) {
            try
            {
                currentImageDimension = vec2(i.w, i.h);

                zoom = min(
                    windowSize.x.to!float / currentImageDimension.x,
                    windowSize.y.to!float / currentImageDimension.y);
                o.setProjection(zoom.getProjection);
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
    catch (LoadException e)
    {
        tid.send(cast(shared)e);
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

mixin CLI!Args.main!(
    (args)
    {
        viewed(args);
    }
);

auto getFiles(Args args)
{
    if (args.album.length > 0)
    {
        string[] directories = args
            .album
            .readText
            .deserializeJson!(string[])
            .map!(d => "%s/%s".format(args.album.dirName, d))
            .array;
        return new Files(directories);
    }
    else
    {
        return new Files(args.directory);
    }
}

void viewed(Args args)
{
    bool showFileList = false;
    bool showFileInfo = false;
    vec2 currentImageDimension;
    string currentError;
    float zoom = 1.0;
    float zoomDelta = 0.01;
    auto files = getFiles(args);
    auto scene = Scene.make("scene");
    auto projection = zoom.getProjection;
    auto observer = Observer.make("observer", projection);
    observer.get.setPosition(vec3(0, 0, 100));
    scene.get.addChild(observer);
    auto clamp(float v, float minimum, float maximum)
    {
        return min(max(v, minimum), maximum);
    }
    void adjustAndSetPosition(vec2 newPosition, vec2 imageDimension, float zoom, Window w)
    {
        auto position = vec3(newPosition.x, newPosition.y, 100);
        auto scaledImage = imageDimension * zoom;

        if (scaledImage.x <= w.getWidth)
        {
            position.x = (scaledImage.x - w.getWidth) / 2.0 / zoom;
        }
        else
        {
            position.x = clamp(position.x, 0, imageDimension.x - w.getWidth / zoom);
        }

        if (scaledImage.y <= w.getHeight)
        {
            position.y = (scaledImage.y - w.getHeight) / 2.0 / zoom;
        }
        else
        {
            position.y = clamp(position.y, 0, imageDimension.y - w.getHeight / zoom);
        }
        observer.get.setPosition(position);
    }

    void zoomImage(Window w, vec2 imageDimension, float oldZoom, float newZoom)
    {
        zoom = newZoom;
        observer.get.setProjection(zoom.getProjection);

        auto windowSize = vec2(w.getWidth, w.getHeight);
        auto position = observer.get.getPosition.xy;
        auto originalPosition = ((position * oldZoom) + (windowSize / 2.0)) / oldZoom;
        auto newPosition = ((originalPosition * newZoom) - windowSize / 2.0) / newZoom;

        adjustAndSetPosition(newPosition, imageDimension, zoom, w);
    }

    void doZoom(Window w,
                int input,
                int key,
                float newZoom,
                Observer observer,
                int action,
                vec2 imageDimension)
    {
        if ((input == key) && (action == GLFW_RELEASE))
        {
            zoomImage(w, imageDimension, zoom, newZoom);
        }
    }

    void move(int dx, int dy, Window w, vec2 imageDimension, float zoom)
    {
        auto position = observer.get.getPosition.xy + vec2(dx, dy);
        adjustAndSetPosition(position, imageDimension, zoom, w);
    }

    auto window = new Window(scene, 800, 600, (Window w, int key, int /+scancode+/, int action, int /+mods+/) {
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
            zoomImage(w, currentImageDimension, zoom, zoom + zoomDelta);
            return;
        }
        if (key == GLFW_KEY_SLASH)
        {
            zoomImage(w, currentImageDimension, zoom, zoom - zoomDelta);
            return;
        }
        if ((key == 'F') && (action == GLFW_RELEASE))
        {
            showFileList = !showFileList;
            return;
        }
        if ((key == 'I') && (action == GLFW_RELEASE))
        {
            showFileInfo = !showFileInfo;
            return;
        }
        if ((key == 'P') && (action == GLFW_RELEASE))
        {
            scene.get.accept(new PrintVisitor());
            return;
        }
        if ((key == 'B') && (action == GLFW_RELEASE))
        {
            files.popBack;
            spawn(&loadNextImageSpawnable, vec2(w.width, w.height), files.front);
            return;
        }
        if ((key == 'N') && (action == GLFW_RELEASE))
        {
            files.popFront;
            spawn(&loadNextImageSpawnable, vec2(w.width, w.height), files.front);
            return;
        }

        doZoom(w, key, '1', 1.0 / 16, observer, action, currentImageDimension);
        doZoom(w, key, '2', 1.0 / 8, observer, action, currentImageDimension);
        doZoom(w, key, '3', 1.0 / 4, observer, action, currentImageDimension);
        doZoom(w, key, '4', 1.0 / 3, observer, action, currentImageDimension);
        doZoom(w, key, '5', 1.0, observer, action, currentImageDimension);
        doZoom(w, key, '6', 1.0 * 2, observer, action, currentImageDimension);
        doZoom(w, key, '7', 1.0 * 3, observer, action, currentImageDimension);
        doZoom(w, key, '8', 1.0 * 4, observer, action, currentImageDimension);
        doZoom(w, key, '9', 1.0 * 5, observer, action, currentImageDimension);
        doZoom(w, key, '0', 1.0 * 6, observer, action, currentImageDimension);
    });

    loadNextImage(thisTid, vec2(window.width, window.height), files.front);

    import sg.visitors : RenderVisitor, BehaviorVisitor;

    version (Default)
    {
        /// noop if not gl_33
        class ImguiVisitor : Visitor
        {
            alias visit = Visitor.visit;
            override void visit(SceneData n)
            {
            }
        }
    }
    version (GL_33)
    {
        class ImguiVisitor : Visitor
        {
            import imgui;
            int fileListScrollArea;
            int fileInfoScrollArea;
            this()
            {
                import std.path : expandTilde;
                "~/.config/viewed/font.ttf".expandTilde.imguiInit.enforce;
            }
            alias visit = Visitor.visit;
            override void visit(SceneData n)
            {
                bool uiActive = showFileInfo || showFileList;
                if (!uiActive)
                {
                    return;
                }
                enum BORDER = 10;
                int xPos = 0;
                auto mouse = window.getMouseInfo();
                auto scrollInfo = window.getScrollInfo;
                imguiBeginFrame(mouse.x, mouse.y, mouse.button, cast(int)scrollInfo.yOffset, 0);
                scrollInfo.reset;
                if (showFileList)
                {
                    imguiBeginScrollArea("Files", xPos+BORDER, BORDER, window.width/3, window.height-2*BORDER, &fileListScrollArea);
                    xPos += window.width/3 + 2*BORDER;
                    foreach (file; files.array)
                    {
                        auto active = file == files.front;
                        if (imguiButton("%s %s".format(active ? "-> ": "", file.to!string), active ? Enabled.no : Enabled.yes))
                        {
                            files.select(file);
                            loadNextImage(thisTid, vec2(window.width, window.height), files.front);
                        }
                    }
                    imguiEndScrollArea();
                }
                if (showFileInfo)
                {
                    imguiBeginScrollArea("Info", xPos+BORDER, BORDER, window.width/3, window.height-2*BORDER, &fileInfoScrollArea);
                    auto active = files.front;
                    imguiLabel("Filename:");
                    imguiValue(active);
                    imguiLabel("Filesize:");
                    imguiValue(active.size.to!string);
                    if (!currentImageDimension.x.isNaN)
                    {
                        imguiLabel("Dimension:");
                        imguiValue(currentImageDimension.to!string);
                    }
                    if (currentError.length)
                    {
                        imguiLabel("Error:");
                        imguiValue(currentError);
                    }
                    imguiEndScrollArea();
                }
                imguiEndFrame();
                if (showFileInfo || showFileList)
                {
                    import bindbc.opengl;
                    glEnable(GL_BLEND);
                    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
                    glDisable(GL_DEPTH_TEST);
                    imguiRender(window.width, window.height);
                }
            }
        }
    }

    // dfmt off
    Visitor renderVisitor = new RenderVisitor(window);
    auto visitors = [
        renderVisitor,
        new BehaviorVisitor(),
        new ImguiVisitor(),
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
        // dfmt off
        receiveTimeout(msecs(-1),
                       (shared void delegate(ObserverData o, ref vec2 imageDimension, ref float zoom) codeForOglThread) {
                           currentError = "";
                           codeForOglThread(observer.get, currentImageDimension, zoom);
                           move(0, 0, window, currentImageDimension, zoom); // clamp image to window
                       },
                       (shared void delegate() codeForOglThread) {
                           codeForOglThread();
                       },
                       (shared(LoadException) loadException)
                       {
                           currentImageDimension = vec2(float.nan, float.nan);
                           currentError = loadException.errorMessage;
                       }
        );
        // dfmt on
    }
}
