module viewed;

import argparse : NamedArgument, CLI;
import bindbc.glfw;
import bindbc.opengl;
import btl.vector : Vector;
import gl3n.linalg : vec2, vec3;
import mir.deser.json : deserializeJson;
import mir.ser.json : serializeJson;
import sg.visitors : RenderVisitor, BehaviorVisitor;
import sg.window : Window;
import sg;
import std.algorithm : min, max, map, joiner, countUntil, sort, reverse;
import std.array : array, join, replace;
import std.range : chunks, take;
import std.concurrency : Tid, send, ownerTid, spawn, thisTid, receiveTimeout;
import std.conv : to;
import std.datetime.stopwatch;
import std.exception : enforce;
import std.file : DirEntry, dirEntries, SpanMode, readText, write;
import std.format : format;
import std.math.traits : isNaN;
import std.path : dirName, expandTilde;
import std.stdio : writeln;
import gamut : Image;
import core.time : Duration;

bool imageChangedByKey = false;
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
        files = directory.dirEntries("{*.jpg,*.png}", SpanMode.depth).array.sort.array;
        (files.length > 0).enforce("no jpg files found");
        currentIndex = 0;
    }

    this(string[] directories)
    {
        files = directories.map!(dir => dir.dirEntries("*.jpg", SpanMode.depth)
                .array.sort).joiner.array;
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

    void popBack()
    {
        if (currentIndex > 0)
        {
            currentIndex--;
        }
        else
        {
            currentIndex = (files.length - 1).to!int;
        }
    }

    auto array()
    {
        return files;
    }

    auto jumpTo(string s)
    {
        auto h = files.countUntil!(v => v.to!string == s);
        if (h != -1)
        {
            currentIndex = h;
        }
    }
}

ShapeGroup createTile(string filename, Image* i)
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
                0,       0,        0, 0.0f, 1.0f,
                i.width, 0,        0, 1.0f, 1.0f,
                i.width, i.height, 0, 1.0f, 0.0f,
                0,       i.height, 0, 0.0f, 0.0f,
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
    long duration;
    this(string message, string errorMessage, long duration)
    {
        super(message);
        this.errorMessage = errorMessage;
        this.duration = duration;
    }
}

void loadNextImage(Tid tid, vec2 windowSize, DirEntry nextFile)
{
    try
    {
        auto sw = StopWatch(AutoStart.yes);

        Image* image = new Image;
        image.loadFromFile(nextFile.name);
        auto loadDuration = sw.peek.total!("msecs");
        writeln("Image %s load%sin %sms".format(nextFile.name, image.isValid
                ? "ed sucessfully " : "ing failed ", loadDuration));

        image.isValid.enforce(new LoadException("Cannot read '%s' because %s".format(nextFile.name,
                image.errorMessage), image.errorMessage.to!string, loadDuration));
        /+
        writeln("valid: ", image.isValid);
        writeln("type: ", image.type);
        writeln("pitch: ", image.pitchInBytes);
        writeln("width: ", image.width);
        writeln("1st row: ", image.scanptr(0));
        writeln("2nd row: ", image.scanptr(1));
        writeln("diff: ", image.scanptr(1) - image.scanptr(0));
        +/
        if (image.pitchInBytes != image.width * 3)
        {
            throw new LoadException("Image with filler bytes at the end of a row",
                    "Image with filler bytes at the end of a row", loadDuration);
        }

        tid.send(cast(shared)(ObserverData o, ref vec2 currentImageDimension,
                ref float zoom, ref long currentLoadDuration) {
            try
            {
                currentLoadDuration = loadDuration;
                currentImageDimension = vec2(image.width, image.height);

                zoom = min(windowSize.x.to!float / currentImageDimension.x,
                    windowSize.y.to!float / currentImageDimension.y);
                o.setProjection(zoom.getProjection);
                Node newNode = createTile(nextFile.name, image);
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
        tid.send(cast(shared) e);
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

mixin CLI!Args.main!((args) { viewed(args); });

// maps from album://string to filename
// or from directory://string to filename
static class State
{
    string[string] indices;
    auto key(Args args)
    {
        return args.album.length > 0 ? "album://" ~ args.album : "directory://" ~ args.directory;
    }

    auto updateAndStore(Files files, Args args)
    {
        indices[key(args)] = files.front;
        stateFile.write(serializeJson(this));
        return this;
    }

    void update(ref Files files, Args args)
    {
        auto k = key(args);
        if (k in indices)
        {
            files.jumpTo(indices[k]);
        }
    }
}

auto getFiles(Args args)
{
    if (args.album.length > 0)
    {
        string[] directories = args.album
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

auto stateFile()
{
    return "~/.config/viewed/state.json".expandTilde;
}

auto readStatefile()
{
    try
    {
        return stateFile().readText().deserializeJson!(State);
    }
    catch (Exception e)
    {
        return new State();
    }

}

void viewed(Args args)
{
    /+
    auto sw = StopWatch(AutoStart.yes);
    Image* image = new Image;
    string benchmark = "images/1/monalisa-original.jpg";
    image.loadFromFile(benchmark);
    auto loadDuration = sw.peek.total!("msecs");
    writeln("single threaded ", benchmark, ": ", loadDuration);
    +/
    bool showFileList = false;
    bool showFileInfo = false;
    vec2 currentImageDimension;
    long currentLoadDuration;
    string currentError;
    float zoom = 1.0;
    float zoomDelta = 0.01;
    State state = readStatefile();
    auto files = getFiles(args);
    state.update(files, args);
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

    void doZoom(Window w, int input, int key, float newZoom, Observer observer,
            int action, vec2 imageDimension)
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

    auto window = new Window(scene, 800, 600, (Window w, int key, int /+scancode+/ , int action, int /+mods+/ ) {
        if (key == 'W')
        {
            move(0, 10, w, currentImageDimension, zoom);
            return;
        }
        if (key == 'A')
        {
            move(-10, 0, w, currentImageDimension, zoom);
            return;
        }
        if (key == 'S')
        {
            move(0, -10, w, currentImageDimension, zoom);
            return;
        }
        if (key == 'D')
        {
            move(10, 0, w, currentImageDimension, zoom);
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
            state = state.updateAndStore(files, args);
            (&loadNextImageSpawnable).spawn(vec2(w.width, w.height), files.front);
            imageChangedByKey = true;
            return;
        }
        if (((key == 'N') || (key == ' ')) && (action == GLFW_RELEASE))
        {
            files.popFront;
            state = state.updateAndStore(files, args);
            (&loadNextImageSpawnable).spawn(vec2(w.width, w.height), files.front);
            imageChangedByKey = true;
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

            ScrollInfo fileListScrollArea;
            ScrollInfo fileInfoScrollArea;
            this()
            {
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
                enum BORDER = 20;
                int xPos = 0;
                auto mouse = window.getMouseInfo();
                auto scrollInfo = window.getScrollInfo;
                imguiBeginFrame(mouse.x, mouse.y, mouse.button,
                                imgui.api.ScrollInfo(cast(int) scrollInfo.xOffset,
                                                     cast(int) scrollInfo.yOffset), 0);
                scrollInfo.reset;
                if (showFileList)
                {
                    xPos += BORDER;
                    imguiBeginScrollArea("Files %d/%d".format(files.currentIndex, files.array.length),
                                         xPos, BORDER,
                                         window.width / 3, window.height - 2 * BORDER, &fileListScrollArea, true, 2000);
                    xPos += window.width / 3;
                    foreach (file; files.take(files.array.length).array)
                    {
                        auto active = file == files.front;
                        /+
                        if (active && imageChangedByKey)
                        {
                            imguiRevealNextElement();
                            imageChangedByKey =false;
                        }
                        +/
                        if (imguiButton("%s %s".format(active ? "-> " : "",
                                                       file.to!string.replace(args.directory, "").replace(args.album.dirName, "")),
                                active ? Enabled.no : Enabled.yes))
                        {
                            files.select(file);
                            state = state.updateAndStore(files, args);
                            (&loadNextImageSpawnable).spawn(vec2(window.width,
                                    window.height), files.front);
                        }
                    }
                    imguiEndScrollArea();
                }
                if (showFileInfo)
                {
                    xPos += BORDER;
                    imguiBeginScrollArea("Info", xPos, BORDER,
                                         window.width / 3, window.height - 2 * BORDER, &fileInfoScrollArea);
                    xPos += window.width / 3;
                    auto active = files.front;
                    imguiLabel("Filename:");
                    imguiValue(active);
                    imguiLabel("Filesize:");
                    string formatFileSize(ulong fileSize)
                    {
                        import std.format.spec : singleSpec;
                        import std.format.write : formatValue;
                        import std.array : appender;

                        auto buffer = appender!string();
                        static spec = "%,3d".singleSpec;
                        spec.separatorChar = '.';
                        buffer.formatValue(fileSize, spec);
                        return buffer[];
                    }

                    imguiValue(formatFileSize(active.size));
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
                    imguiLabel("Load duration:");
                    imguiValue(currentLoadDuration.to!string);
                    imguiEndScrollArea();
                }
                imguiEndFrame();
                if (showFileInfo || showFileList)
                {
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
        receiveTimeout(-1.msecs,
                       (shared void delegate(ObserverData, ref vec2, ref float, ref long) codeForOglThread) {
                           currentError = "";
                           codeForOglThread(observer.get, currentImageDimension, zoom, currentLoadDuration);
                           move(0, 0, window, currentImageDimension, zoom); // clamp image to window
                       },
                       (shared void delegate() codeForOglThread) {
                           codeForOglThread();
                       },
                       (shared(LoadException) loadException)
                       {
                           currentLoadDuration = loadException.duration;
                           currentImageDimension = vec2(float.nan, float.nan);
                           currentError = loadException.errorMessage;
                       }
        );
        // dfmt on
    }
}
