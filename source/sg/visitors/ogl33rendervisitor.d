module sg.visitors.ogl33rendervisitor;

// http://www.lighthouse3d.com/tutorials/glsl-tutorial/hello-world/
// https://learnopengl.com/Getting-started/Shaders - great tutorial as it takes the projection and modelview matrices out of the equation!!!

version (GL_33)
{
    import sg;
    import sg.visitors;
    import sg.window;
    import std.concurrency;
    import std.conv;
    import std.exception;
    import std.string;

    // adapted from https://github.com/extrawurst/unecht/tree/master/source/unecht/gl

    ///
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

        this() {
            program = glCreateProgram();
            (program != 0).enforce("Cannot create program");
        }
        void destroy() {
            program.glDeleteProgram;
            checkOglErrors;
        }

        void link(Shader[] shaders...) {
            foreach (shader; shaders) {
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

    class FileProgram : CustomData {
        import fswatch;
        string shaderName;
        Program program;
        FileWatch fileWatch;
        this(string shaderName) {
            this.shaderName = shaderName;
            this.fileWatch = FileWatch("../shaders", true);
            update();
        }

        void checkForUpdates() {
            try {
            foreach (event; fileWatch.getEvents()) {
                import std.path;
                if (event.path.startsWith(shaderName.baseName)) {
                    update();
                }
            }
            } catch (Exception e) {
                import std.stdio; writeln(e);
            }
        }
        void use() {
            program.use();
        }
        void update() {
            program = new Program();
            import std.file : readText;
            scope vertexShader = new Shader(Shader.Type.vertex, ("../shaders/" ~ shaderName ~ ".vert").readText);
            scope fragmentShader = new Shader(Shader.Type.fragment, ("../shaders/" ~ shaderName ~ ".frag").readText);
            program.link(vertexShader, fragmentShader);
            program.use();
        }
        alias program this;
    }

    // example code https://github.com/extrawurst/unecht/tree/master/source/unecht/gl
    class OGL33RenderVisitor : Visitor
    {
        import bindbc.opengl;

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
                child.get.accept(this);
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
            visit(cast(GroupData)n);
            modelViewStack = old;
        }

        class TriangleArrayBuffers : CustomData
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

            auto bind()
            {
                vao.bind();
                return this;
            }
        }
        class IndexedInterleavedTriangleArrayBuffers : CustomData {
            VAO vao;
            VBO vertexData;
            EBO indexData;
            this() {
                vao = new VAO();
                vertexData = new VBO();
                indexData = new EBO();
            }
            auto bind() {
                vao.bind();
                return this;
            }
        }
        class EBO {
            GLuint indexArray;
            this() {
                1.glGenBuffers(&indexArray);
                checkOglErrors;
            }
            auto bind() {
                GL_ELEMENT_ARRAY_BUFFER.glBindBuffer(indexArray);
                return this;
            }
            auto data(T)(T[] data) {
                GL_ELEMENT_ARRAY_BUFFER.glBufferData(data.length * T.sizeof,
                        cast(void*) data.ptr, GL_STATIC_DRAW);
                checkOglErrors;
                return this;
            }
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

        void prepareBuffers(AppearanceData app, IndexedInterleavedTriangleArray triangles)
        {
            auto program = cast(FileProgram)app.customData;
            if (auto buffers = cast(IndexedInterleavedTriangleArrayBuffers) triangles.customData) {
                buffers.bind();
            } else {
                auto buffers = new IndexedInterleavedTriangleArrayBuffers().bind();

                buffers.indexData.bind.data(triangles.indices);

                buffers.vertexData.bind.data(triangles.data.data);

                auto position = program.getAttribute("position");
                position.glVertexAttribPointer(3, GL_FLOAT, GL_FALSE,
                                               cast(int)(triangles.data.tupleSize * float.sizeof),
                                               cast(void*)0);
                checkOglErrors();
                position.glEnableVertexAttribArray();
                checkOglErrors();

                if (triangles.data.components.COLORS) {
                    auto color = program.getAttribute("color");
                    color.glVertexAttribPointer(4, GL_FLOAT, GL_FALSE,
                                                cast(int)(triangles.data.tupleSize * float.sizeof),
                                                cast(void*)(triangles.data.colorsOffset*float.sizeof));
                    checkOglErrors();
                    color.glEnableVertexAttribArray();
                    checkOglErrors();
                }

                if (triangles.data.components.TEXTURE_COORDINATES) {
                    auto textureCoordinate = program.getAttribute("textureCoordinate");
                    textureCoordinate.glVertexAttribPointer(2, GL_FLOAT, GL_FALSE,
                                                            cast(int)(triangles.data.tupleSize * float.sizeof),
                                                            cast(void*)(triangles.data.textureCoordinatesOffset*float.sizeof));
                    checkOglErrors();
                    textureCoordinate.glEnableVertexAttribArray();
                    checkOglErrors();
                }

                triangles.customData = buffers;
            }
        }

        void prepareBuffers(AppearanceData app, TriangleArray triangles)
        {
            auto program = cast(FileProgram)app.customData;
            if (auto buffers = cast(TriangleArrayBuffers) triangles.customData)
            {
                buffers.bind();
            }
            else
            {
                auto buffers = new TriangleArrayBuffers().bind();

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

                triangles.customData = buffers;
            }
        }

        class TextureName : CustomData
        {
            GLuint textureName;
            this(GLuint textureName)
            {
                this.textureName = textureName;
            }

        }

        private TextureName createAndLoadTexture(Texture texture)
        {
            auto image = texture.image;
            GLuint textureName;
            1.glGenTextures(&textureName);
            checkOglErrors;
            GL_TEXTURE_2D.glBindTexture(textureName);
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
            auto result = new TextureName(textureName);
            texture.customData = result;
            return result;
        }

        private void activate(Texture texture)
        {
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_WRAP_S, texture.wrapS
                    ? GL_REPEAT : GL_CLAMP_TO_EDGE);
            checkOglErrors;
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_WRAP_T, texture.wrapT
                    ? GL_REPEAT : GL_CLAMP_TO_EDGE);
            checkOglErrors;
            // dfmt off
            auto textureName = cast(TextureName) texture.customData is null ?
                createAndLoadTexture(texture)
                : cast(TextureName) texture.customData;
            // dfmt on
            GL_TEXTURE0.glActiveTexture();
            GL_TEXTURE_2D.glBindTexture(textureName.textureName);
            checkOglErrors;
        }

        void activate(AppearanceData appearance) {
            if (auto program = cast(FileProgram)appearance.customData) {
                program.use();
            } else {
                auto program = new FileProgram(appearance.shaderBase);
                appearance.customData = program;
                program.use();
            }
            activate(appearance.textures[0]);
        }

        override void visit(ShapeGroupData n)
        {
            activate(n.appearance.get);

            auto program = cast(FileProgram)n.appearance.get.customData;
            program.setUniform("projection", projection);

            auto mv = modelViewStack[$ - 1];
            program.setUniform("modelView", mv);
            checkOglErrors;

            if (auto triangles = cast(TriangleArray) n.geometry)
            {
                prepareBuffers(n.appearance.get, triangles);
                GL_TRIANGLES.glDrawArrays(0, cast(int) triangles.coordinates.length);
                checkOglErrors;
            }

            if (auto triangles = cast(IndexedInterleavedTriangleArray) n.geometry)
            {
                prepareBuffers(n.appearance.get, triangles);
                GL_TRIANGLES.glDrawElements(cast(int)triangles.indices.length, GL_UNSIGNED_INT, cast(void*)0);
                checkOglErrors;
            }
        }

        override void visit(Behavior b)
        {
        }
    }
}
