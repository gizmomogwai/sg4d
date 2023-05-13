module sg.visitors.ogl33rendervisitor;

// http://www.lighthouse3d.com/tutorials/glsl-tutorial/hello-world/
// https://learnopengl.com/Getting-started/Shaders - great tutorial as it takes the projection and modelview matrices out of the equation!!!

version (GL_33)
{
    import bindbc.opengl;
    import sg.visitors.oglhelper;
    import std;
    import sg;
    import sg.visitors;
    import sg.window : Window;
    import std.concurrency;
    import std.conv;
    import std.exception;
    import std.string;
    import btl.autoptr.common;
    import btl.autoptr.intrusive_ptr;
    import core.stdc.stdio;

    alias TextureName = IntrusivePtr!TextureNameData;
    class TextureNameData : CustomDataData
    {
        Tid renderThread;
        GLuint textureName;
        this(Tid renderThread)
        {
            this.renderThread = renderThread;
            1.glGenTextures(&textureName);
            checkOglErrors;
        }

        ~this() @nogc
        {
            1.glDeleteTextures(&textureName);
        }
    }

    // adapted from https://github.com/extrawurst/unecht/tree/master/source/unecht/gl
    final class Shader
    {
        enum Type
        {
            vertex,
            fragment
        }

        GLuint shader;
        Type type;

        this(Type type, string source)
        {
            this.type = type;

            shader = (type == Type.vertex ? GL_VERTEX_SHADER : GL_FRAGMENT_SHADER).glCreateShader;
            checkOglErrors;

            auto stringLength = cast(int) source.length;
            const(char)* stringPointer = source.ptr;
            shader.glShaderSource(1, &stringPointer, &stringLength);
            checkOglErrors;

            shader.glCompileShader();
            checkOglErrors;

            GLint success;
            shader.glGetShaderiv(GL_COMPILE_STATUS, &success);
            checkOglErrors;
            if (!success)
            {
                GLchar[1024] infoLog;
                GLsizei logLen;
                shader.glGetShaderInfoLog(1024, &logLen, infoLog.ptr);
                checkOglErrors;

                auto errors = (infoLog[0 .. logLen - 1]).to!string;
                success.enforce("Error compiling shader\n  type='%s'\n  source='%s'\n  errors: '%s'".format(type,
                        source, errors));
            }
        }

        ~this()
        {
            shader.glDeleteShader();
            checkOglErrors;
        }
    }

    class Program
    {
        GLuint program;
        GLuint[string] attributesCache;
        GLuint[string] uniformsCache;

        this()
        {
            program = glCreateProgram();
            (program != 0).enforce("Cannot create program");
        }

        void destroy()
        {
            program.glDeleteProgram;
            checkOglErrors;
        }

        void link(Shader[] shaders...)
        {
            foreach (shader; shaders)
            {
                program.glAttachShader(shader.shader);
            }
            program.glLinkProgram();
            GLint success;
            program.glGetProgramiv(GL_LINK_STATUS, &success);
            if (success == 0)
            {
                static GLchar[1024] logBuff;
                static GLsizei logLen;
                program.glGetProgramInfoLog(logBuff.sizeof, &logLen, logBuff.ptr);
                throw new Exception("Error: linking program: %s".format(
                        logBuff[0 .. logLen - 1].to!string));
            }
        }

        auto setUniform(string name, mat4 matrix)
        {
            auto location = name in uniformsCache ? uniformsCache[name] : addUniformLocationToCache(
                    name);
            location.glUniformMatrix4fv(1, GL_TRUE, matrix.value_ptr);
            checkOglErrors;
        }

        private GLuint addUniformLocationToCache(string name)
        {
            auto location = program.glGetUniformLocation(name.ptr);
            (location != -1).enforce("Cannot find uniform location for '%s'".format(name));
            uniformsCache[name] = location;
            return location;
        }

        private GLuint addAttributeLocationToCache(string name)
        {
            auto location = program.glGetAttribLocation(name.ptr);
            (location != -1).enforce("Cannot find attribute location for '%s'".format(name));
            attributesCache[name] = location;
            return location;
        }

        auto getAttribute(string name)
        {
            return name in attributesCache ? attributesCache[name] : addAttributeLocationToCache(
                    name);
        }

        void use()
        {
            program.glUseProgram();
        }
    }

    alias FileProgram = IntrusivePtr!FileProgramData;
    class FileProgramData : CustomDataData
    {
        import fswatch;

        string shaderName;
        Program program;
        FileWatch fileWatch;
        this(string shaderName)
        {
            this.shaderName = shaderName;
            this.fileWatch = FileWatch("../shaders", true);
            update();
        }

        ~this() @nogc
        {
            printf("free program\n");
        }

        void checkForUpdates()
        {
            try
            {
                foreach (event; fileWatch.getEvents())
                {
                    import std.path;

                    if (event.path.startsWith(shaderName.baseName))
                    {
                        update();
                    }
                }
            }
            catch (Exception e)
            {
                import std.stdio;

                writeln(e);
            }
        }

        void use()
        {
            program.use();
        }

        void update()
        {
            program = new Program();
            import std.file : readText;

            scope vertexShader = new Shader(Shader.Type.vertex,
                    ("../shaders/" ~ shaderName ~ ".vert").readText);
            scope fragmentShader = new Shader(Shader.Type.fragment,
                    ("../shaders/" ~ shaderName ~ ".frag").readText);
            program.link(vertexShader, fragmentShader);
            program.use();
        }

        alias program this;
    }

    class VAO
    {
        GLuint vertexArray;
        this()
        {
            1.glGenVertexArrays(&vertexArray);
            checkOglErrors;
        }

        auto bind()
        {
            vertexArray.glBindVertexArray();
            checkOglErrors;
            return this;
        }
    }

    class VBO
    {
        GLuint buffer;
        this()
        {
            1.glGenBuffers(&buffer);
            checkOglErrors;
        }

        auto bind()
        {
            GL_ARRAY_BUFFER.glBindBuffer(buffer);
            checkOglErrors;
            return this;
        }

        auto data(T)(T[] data)
        {
            GL_ARRAY_BUFFER.glBufferData(data.length * T.sizeof,
                    cast(void*) data.ptr, GL_STATIC_DRAW);
            checkOglErrors;
            return this;
        }
    }

    class EBO
    {
        GLuint indexArray;
        this()
        {
            1.glGenBuffers(&indexArray);
            checkOglErrors;
        }

        auto bind()
        {
            GL_ELEMENT_ARRAY_BUFFER.glBindBuffer(indexArray);
            return this;
        }

        auto data(T)(T[] data)
        {
            GL_ELEMENT_ARRAY_BUFFER.glBufferData(data.length * T.sizeof,
                    cast(void*) data.ptr, GL_STATIC_DRAW);
            checkOglErrors;
            return this;
        }
    }

    alias TriangleArrayBuffers = IntrusivePtr!TriangleArrayBuffersData;
    class TriangleArrayBuffersData : CustomDataData
    {
        VAO vao;
        VBO positions;
        VBO colors;
        VBO textureCoordinates;
        this()
        {
            vao = new VAO();
            positions = new VBO();
            colors = new VBO();
            textureCoordinates = new VBO();
        }

        ~this() @nogc
        {
            printf("free triangle array buffers\n");
        }

        auto bind()
        {
            vao.bind();
            return this;
        }
    }

    alias IndexedInterleavedTriangleArrayBuffers = IntrusivePtr!IndexedInterleavedTriangleArrayBuffersData;
    class IndexedInterleavedTriangleArrayBuffersData : CustomDataData
    {
        VAO vao;
        VBO vertexData;
        EBO indexData;
        this()
        {
            vao = new VAO();
            vertexData = new VBO();
            indexData = new EBO();
        }

        ~this() @nogc
        {
            printf("free indexedinterleavedtrianglearraybuffers\n");
        }

        auto bind()
        {
            vao.bind();
            return this;
        }
    }

    // example code https://github.com/extrawurst/unecht/tree/master/source/unecht/gl
    class OGL33RenderVisitor : Visitor
    {
        Window window;
        Shader vertexShader;
        Shader fragmentShader;
        mat4[] modelViewStack;
        mat4 projection;
        this(Window window)
        {
            this.window = window;
        }

        override void visit(NodeData n)
        {
        }

        override void visit(GroupData n)
        {
            foreach (ref child; n.childs)
            {
                if (child.get)
                {
                    child.get.accept(this);
                }
                else
                {
                    writeln("child null", n);
                }
            }
        }

        override void visit(SceneData n)
        {
            n.ensureRenderThread;

            glClearColor(1, 0, 0, 1);
            checkOglErrors;
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            checkOglErrors;
            glFrontFace(GL_CCW);
            checkOglErrors;
            glCullFace(GL_BACK);
            checkOglErrors;
            glEnable(GL_CULL_FACE);
            checkOglErrors;
            // glDisable(GL_CULL_FACE);
            // checkOglErrors;
            glDisable(GL_DITHER);
            checkOglErrors;
            glDisable(GL_DEPTH_TEST);
            checkOglErrors;
            //  glDepthFunc(GL_LESS);
            checkOglErrors;
            // glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
            checkOglErrors;
            glViewport(0, 0, window.getWidth, window.getHeight);
            checkOglErrors;

            visit(cast(GroupData) n);
        }

        override void visit(ProjectionGroupData n)
        {
            projection = n.getProjection.getProjectionMatrix(window.getWidth, window.getHeight);
            visit(cast(GroupData) n);
        }

        override void visit(ObserverData n)
        {
            modelViewStack = [mat4.identity * n.getCameraTransformation];
            visit(cast(ProjectionGroupData) n);
        }

        override void visit(TransformationGroupData n)
        {
            auto old = modelViewStack;
            modelViewStack ~= modelViewStack[$ - 1] * n.getTransformation;
            visit(cast(GroupData) n);
            modelViewStack = old;
        }

        void prepareBuffers(AppearanceData app, IndexedInterleavedTriangleArrayData triangles)
        {
            auto rcProgram = dynCast!(FileProgramData)(app.customData);
            (rcProgram != null).enforce("no program");

            auto program = rcProgram.get;

            auto rcBuffers = dynCast!(
                IndexedInterleavedTriangleArrayBuffersData)(triangles.customData);
            if (rcBuffers != null)
            {
                rcBuffers.get.bind();
            }
            else
            {
                rcBuffers = IndexedInterleavedTriangleArrayBuffers.make();
                auto buffers = rcBuffers.get.bind();
                buffers.indexData.bind.data(triangles.indices);

                buffers.vertexData.bind.data(triangles.data.get.data);
                auto position = program.getAttribute("position");
                position.glVertexAttribPointer(3, GL_FLOAT, GL_FALSE,
                        cast(int)(triangles.data.get.tupleSize * float.sizeof), cast(void*) 0);
                checkOglErrors();
                position.glEnableVertexAttribArray();
                checkOglErrors();

                if (triangles.data.get.components.COLORS)
                {
                    auto color = program.getAttribute("color");
                    color.glVertexAttribPointer(4, GL_FLOAT, GL_FALSE,
                            cast(int)(triangles.data.get.tupleSize * float.sizeof),
                            cast(void*)(triangles.data.get.colorsOffset * float.sizeof));
                    checkOglErrors();
                    color.glEnableVertexAttribArray();
                    checkOglErrors();
                }

                if (triangles.data.get.components.TEXTURE_COORDINATES)
                {
                    auto textureCoordinate = program.getAttribute("textureCoordinate");
                    textureCoordinate.glVertexAttribPointer(2, GL_FLOAT, GL_FALSE,
                            cast(int)(triangles.data.get.tupleSize * float.sizeof),
                            cast(void*)(triangles.data.get.textureCoordinatesOffset * float.sizeof));
                    checkOglErrors();
                    textureCoordinate.glEnableVertexAttribArray();
                    checkOglErrors();
                }

                triangles.customData = rcBuffers;
            }
        }

        void prepareBuffers(AppearanceData app, TriangleArrayData triangles)
        {
            auto rcProgram = dynCast!(FileProgramData)(app.customData);
            auto program = rcProgram.get;
            auto rcBuffers = dynCast!(TriangleArrayBuffersData)(triangles.customData);
            if (rcBuffers != null)
            {
                rcBuffers.get.bind();
            }
            else
            {
                rcBuffers = TriangleArrayBuffers.make();
                auto buffers = rcBuffers.get.bind();

                buffers.positions.bind.data(triangles.coordinates);
                auto position = program.getAttribute("position");
                position.glVertexAttribPointer(3, GL_FLOAT, GL_FALSE, // normalized
                        vec3.sizeof, // stride
                        cast(void*) 0); // offset of the first
                checkOglErrors;
                position.glEnableVertexAttribArray();
                checkOglErrors;

                buffers.colors.bind.data(triangles.colors);
                auto color = program.getAttribute("color");
                color.glVertexAttribPointer(4, GL_FLOAT, GL_FALSE, vec4.sizeof, cast(void*) 0);
                checkOglErrors;
                color.glEnableVertexAttribArray();
                checkOglErrors;

                buffers.textureCoordinates.bind.data(triangles.textureCoordinates);
                auto textureCoordinate = program.getAttribute("textureCoordinate");
                textureCoordinate.glVertexAttribPointer(2, GL_FLOAT, GL_FALSE,
                        vec2.sizeof, cast(void*) 0);
                checkOglErrors;
                textureCoordinate.glEnableVertexAttribArray();
                checkOglErrors;

                triangles.customData = rcBuffers;
            }
        }

        private TextureName createAndLoadTexture(TextureData texture)
        {
            auto image = texture.image;
            auto result = TextureName.make(thisTid);
            GL_TEXTURE_2D.glBindTexture(result.get.textureName);
            checkOglErrors;
            GL_UNPACK_ALIGNMENT.glPixelStorei(1);
            checkOglErrors;
            GL_TEXTURE_2D.glTexImage2D( // target
                    0, // level
                    GL_RGB, // internalFormat
                    image.w, // width
                    image.h, // height
                    0, // border
                    GL_RGB, // format
                    GL_UNSIGNED_BYTE, // type
                    image.buf8.ptr // pixels
                    );
            checkOglErrors;
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            checkOglErrors;
            texture.customData = result;
            return result;
        }

        private void activate(TextureData texture)
        {
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_WRAP_S, texture.wrapS
                    ? GL_REPEAT : GL_CLAMP_TO_EDGE);
            checkOglErrors;
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_WRAP_T, texture.wrapT
                    ? GL_REPEAT : GL_CLAMP_TO_EDGE);
            checkOglErrors;
            // dfmt off
            auto textureName = dynCast!(TextureNameData)(texture.customData);
            if (textureName == null) {
                textureName = createAndLoadTexture(texture);
            }
            // dfmt on
            GL_TEXTURE0.glActiveTexture();
            GL_TEXTURE_2D.glBindTexture(textureName.get.textureName);
            checkOglErrors;
        }

        void activate(AppearanceData appearance)
        {
            auto program = dynCast!(FileProgramData)(appearance.customData);
            if (program == null)
            {
                program = FileProgram.make(appearance.shaderBase);
                appearance.customData = program;
            }
            program.get.use();
            activate(appearance.textures[0].get);
        }

        override void visit(ShapeGroupData n)
        {
            activate(n.appearance.get);

            auto program = dynCast!(FileProgramData)(n.appearance.get.customData);
            program.get.setUniform("projection", projection);

            auto mv = modelViewStack[$ - 1];
            program.get.setUniform("modelView", mv);
            checkOglErrors;

            if (auto triangles = cast(TriangleArrayData) n.geometry.get)
            {
                prepareBuffers(n.appearance.get, triangles);
                GL_TRIANGLES.glDrawArrays(0, cast(int) triangles.coordinates.length);
                checkOglErrors;
            }

            if (auto triangles = cast(IndexedInterleavedTriangleArrayData) n.geometry.get)
            {
                prepareBuffers(n.appearance.get, triangles);
                GL_TRIANGLES.glDrawElements(cast(int) triangles.indices.length,
                        GL_UNSIGNED_INT, cast(void*) 0);
                checkOglErrors;
            }
        }

        override void visit(Behavior b)
        {
        }
    }
}
