module viewed;

import bindbc.glfw : GLFW_RELEASE, GLFW_PRESS, GLFW_KEY_ENTER,
    GLFW_KEY_BACKSPACE, GLFW_KEY_RIGHT_BRACKET, GLFW_KEY_SLASH, GLFW_KEY_COMMA,
    GLFW_KEY_RIGHT, GLFW_KEY_LEFT, glfwWindowShouldClose, glfwSwapBuffers,
    glfwPollEvents, GLFW_KEY_ESCAPE;
import sg : Texture, ParallelProjection, ShapeGroup, Geometry,
    IndexedInterleavedTriangleArray, GeometryData, Vertices, Appearance,
    ObserverData, Scene, Observer, Visitor, SceneData, VertexData, Node, PrintVisitor;
import args : Args;
import btl.vector : Vector;
import core.time : Duration;
import deepface : deepface, Face, calcDeepfaceCachePath, calcDeepfaceJsonPath;
import gamut : Image;
import gamut.types : PixelType;
import gl3n.linalg : vec2, vec3;
import imagedb : shorten;
import imgui : Editor;
import imgui.colorscheme : RGBA;
import mir.serde : serdeIgnoreUnexpectedKeys, serdeOptional, serdeKeys;
import sg.visitors : RenderVisitor, BehaviorVisitor;
import sg.window : Window;
import std.algorithm : min, max, map, joiner, countUntil, sort, reverse,
    filter, find, clamp, remove;
import std.concurrency : Tid, send, ownerTid, spawn, thisTid, receiveTimeout,
    spawnLinked, LinkTerminated, OwnerTerminated;
import std.datetime.stopwatch : StopWatch, AutoStart, msecs;
import std.datetime.systime : SysTime, Clock;
import std.conv : to;
import std.array : array, join;
import std.exception : enforce;
import std.file : SpanMode, readText, write, exists, getSize;
import std.format : format;
import std.math.traits : isNaN;
import std.process : execute;
import std.range : chunks, take, empty;
import std.regex : replaceFirst, regex, matchFirst;
import std.stdio : writeln;
import viewed.expression;
public import thepath : Path;
import viewed.tags : identityTag, loadCache, storeCache;
import progressbar : withTextUi;
version (unittest)
{
    import unit_threaded : should, shouldApproxEqual;
}
else
{
    import mir.deser.json : deserializeJson;
    import mir.ser.json : serializeJson;
}

auto getProjection(float zoom) => new ParallelProjection(1, 1000, zoom);

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

class ImageFile
{
    Path file;
    Path baseDirectory;
    string[] tags;

    float[] gps; // lat, lon, alt

    Face[] faces;
    string allNames;
    /// is exifdata read in
    bool metadataRead;
    /// exifdata if available
    Metadata metadata;

    this(Path baseDirectory, Path file)
    {
        this.file = file;
        this.baseDirectory = baseDirectory;
        auto cacheData = file.loadCache(baseDirectory);
        this.tags = cacheData.tags;
        this.gps = cacheData.gps;
        if (
            !cacheData.found
            // in a transition period it could be that old caches are used, that do not yet contain existing gps.
            // out of a transition period the cache data should always be complete
            // || this.gps == null
        )
        {
            if (hasMetadata)
            {
                auto metadata = getMetadata;
                this.gps = parseGps(metadata.position, metadata.altitude);
                if (this.gps != null)
                {
                    file.storeCache(baseDirectory, this.tags, this.gps);
                }
            }
        }
    }

    void addTag(string tag)
    {
        if (!hasTag(tag))
        {
            tags ~= tag;
            tags.sort;
            file.storeCache(baseDirectory, tags, gps);
        }
    }

    void removeTag(string tag)
    {
        if (hasTag(tag))
        {
            tags = tags.remove!(i => i == tag);
            file.storeCache(baseDirectory, tags, gps);
        }
    }

    bool hasTag(string tag)
    {
        return !tags.find(tag).empty;
    }

    auto deepface(Args args) const
    {
        return file.deepface(args);
    }

    void setFaces(Face[] faces)
    {
        this.faces = faces;
        this.allNames = faces.filter!(f => f.name)
            .map!(f => f.name)
            .join(", ");
    }

    bool hasMetadata()
    {
        if (metadataRead == false)
        {
            metadata = Metadata.read(file);
            metadataRead = true;
        }
        return metadata != Metadata.init;
    }

    auto getMetadata()
    {
        return metadata;
    }

    auto storeFaceInfo(Args args)
    {
        version (unittest)
        {
        }
        else
        {
            Path deepfaceJson = file.calcDeepfaceCachePath(args).calcDeepfaceJsonPath();
            Path newFile = deepfaceJson.withExt("new");
            newFile.writeFile(serializeJson(faces));
            auto result = ["mv", newFile.toString, deepfaceJson.toString].execute;
            if (result.status != 0)
            {
                writeln("Cannot rename ", newFile, " to ", deepfaceJson);
            }
        }
    }
}

float[] parseGps(string latLonString, string altitudeString)
{
    float[] result;
    auto latLon = latLonString.matchFirst(regex(`(?P<lat>[\d\.]+) ., (?P<lon>[\d\.]+) .`));
    if (!latLon.empty)
    {
        result ~= latLon["lat"].to!float;
        result ~= latLon["lon"].to!float;
        auto alt = altitudeString.matchFirst(regex(`(?P<altitude>\d+) m`));
        if (!alt.empty)
        {
            result ~= alt["altitude"].to!float;
        }
    }
    return result;
}

@("parseGps") unittest
{
    float[] result = parseGps("48.14211389 N, 11.58691944 E", "557 m Above Sea Level");
    result[0].should ~ 48.142;
    result[1].should ~ 11.586;
    result[2].should ~ 557.0;
}

@serdeIgnoreUnexpectedKeys struct Metadata
{
    @serdeKeys("CreateDate") @serdeOptional @("Creation Date")
    string creationDate;

    @serdeKeys("GPSPosition") @serdeOptional @("GPS Position")
    string position;

    @serdeKeys("GPSAltitude") @serdeOptional @("GPS Altitude")
    string altitude;

    public static auto read(Path file)
    {
        auto exiftool = execute(["exiftool", "-coordFormat", "%.8f", "-json", file.toString()]);
        if (exiftool.status != 0)
        {
            writeln("exiftool failed");
            return Metadata.init;
        }

        version (unittest)
        {
            return Metadata.init;
        }
        else
        {
            // writeln(exiftool.output);
            auto result = deserializeJson!(Metadata[])(exiftool.output);
            return result[0];
        }
    }
}

class Files
{
    public ImageFile[] files;
    private Editor filter;
    public bool filterState;
    public ImageFile[] filteredFiles;
    size_t currentIndex;
    enum IMAGE_PATTERN = "{*.jpg,*.JPG,*.jpeg,*.JPEG*.png,*.PNG}";
    Face[] faces;
    this(Path directory)
    {
        // dfmt off
        files = directory
            .walk(IMAGE_PATTERN, SpanMode.depth)
            .filter!(f => f.toString().find(".deepface").empty)
            .array
            .sort
            .array
            .withTextUi("%>20P%>3p")
            .map!(entry => new ImageFile(directory, entry))
            .array;
        // dfmt on
        runFilter();
        init();
    }

    private void init()
    {
        (files.length > 0).enforce("no images found");
        currentIndex = 0;
    }

    this(Path[] directories)
    {
        // dfmt off
        files = directories.map!(
            dir => dir
                .walk(IMAGE_PATTERN, SpanMode.depth)
                .filter!(f => f.toString().find(".deepface").empty)
                .array
                .sort
                .array
                .withTextUi("%>20P%>3p")
                .map!(entry => new ImageFile(dir, entry))
            )
            .joiner
            .array;
        // dfmt on
        runFilter();
        init();
    }

    void runFilter()
    {
        if (filter.buffer.empty)
        {
            filteredFiles = files;
            filterState = true;
        }
        else
        {
            try
            {
                auto predicate = filter.buffer.predicateForExpression;
                filteredFiles = files.filter!(f => predicate.test(f)).array;
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
        try {
            if (filteredFiles.empty) {
                throw new Exception("filtered files empty");
            }
        }
        catch (Exception e)
        {
            writeln(e.info.toString);
        }
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

    void jumpTo(in Path s)
    {
        const h = filteredFiles.countUntil!(v => v.file == s);
        if (h != -1)
        {
            currentIndex = h;
        }
    }

    void update()
    {
        if (empty)
        {
            runFilter();
            currentIndex = 0;
        }
        else
        {
            auto current = front;
            runFilter();
            currentIndex = filteredFiles.countUntil(current);
            if (currentIndex == -1)
            {
                currentIndex = 0;
            }
        }
    }

    void updateImage(ulong index, immutable(Face)[] faces)
    {
        files[index].setFaces(cast(Face[]) faces);
    }
}

auto createTile(Path file, Image* i)
{
    // dfmt off
    Geometry geometry = IndexedInterleavedTriangleArray.make(
        file.toString(),
        GeometryData.Type.ARRAY,
        Vertices.make(
            file.toString(),
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
        file.toString(),
        geometry,
        Appearance.make(
            file.toString(),
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

void setPixel(Image* image, int x, int y, ref RGBA color)
{
    ubyte[] bytes = cast(ubyte[]) image.scanline(y);
    const reminder = 255 - color.a;
    if (image.type == PixelType.rgb8)
    {
        const idx = x * 3;
        bytes[idx + 0] = cast(ubyte)((bytes[idx + 0] * reminder + color.r * color.a) / 255);
        bytes[idx + 1] = cast(ubyte)((bytes[idx + 1] * reminder + color.g * color.a) / 255);
        bytes[idx + 2] = cast(ubyte)((bytes[idx + 2] * reminder + color.b * color.a) / 255);
    }
    else if (image.type == PixelType.rgba8)
    {
        const idx = x * 4;
        bytes[idx + 0] = cast(ubyte)((bytes[idx + 0] * reminder + color.r * color.a) / 255);
        bytes[idx + 1] = cast(ubyte)((bytes[idx + 1] * reminder + color.g * color.a) / 255);
        bytes[idx + 2] = cast(ubyte)((bytes[idx + 2] * reminder + color.b * color.a) / 255);
        bytes[idx + 3] = cast(ubyte)((bytes[idx + 3] * reminder + color.a * color.a) / 255);
    }
}

void drawRect(Image* image, int x, int y, int width, int height, ref RGBA color)
{
    for (int j = y; j < y + height; ++j)
    {
        image.setPixel(x, j, color);
        image.setPixel(x + width - 1, j, color);
    }
    for (int i = x + 1; i < x + width - 1; ++i)
    {
        image.setPixel(i, y, color);
        image.setPixel(i, y + height - 1, color);
    }
}

void loadNextImage(Tid tid, vec2 windowSize, ImageFile nextFile, bool renderFaces,
        immutable(RGBA[]) colors)
{
    try
    {
        const sw = StopWatch(AutoStart.yes);

        Image* image = new Image;
        image.loadFromFile(nextFile.file.toString());
        auto loadDuration = sw.peek.total!("msecs");
        // dfmt off
        writeln(format!("Image %s load%sin %sms")(
                    nextFile.file,
                    image.isValid ? "ed sucessfully " : "ing failed ",
                    loadDuration,
                ));
        image.isValid.enforce(new LoadException(format!("Cannot read '%s' because %s")(nextFile.file, image.errorMessage),
                                                image.errorMessage.to!string,
                                                loadDuration));
        if ((image.pitchInBytes != image.width * 3) && (image.pitchInBytes != image.width * 4))
        {
            throw new LoadException(
                "Image with filler bytes at the end of a row",
                "Image with filler bytes at the end of a row",
                loadDuration);
        }
        // dfmt on

        if (renderFaces)
        {
            foreach (index, face; nextFile.faces)
            {
                RGBA color = colors[index % colors.length];
                color.a = ubyte(255);
                // alpha = tagged -> 63, recognized -> 127, unknown -> 255
                if (face.name)
                {
                    color.a /= 2;
                }

                if (face.name && nextFile.hasTag(face.name.identityTag()))
                {
                    color.a /= 2;
                }
                image.drawRect(face.region.x, face.region.y, face.region.width,
                        face.region.height, color);
            }
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
                Node newNode = createTile(nextFile.file, image);
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

// dfmt off
void loadNextImageSpawnable(vec2 windowSize,
                            shared(ImageFile) nextFile,
                            bool renderFaces,
                            immutable(RGBA[]) colors) => loadNextImage(ownerTid, windowSize, cast() nextFile, renderFaces, colors);
// dfmt on

// maps from album://string to filename
// or from directory://string to filename
static class State
{
    string[string] indices;

    auto key(Args args)
    {
        return args.album != Path.init ? "album://" ~ args.album : "directory://" ~ args.directory;
    }

    auto updateAndStore(Files files, Args args)
    {
        if (files.empty)
        {
            return this;
        }
        version (unittest)
        {
        }
        else
        {
            stateFile.writeFile(serializeJson(this));
        }
        return this;
    }

    void update(ref Files files, Args args)
    {
        auto k = key(args);
        if (k in indices)
        {
            files.jumpTo(Path(indices[k]));
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
    if (args.album != Path.init)
    {
        version (unittest)
        {
            assert(0);
        }
        else
        {
            args.album = args.album.expandTilde;
            // dfmt off
            auto directories = args
                .album
                .readFileText
                .deserializeJson!(string[])
                .map!(d => args.album.parent.join(d))
                .array;
            // dfmt on
            return new Files(directories);
        }
    }
    else
    {
        args.directory = args.directory.expandTilde;
        return new Files(args.directory);
    }
}

auto stateFile() => Path("~/.config/viewed/state.json");

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
            return stateFile().readFileText().deserializeJson!(State);
        }
        catch (Exception e)
        {
            writeln(e);
            return new State();
        }
    }
}

struct DeepfaceProgress
{
    string message;
}

immutable struct FacesFound
{
    ulong index;
    Face[] faces;
}

void runDeepface(immutable(ImageFile)[] files, Args args)
{
    import deepface : deepface, finishDeepface;

    try
    {
        import core.thread.osthread : Thread;
        import core.time : dur;

        ownerTid.send(DeepfaceProgress("Deepface: Started"));
        foreach (index, file; files)
        {
            receiveTimeout(-1.msecs,); // to get the owner terminated exception
            ownerTid.send(DeepfaceProgress("Deepface: Working on %s (%s%%)".format(file.file.shorten(args),
                    (index + 1).to!float / files.length * 100)));
            try
            {
                auto facesFound = FacesFound(index, cast(immutable) file.deepface(args));
                ownerTid.send(facesFound);
            }
            catch (Exception e)
            {
                writeln(e);
            }
        }
        ownerTid.send(DeepfaceProgress("Deepface: Done"));
    }
    catch (OwnerTerminated t)
    {
    }
    finishDeepface(args);
}

void adjustAndSetPosition(scope Observer observer, vec2 newPosition,
        vec2 imageDimension, float zoom, Window w)
{
    auto position = vec3(newPosition.x, newPosition.y, 100);
    const scaledImage = imageDimension * zoom;

    if (scaledImage.x <= w.getWidth)
    {
        position.x = (scaledImage.x - w.getWidth) / 2.0 / zoom;
    }
    else
    {
        position.x = position.x.clamp(0, imageDimension.x - w.getWidth / zoom);
    }

    if (scaledImage.y <= w.getHeight)
    {
        position.y = (scaledImage.y - w.getHeight) / 2.0 / zoom;
    }
    else
    {
        position.y = position.y.clamp(0, imageDimension.y - w.getHeight / zoom);
    }
    observer.get.setPosition(position);
}

void revealFile(ImageFile imageFile)
{
    auto result = ["open", "-R", imageFile.file.toAbsolute.toString].execute;
    writeln(result);
}

public void viewedMain(Args args)
{
    vec2 currentImageDimension;
    long currentLoadDuration;
    string currentError;
    float zoom = 1.0;
    float zoomDelta = 0.01;
    State state = readStatefile();
    auto files = getFiles(args);
    state.update(files, args);
    string deepfaceProgress = "Deepface: ...";
    bool showFaces = false;
    bool renderFaces = false;
    bool showMetadata = false;
    bool showTags = false;
    bool showBasicInfo = false;
    bool imageChangedExternally = true; // true to handle showing of the first image

    // dfmt off
    immutable(RGBA[]) colors = [
        RGBA(255, 0  ,   0, 128),
        RGBA(255, 255,   0, 128),
        RGBA(  0, 255,   0, 128),
        RGBA(  0, 255, 255, 128),
        RGBA(  0,   0, 255, 128),
        RGBA(255,   0, 255, 128),
    ];
    // dfmt on

    auto deepface = spawnLinked(&runDeepface, cast(immutable) files.files, args);

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

    void zoomImage(Window w, vec2 imageDimension, float oldZoom, float newZoom)
    {
        zoom = newZoom;
        observer.get.setProjection(zoom.getProjection);

        const windowSize = vec2(w.getWidth, w.getHeight);
        const position = observer.get.getPosition.xy;
        const originalPosition = ((position * oldZoom) + (windowSize / 2.0)) / oldZoom;
        auto newPosition = ((originalPosition * newZoom) - windowSize / 2.0) / newZoom;

        observer.adjustAndSetPosition(newPosition, imageDimension, zoom, w);
    }

    void move(int dx, int dy, Window w, vec2 imageDimension, float zoom)
    {
        auto position = observer.get.getPosition.xy + vec2(dx, dy);
        observer.adjustAndSetPosition(position, imageDimension, zoom, w);
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
            import imgui : ImGui, MouseInfo, Enabled, Sizes, addGlobalAlpha, Sizes, ColumnLayout;
            import imgui.renderer.opengl33 : Opengl33;
            import imgui.colorscheme : ColorScheme, defaultColorScheme;

            Window window;
            ImGui!Opengl33 gui;
            Duration renderTime;
            enum BORDER = 20;
            Editor newTag;
            const(ColorScheme) errorColorScheme;
            ColorScheme facesColorScheme;
            this(Window window)
            {
                this.window = window;
                gui = new ImGui!(Opengl33)(Path("~/.config/viewed/font.ttf")
                        .expandTilde().toString());
                ColorScheme h = defaultColorScheme;
                h.textInput.back = RGBA(255, 0, 0, 255);
                h.textInput.backDisabled = RGBA(255, 0, 0, 255);
                errorColorScheme = h;
                facesColorScheme = defaultColorScheme;
            }

            alias visit = Visitor.visit;
            void renderFileList(ref int xPos, ref int yPos, const int height)
            {
                if (fileList.isVisible)
                {
                    xPos += BORDER;
                    const width = window.width / 3;
                    // dfmt off
                    gui.scrollArea(fileList,
                                   xPos, yPos, width, height,
                                   ()
                                   {
                                       string title = "Files %s/%d/%d".format(files.empty ? "-" : (files.currentIndex + 1).to!string,
                                                                              files.filteredFiles.length,
                                                                              files.files.length);
                                       gui.label(title);
                                       if (gui.textInput("Filter: ", files.filter, false, files.filterState ? defaultColorScheme : errorColorScheme)) {
                                           if (files.empty)
                                           {
                                               files.update();
                                               state = state.updateAndStore(files, args);
                                               imageChangedExternally = true;
                                               loadImage();
                                           }
                                           else
                                           {
                                               auto currentFile = files.front;
                                               auto currentCount = files.filteredFiles.length;
                                               files.update();
                                               if (!files.empty && (currentFile != files.front) || (currentCount != files.filteredFiles.length)) {
                                                   state = state.updateAndStore(files, args);
                                                   imageChangedExternally = true;
                                                   loadImage();
                                               }
                                           }
                                       }
                                   },
                                   ()
                                   {
                                       xPos += width;
                                       foreach (file; files.filteredFiles)
                                       {
                                           const active = file == files.front;
                                           if (imageChangedExternally && active)
                                           {
                                               gui.revealNextElement(fileList, 0.0);
                                               imageChangedExternally = false;
                                           }
                                           // dfmt off
                                           const shortenedFilename = file.file.shorten(args);
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
        if (files.empty)
        {
            return;
        }
        auto currentImage = files.front;
        spawn(
            &loadNextImageSpawnable,
            vec2(window.width, window.height),
            cast(shared)currentImage,
            renderFaces,
            colors,
        );
        // dfmt on
    }

    void renderStats(ref int xPos, ref int yPos, const int height)
    {
        if (stats.isVisible)
        {
            xPos += BORDER;
            const width = window.width / 4;
            gui.scrollArea(stats, xPos, yPos, width, height, () {
                gui.label("Stats");
            }, () {
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
            gui.scrollArea(fileInfo, xPos, yPos, width, height, () {
                gui.label("Info");
            }, () {
                xPos += width;
                if (files.empty) return;

                auto imageFile = files.front;
                auto imageFileName = imageFile.file;
                if (gui.collapse("Basic info", "", &showBasicInfo))
                {
                    gui.label("Filename:");
                    gui.value(imageFileName.toString());
                    gui.separatorLine();
                    gui.label("Filesize:");
                    gui.value(imageFileName.getSize.formatBigNumber);
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
                    if (imageFile.gps !is null)
                    {
                        gui.label("GPS:");
                        gui.value(imageFile.gps.to!string);
                    }
                    gui.label("Load duration:");
                    gui.value(currentLoadDuration.to!string);
                }
                if (gui.collapse("Tags", "", &showTags))
                {
                    foreach (tag; imageFile.tags)
                    {
                        gui.pushLayout(new ColumnLayout([-100, 0]));
                        scope (exit)
                            gui.popLayout();

                        gui.value(tag);
                        if (gui.button("X"))
                        {
                            imageFile.removeTag(tag);
                        }
                    }
                    if (gui.textInput("New tag", newTag))
                    {
                        imageFile.addTag(newTag.buffer);
                    }
                }
                if (imageFile.hasMetadata())
                {
                    if (gui.collapse("Metadata", "", &showMetadata))
                    {
                        auto metadata = imageFile.getMetadata();

                        import std.traits : FieldNameTuple;

                        static foreach (fieldName; FieldNameTuple!(Metadata))
                        {
                            static foreach (attribute; __traits(getAttributes,
                                __traits(getMember, metadata, fieldName)))
                            {
                                static if (is(typeof(attribute) == string))
                                {
                                    gui.label(attribute);
                                    gui.value(__traits(getMember, metadata, fieldName));
                                }
                            }
                        }
                    }
                }
                if (imageFile.faces)
                {
                    if (gui.collapse("Faces %s %s".format(imageFile.faces.length,
                        imageFile.allNames ? "(%s)".format(imageFile.allNames) : ""),
                        "", &showFaces))
                    {
                        gui.checkbox("Show faces", &renderFaces);
                        foreach (index, ref face; imageFile.faces)
                        {
                            auto color = colors[index % colors.length];
                            if (face.name)
                            {
                                string newTag = face.name.identityTag();
                                if (!imageFile.hasTag(newTag))
                                {
                                    facesColorScheme.button.text = color;
                                    if (gui.button("Add tag " ~ newTag,
                                        Enabled.yes, facesColorScheme))
                                    {
                                        imageFile.addTag(newTag);
                                        face.done = true;
                                        imageFile.storeFaceInfo(args);
                                    }
                                }
                                else
                                {
                                    facesColorScheme.value.text = color;
                                    gui.value(newTag, facesColorScheme);
                                }
                            }
                            else
                            {
                                facesColorScheme.label.text = color;
                                gui.label("Unknown face", facesColorScheme);
                            }
                        }
                        gui.separatorLine();
                    }
                }
            });
        }
    } // renderFileInfo

    void renderGui(ref int xPos, ref int yPos, ref int height)
    {
        if (viewedGui.isVisible)
        {
            // dfmt off
            const scrollHeight =
                + Sizes.SCROLL_AREA_PADDING
                + Sizes.LINE_HEIGHT
                + Sizes.DEFAULT_SPACING
                + Sizes.LINE_HEIGHT
                + Sizes.SCROLL_BAR_SIZE;
            gui.scrollArea(viewedGui, xPos + BORDER,
                           window.height - BORDER - scrollHeight,
                           window.width - 2 * BORDER, scrollHeight,
                           () {},
                           () {
                               float oldZoom = zoom;
                               if (gui.slider("Zoom", &zoom, 0.1, 3, 0.005))
                               {
                                   zoomImage(window, currentImageDimension, oldZoom, zoom);
                               }
                               gui.label(deepfaceProgress);
                           }, false, window.width - 2 * BORDER - Sizes.SCROLL_BAR_SIZE);
            // dfmt on
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

            void _move(int dx, int dy) => move(dx, dy, window, currentImageDimension, zoom);
            gui.hotKey('w', "Move Up", () => _move(0, 10));
            gui.hotKey('a', "Move Left", () => _move(-10, 0));
            gui.hotKey('s', "Move Down", () => _move(0, -10));
            gui.hotKey('d', "Move Right", () => _move(10, 0));

            void _zoom(float newZoom) => zoomImage(window, currentImageDimension, zoom, newZoom);
            gui.hotKey('+', "Zoom In", () => _zoom(zoom + zoomDelta));
            gui.hotKey('-', "Zoom Out", () => _zoom(zoom - zoomDelta));
            gui.hotKey('1', "Set Zoom to 1/16", () => _zoom(1.0 / 16));
            gui.hotKey('2', "Set Zoom to 1/8", () => _zoom(1.0 / 8));
            gui.hotKey('3', "Set Zoom to 1/4", () => _zoom(1.0 / 4));
            gui.hotKey('4', "Set Zoom to 1/3", () => _zoom(1.0 / 3));
            gui.hotKey('5', "Set Zoom to 1", () => _zoom(1.0));
            gui.hotKey('6', "Set Zoom to 2", () => _zoom(1.0 * 2));
            gui.hotKey('7', "Set Zoom to 3", () => _zoom(1.0 * 3));
            gui.hotKey('8', "Set Zoom to 4", () => _zoom(1.0 * 4));
            gui.hotKey('9', "Set Zoom to 5", () => _zoom(1.0 * 5));
            gui.hotKey('0', "Set Zoom to 6", () => _zoom(1.0 * 6));

            void filesChanged()
            {
                state = state.updateAndStore(files, args);
                spawn(&loadNextImageSpawnable, vec2(window.width,
                    window.height), cast(shared) files.front, renderFaces, colors,);
                imageChangedExternally = true;
            }
            // image navigation
            gui.hotKey(['b', 263], "Show previous image", () {
                files.popBack;
                filesChanged();
            });
            gui.hotKey(['n', ' ', 262], "Show next image", () {
                files.popFront;
                filesChanged();
            });
            // gui hotkeys
            gui.hotKey('f', "Show Filelist", () => fileList.toggle());
            gui.hotKey('i', "Show Fileinfo", () => fileInfo.toggle());
            gui.hotKey(',', "Show Statistics", () => stats.toggle());
            gui.hotKey('g', "Show GUI", () => viewedGui.toggle());
            gui.hotKey('r', "Reveal File in Finder", () => revealFile(files.front));
            // debug hotkey
            gui.hotKey('p', "Print Scenegraph", () => scene.get.accept(new PrintVisitor()));
            gui.hotKey('h', "Print Hotkeys",
                () => writeln(gui.state.hotkeys.map!(i => i.to!string).join("\n")));
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
loadNextImage(thisTid, vec2(window.width, window.height), files.front, renderFaces, colors);

Visitor renderVisitor = new RenderVisitor(window);
Visitor imguiVisitor = new ImguiVisitor(window);
auto visitors = [renderVisitor, new BehaviorVisitor(), imguiVisitor,];

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
                       },
                       (LinkTerminated terminated)
                       {
                           writeln(terminated);
                           if (terminated.tid == deepface)
                           {
                               writeln("deepface terminated");
                           }
                       },
                       (DeepfaceProgress deepfaceProgressMessage)
                       {
                           deepfaceProgress = deepfaceProgressMessage.message;
                       },
                       (immutable(FacesFound) found)
                       {
                           files.updateImage(found.index, found.faces);
                       },
        );
        // dfmt on
}
}
