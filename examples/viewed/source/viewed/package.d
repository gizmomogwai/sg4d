module viewed;

import bindbc.glfw : GLFW_RELEASE, GLFW_PRESS, GLFW_KEY_ENTER,
    GLFW_KEY_BACKSPACE, GLFW_KEY_RIGHT_BRACKET, GLFW_KEY_SLASH, GLFW_KEY_COMMA,
    GLFW_KEY_RIGHT, GLFW_KEY_LEFT, glfwWindowShouldClose, glfwSwapBuffers,
    glfwPollEvents, GLFW_KEY_ESCAPE;
import btl.vector : Vector;
import gamut : Image;
import gl3n.linalg : vec2, vec3;

version (unittest)
{
}
else
{
    import mir.deser.json : deserializeJson;
    import mir.ser.json : serializeJson;
}
import sg : Texture, ParallelProjection, ShapeGroup, Geometry,
    IndexedInterleavedTriangleArray, GeometryData, Vertices, Appearance,
    ObserverData, Scene, Observer, Visitor, SceneData, VertexData, Node, PrintVisitor;
import sg.visitors : RenderVisitor, BehaviorVisitor;
import sg.window : Window;
import std.algorithm : min, max, map, joiner, countUntil, sort, reverse, filter, find, clamp;
import std.array : array, join, replace, split;
import std.concurrency : Tid, send, ownerTid, spawn, thisTid, receiveTimeout;
import std.conv : to;
import std.datetime.stopwatch;
import std.exception : enforce;
import std.file : DirEntry, dirEntries, SpanMode, readText, write, exists;
import std.format : format;
import std.math.traits : isNaN;
import std.path : dirName, expandTilde;
import std.range : chunks, take, empty;
import std.regex : replaceFirst, regex;
import std.stdio : writeln;
import core.time : Duration;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.datetime.systime : SysTime, Clock;
import args : Args;
import viewed.expression;

version (unittest)
{
    import unit_threaded : should;
}

bool imageChangedExternally = false;
bool firstImage = true;

string formatBigNumber(T)(const T number)
{
    import std.format.spec : singleSpec;
    import std.format.write : formatValue;
    import std.array : appender;

    auto buffer = appender!string();
    static spec = "%,3d".singleSpec;
    spec.separatorChar = '.';
    buffer.formatValue(number, spec);
    return buffer[];
}

auto getProjection(float zoom)
{
    return new ParallelProjection(1, 1000, zoom);
}

class ImageFile
{
    DirEntry file;
    string[] tags;
    this(DirEntry file)
    {
        this.file = file;
        this.tags = file.loadTags();
    }

    void addTag(string tag)
    {
        if (tags.find(tag).empty)
        {
            tags ~= tag;
            tags.sort;
            file.storeTags(tags);
        }
    }
}

class Files
{
    public ImageFile[] files;
    private string filter;
    public bool filterState;
    public ImageFile[] filteredFiles;
    size_t currentIndex;
    enum IMAGE_PATTERN = "{*.jpg,*.png}";
    this(string directory)
    {
        files = directory.expandTilde.dirEntries(IMAGE_PATTERN, SpanMode.depth)
            .array.sort.map!(dirEntry => new ImageFile(dirEntry)).array;
        runFilter();
        init();
    }

    private void init()
    {
        (files.length > 0).enforce("no images found");
        currentIndex = 0;
    }

    this(string[] directories)
    {
        // dfmt off
        files = directories.map!(
            dir => dir
            .expandTilde
            .dirEntries(IMAGE_PATTERN, SpanMode.depth)
            .array
            .sort.map!(dirEntry => new ImageFile(dirEntry)))
            .joiner
            .array;
        runFilter();
        init();
    }

    void runFilter()
    {
        if (filter.empty)
        {
            filteredFiles = files;
            filterState = true;
        }
        else
        {
            try {
                auto matcher = filter.matcherForExpression;
                filteredFiles = files.filter!(f => matcher.matches(f.tags)).array;
                filterState = true;
            }
            catch (Exception e)
            {
                writeln(e);
                filteredFiles = files;
                filterState = false;
            }
        }
    }

    void select(ImageFile file)
    {
        currentIndex = filteredFiles.countUntil(file);
    }

    bool empty()
    {
        return filteredFiles.length == 0;
    }

    auto front()
    {
        return filteredFiles[currentIndex];
    }

    void popFront()
    {
        currentIndex++;
        if (currentIndex == filteredFiles.length)
        {
            currentIndex = 0;
        }
    }

    auto back()
    {
        return filteredFiles[currentIndex];
    }

    void popBack()
    {
        if (currentIndex > 0)
        {
            currentIndex--;
        }
        else
        {
            enforce(!filteredFiles.empty, "No images");
            currentIndex = filteredFiles.length + -1;
        }
    }

    void jumpTo(in string s)
    {
        const h = filteredFiles.countUntil!(v => v.file.to!string == s);
        if (h != -1)
        {
            currentIndex = h;
        }
    }

    void update()
    {
        auto current = front;
        runFilter();
        currentIndex = filteredFiles.countUntil(current);
        if (currentIndex == -1) {
            currentIndex = 0;
        }
    }
}

auto loadTags(DirEntry e)
{
    auto propertiesFile = e.name ~ ".properties";
    if (propertiesFile.exists)
    {
        return propertiesFile.readText.idup.loadJavaProperties;
    }
    return null;
}

auto storeTags(DirEntry e, string[] tags)
{
    auto propertiesFile = e.name ~ ".properties";
    propertiesFile.write(tags.toJavaProperties());
}
string[] loadJavaProperties(string content)
{
    return content
        .split("\n")
        .map!(line => line.split("="))
        .filter!(keyValue => keyValue.length == 2 && keyValue[1] == "true")
        .map!(keyValue => keyValue[0])
        .array
        ;
}

@("load java properties") unittest
{
    "iotd=true\n".loadJavaProperties.should == ["iotd"];
    "iotd=true\niotd2=true\n".loadJavaProperties.should == ["iotd", "iotd2"];
    "iotd=false\niotd2=true\n".loadJavaProperties.should == ["iotd2"];
}

string toJavaProperties(string[] tags)
{
    return tags.map!(t => "%s=true".format(t)).joiner("\n").to!string ~"\n";
}
@("convert to java properties") unittest
{
    ["a", "b", "c"].toJavaProperties.should == "a=true\nb=true\nc=true\n";
}

auto createTile(string filename, Image* i)
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

    void loadNextImage(Tid tid, vec2 windowSize, ImageFile nextFile)
    {
        try
        {
            const sw = StopWatch(AutoStart.yes);

            Image* image = new Image;
            image.loadFromFile(nextFile.file.name);
            auto loadDuration = sw.peek.total!("msecs");
            // dfmt off
        writeln("Image %s load%sin %sms".format(
                    nextFile.file.name,
                    image.isValid ? "ed sucessfully " : "ing failed ",
                    loadDuration));
        // dfmt on
            image.isValid.enforce(new LoadException("Cannot read '%s' because %s".format(nextFile.file.name,
                    image.errorMessage), image.errorMessage.to!string, loadDuration));
            if ((image.pitchInBytes != image.width * 3) && (image.pitchInBytes != image.width * 4))
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
                    Node newNode = createTile(nextFile.file.name, image);
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

    void loadNextImageSpawnable(vec2 windowSize, shared(ImageFile) nextFile)
    {
        loadNextImage(ownerTid, windowSize, cast() nextFile);
    }

    // maps from album://string to filename
    // or from directory://string to filename
    static class State
    {
        string[string] indices;
        auto key(Args args)
        {
            return args.album.length > 0 ? "album://" ~ args.album : "directory://" ~ args
                .directory;
        }

        auto updateAndStore(Files files, Args args)
        {
            indices[key(args)] = files.front.file;
            version (unittest)
            {
            }
            else
            {
                stateFile.write(serializeJson(this));
            }
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

    auto getFiles(ref Args args)
    {
        const sw = StopWatch(AutoStart.yes);
        scope (exit)
        {
            writeln("getFiles took: %s".format(sw.peek));
        }
        if (args.album.length > 0)
        {
            version (unittest)
            {
                assert(0);
            }
            else
            {
                args.album = args.album.expandTilde;
                string[] directories = args.album
                    .readText
                    .deserializeJson!(string[])
                    .map!(d => "%s/%s".format(args.album.dirName, d))
                    .array;
                return new Files(directories);
            }
        }
        else
        {
            args.directory = args.directory.expandTilde;
            return new Files(args.directory);
        }
    }

    auto stateFile()
    {
        return "~/.config/viewed/state.json".expandTilde;
    }

    auto readStatefile()
    {
        version (unittest)
        {
            return new State();
        }
        else
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
    }

    struct Visible
    {
        bool current;
        bool should;
        bool needsRendering()
        {
            return current || should;
        }

        void animationDone()
        {
            current = should;
        }
    }

    public void viewedMain(Args args)
    {
        /+
     auto sw = StopWatch(AutoStart.yes);
     Image* image = new Image;
     string benchmark = "images/1/monalisa-original.jpg";
     image.loadFromFile(benchmark);
     auto loadDuration = sw.peek.total!("msecs");
     writeln("single threaded ", benchmark, ": ", loadDuration);
     +/
        args.directory.expandTilde;
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
        import imgui : ScrollAreaContext;

        ScrollAreaContext viewedGui;
        ScrollAreaContext filterGui;
        ScrollAreaContext fileList;
        ScrollAreaContext fileInfo;
        ScrollAreaContext stats;

        auto clamp(float v, float minimum, float maximum)
        {
            return min(max(v, minimum), maximum);
        }

        void adjustAndSetPosition(vec2 newPosition, vec2 imageDimension, float zoom, Window w)
        {
            auto position = vec3(newPosition.x, newPosition.y, 100);
            const scaledImage = imageDimension * zoom;

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

            const windowSize = vec2(w.getWidth, w.getHeight);
            const position = observer.get.getPosition.xy;
            const originalPosition = ((position * oldZoom) + (windowSize / 2.0)) / oldZoom;
            auto newPosition = ((originalPosition * newZoom) - windowSize / 2.0) / newZoom;

            adjustAndSetPosition(newPosition, imageDimension, zoom, w);
        }

        void move(int dx, int dy, Window w, vec2 imageDimension, float zoom)
        {
            auto position = observer.get.getPosition.xy + vec2(dx, dy);
            adjustAndSetPosition(position, imageDimension, zoom, w);
        }

        version (Default)
        {
            /// noop if not gl_33
            class ImguiVisitor : Visitor
            {
                alias visit = Visitor.visit;
                this(Window w)
                {
                }

                override void visit(SceneData n)
                {
                }
            }
        }
        version (GL_33)
        {
            class ImguiVisitor : Visitor
            {
                import imgui : ImGui, MouseInfo, Enabled, Sizes, addGlobalAlpha;
                import imgui.colorscheme : ColorScheme, defaultColorScheme, RGBA;

                Window window;
                ImGui gui;
                Duration renderTime;
                enum BORDER = 20;
                string newTag;
                const(ColorScheme) errorColorScheme;
                this(Window window)
                {
                    this.window = window;
                    gui = new ImGui("~/.config/viewed/font.ttf".expandTilde);
                    ColorScheme h = defaultColorScheme;
                    h.textInput.back = RGBA(255, 0, 0, 255);
                    h.textInput.backDisabled = RGBA(255, 0, 0, 255);
                    errorColorScheme = h;
                }

                alias visit = Visitor.visit;
                void renderFileList(ref int xPos, ref int yPos, const int height)
                {
                    if (fileList.isVisible)
                    {
                        xPos += BORDER;
                        const width = window.width / 3;
                        // dfmt off
                    string title = "Files %d/%d/%d".format(files.currentIndex + 1,
                                                           files.filteredFiles.length,
                                                           files.files.length);
                    gui.scrollArea(fileList, title,
                                   xPos, yPos, width, height,
                                   () {
                                       if (gui.textInput("Filter: ", files.filter, false, files.filterState ? defaultColorScheme : errorColorScheme)) {
                                           auto currentFile = files.front;
                                           auto currentCount = files.filteredFiles.length;
                                           files.update();
                                           if ((currentFile != files.front) || (currentCount != files.filteredFiles.length)) {
                                               state = state.updateAndStore(files, args);
                                               imageChangedExternally = true;
                                               loadImage();
                                           }
                                       }
                                   },
                                   () {
                                       xPos += width;
                                       foreach (file; files.filteredFiles)
                                       {
                                           const active = file == files.front;
                                           if ((imageChangedExternally || firstImage) && active)
                                           {
                                               gui.revealNextElement(fileList);
                                               imageChangedExternally = false;
                                               firstImage = false;
                                           }
                                           // dfmt off
                                           const shortenedFilename = file.file
                                               .to!string
                                               .replace(args.directory !is null ? args.directory : "", "")
                                               .replace(args.album !is null? args.album.dirName : "", "")
                                               .replaceFirst(regex("^/"), "");
                                           // dfmt on
                        const title = "%s %s".format(active ? "-> " : "", shortenedFilename);
                        if (gui.button(title, active ? Enabled.no : Enabled.yes))
                        {
                            files.select(file);
                            state = state.updateAndStore(files, args);
                            loadImage();
                        }
                    }
                }, true, 2000);
            }
        }

        private void loadImage()
        {
            // dfmt off
                auto currentImage = files.front;
                spawn(
                    &loadNextImageSpawnable,
                    vec2(window.width, window.height),
                    cast(shared)currentImage);
                // dfmt on
        }

        void renderStats(ref int xPos, ref int yPos, const int height)
        {
            if (stats.isVisible)
            {
                xPos += BORDER;
                const width = window.width / 4;
                gui.scrollArea(stats, "Stats", xPos, yPos, width, height, () {}, () {
                    xPos += width;
                    gui.label("UI Rendertime:");
                    gui.value(renderTime.total!("msecs")
                        .to!string);
                    gui.separatorLine();
                });
            }
        }

        void renderFileInfo(ref int xPos, ref int yPos, const int height)
        {
            if (fileInfo.isVisible)
            {
                xPos += BORDER;
                const width = max(0, window.width - BORDER - xPos);
                gui.scrollArea(fileInfo, "Info", xPos, yPos, width, height, () {}, () {
                    xPos += width;
                    auto imageFile = files.front;
                    auto imageDirEntry = imageFile.file;
                    gui.label("Filename:");
                    gui.value(imageDirEntry);
                    gui.separatorLine();
                    gui.label("Filesize:");

                    gui.value(imageDirEntry.size.formatBigNumber);
                    gui.separatorLine();
                    if (!currentImageDimension.x.isNaN)
                    {
                        gui.label("Dimension:");
                        gui.value(currentImageDimension.to!string);
                        gui.separatorLine();
                        gui.label("Pixels:");
                        gui.value((currentImageDimension.x.to!int * currentImageDimension.y.to!int)
                            .formatBigNumber);
                        gui.separatorLine();
                    }
                    if (currentError.length)
                    {
                        gui.label("Error:");
                        gui.value(currentError);
                        gui.separatorLine();
                    }
                    gui.label("Load duration:");
                    gui.value(currentLoadDuration.to!string);
                    gui.separatorLine();
                    gui.label("Tags");
                    foreach (tag; imageFile.tags)
                    {
                        gui.value(tag);
                    }
                    if (gui.textInput("New tag", newTag))
                    {
                        imageFile.addTag(newTag);
                    }
                    gui.separatorLine();
                });
            }
        }

        void renderGui(ref int xPos, ref int yPos, ref int height)
        {
            if (viewedGui.isVisible)
            {
                // dfmt off
                    const scrollHeight = Sizes.SCROLL_AREA_HEADER
                        + Sizes.SCROLL_AREA_PADDING
                        + Sizes.SLIDER_HEIGHT
                        + Sizes.SCROLL_BAR_SIZE;
                    // dfmt on
                gui.scrollArea(viewedGui, "Gui", xPos + BORDER,
                        window.height - BORDER - scrollHeight,
                        window.width - 2 * BORDER, scrollHeight, () {}, () {
                    float oldZoom = zoom;
                    if (gui.slider("Zoom", &zoom, 0.1, 3, 0.005))
                    {
                        zoomImage(window, currentImageDimension, oldZoom, zoom);
                    }
                }, false, window.width - 2 * BORDER - Sizes.SCROLL_BAR_SIZE);
                height -= scrollHeight + BORDER;
            }
        }

        override void visit(SceneData n)
        {
            const sw = StopWatch(AutoStart.yes);
            int xPos = 0;
            int yPos = BORDER;
            int height = window.height - 2 * BORDER;
            auto mouse = window.getMouseInfo();
            auto scrollInfo = window.getAndResetScrollInfo();
            gui.frame(MouseInfo(mouse.x, mouse.y, mouse.button,
                    cast(int) scrollInfo.xOffset, cast(int) scrollInfo.yOffset),
                    window.width, window.height, window.unicode, () {

                auto t = Clock.currTime;
                viewedGui.animate(t);
                fileList.animate(t);
                fileInfo.animate(t);
                stats.animate(t);

                renderGui(xPos, yPos, height);
                renderFileList(xPos, yPos, height);
                renderStats(xPos, yPos, height);
                renderFileInfo(xPos, yPos, height);

                //movement
                gui.hotKey('w', () {
                    move(0, 10, window, currentImageDimension, zoom);
                });
                gui.hotKey('a', () {
                    move(-10, 0, window, currentImageDimension, zoom);
                });
                gui.hotKey('s', () {
                    move(0, -10, window, currentImageDimension, zoom);
                });
                gui.hotKey('d', () {
                    move(10, 0, window, currentImageDimension, zoom);
                });
                gui.hotKey('+', () {
                    zoomImage(window, currentImageDimension, zoom, zoom + zoomDelta);
                });
                gui.hotKey('-', () {
                    zoomImage(window, currentImageDimension, zoom, zoom - zoomDelta);
                });
                gui.hotKey('1', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 / 16);
                });
                gui.hotKey('2', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 / 8);
                });
                gui.hotKey('3', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 / 4);
                });
                gui.hotKey('4', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 / 3);
                });
                gui.hotKey('5', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0);
                });
                gui.hotKey('6', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 * 2);
                });
                gui.hotKey('7', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 * 3);
                });
                gui.hotKey('8', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 * 4);
                });
                gui.hotKey('9', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 * 5);
                });
                gui.hotKey('0', () {
                    zoomImage(window, currentImageDimension, zoom, 1.0 * 6);
                });

                // image navigation
                gui.hotKey(['b', 263], () {
                    files.popBack;
                    state = state.updateAndStore(files, args);
                    (&loadNextImageSpawnable).spawn(vec2(window.width,
                    window.height), cast(shared) files.front);
                    imageChangedExternally = true;
                });
                gui.hotKey(['n', ' ', 262], () {
                    files.popFront;
                    state = state.updateAndStore(files, args);
                    (&loadNextImageSpawnable).spawn(vec2(window.width,
                    window.height), cast(shared) files.front);
                    imageChangedExternally = true;
                });
                // gui hotkeys
                gui.hotKey('f', () { fileList.toggle(); });
                gui.hotKey('i', () { fileInfo.toggle(); });
                gui.hotKey(',', () { stats.toggle(); });
                gui.hotKey('g', () { viewedGui.toggle(); });
                // debug hotkey
                gui.hotKey('p', () { scene.get.accept(new PrintVisitor()); });
            });
            import bindbc.opengl : glEnable, GL_BLEND, GL_SRC_ALPHA,
                GL_ONE_MINUS_SRC_ALPHA, GL_DEPTH_TEST, glDisable, glBlendFunc;

            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glDisable(GL_DEPTH_TEST);
            gui.render();
            renderTime = sw.peek;
        }
    }
}

auto window = new Window("viewed", scene, 800, 600, (Window w, int key, int /+scancode+/ ,
        int action, int /+mods+/ ) {
    if (action != GLFW_PRESS)
    {
        return;
    }
    switch (key)
    {
    case GLFW_KEY_ENTER:
        w.unicode = 0x0d;
        break;
    case GLFW_KEY_BACKSPACE:
        w.unicode = 0x08;
        break;
    case GLFW_KEY_RIGHT:
        w.unicode = 262;
        break;
    case GLFW_KEY_LEFT:
        w.unicode = 263;
        break;
    case GLFW_KEY_ESCAPE:
        w.unicode = 0x27;
        break;
    default:
        break;
    }
}, (Window w, uint code) { w.unicode = code; });
loadNextImage(thisTid, vec2(window.width, window.height), files.front);

Visitor renderVisitor = new RenderVisitor(window);
Visitor imguiVisitor = new ImguiVisitor(window);
// dfmt off
    auto visitors = [
        renderVisitor,
        new BehaviorVisitor(),
        imguiVisitor,
    ];
    // dfmt on

while (!window.window.glfwWindowShouldClose())
{
    foreach (visitor; visitors)
    {
        scene.get.accept(visitor);
    }

    window.window.glfwSwapBuffers();

    // poll glfw
    glfwPollEvents();
    // and scene graph "events"
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
