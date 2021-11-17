module sg.visitors.ogl33rendervisitor;

// http://www.lighthouse3d.com/tutorials/glsl-tutorial/hello-world/
// https://learnopengl.com/Getting-started/Shaders - great tutorial as it takes the projection and modelview matrices out of the equation!!!

version (GL_33)
{
    import sg;
    import sg.visitors;
    import sg.window;
    import std;

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
            checkOglError;

            auto stringLength = cast(int) source.length;
            const(char)* stringPointer = source.ptr;
            shader.glShaderSource(1, &stringPointer, &stringLength);
            checkOglError;

            shader.glCompileShader();
            checkOglError;

            GLint success;
            shader.glGetShaderiv(GL_COMPILE_STATUS, &success);
            checkOglError;
            if (!success)
            {
                GLchar[1024] infoLog;
                GLsizei logLen;
                shader.glGetShaderInfoLog(1024, &logLen, infoLog.ptr);
                checkOglError;

                auto errors = (infoLog[0 .. logLen - 1]).to!string;
                success.enforce("Error compiling shader\n  type='%s'\n  source='%s'\n  errors: '%s'".format(type, source, errors));
            }
        }

        ~this()
        {
            shader.glDeleteShader();
            checkOglError;
        }
    }

    class Program {
        GLuint program;
        GLuint[string] attributesCache;
        GLuint[string] uniformsCache;
        this(Shader vertexShader, Shader fragmentShader) {
            program = glCreateProgram();
            (program != 0).enforce("Cannot create program");
            program.glAttachShader(vertexShader.shader);
            program.glAttachShader(fragmentShader.shader);
            program.glLinkProgram();
            GLint success;
            program.glGetProgramiv(GL_LINK_STATUS, &success);
            if (success == 0) {
                static GLchar[1024] logBuff;
                static GLsizei logLen;
                program.glGetProgramInfoLog(logBuff.sizeof, &logLen, logBuff.ptr);
                throw new Exception("Error: linking program: %s".format(logBuff[0..logLen-1].to!string));
            }
        }
        auto setUniform(string name, mat4 matrix) {
            auto location = name in uniformsCache ? uniformsCache[name] : addUniformLocationToCache(name);
            location.glUniformMatrix4fv(1, GL_TRUE, matrix.value_ptr);
            checkOglError;
        }
        private GLuint addUniformLocationToCache(string name) {
            auto location = program.glGetUniformLocation(name.ptr);
            (location != -1).enforce("Cannot find uniform location for '%s'".format(name));
            uniformsCache[name] = location;
            return location;
        }
        private GLuint addAttributeLocationToCache(string name) {
            auto location = program.glGetAttribLocation(name.ptr);
            (location != -1).enforce("Cannot find attribute location for '%s'".format(name));
            attributesCache[name] = location;
            return location;
        }
        auto getAttribute(string name) {
            return name in attributesCache ? attributesCache[name] : addAttributeLocationToCache(name);
        }
        void use() {
            program.glUseProgram();
        }
    }
    // https://github.com/Circular-Studios/Dash/blob/develop/source/dash/graphics/shaders/glsl/package.d
    enum glslVersionSource = "#version 330 core\n";
    immutable string vertexShaderSource = glslVersionSource ~ q{
        uniform mat4 projection;
        uniform mat4 modelView;

        in vec3 position;
        in vec4 color;
        in vec2 textureCoordinate;

        out vec4 vertexColor;
        out vec2 vertexTextureCoordinate;
        void main()
        {
            gl_Position = projection * modelView * vec4(position, 1.0);
            vertexColor = color;
            vertexTextureCoordinate = textureCoordinate;
        }
    };

    immutable string fragmentShaderSource = glslVersionSource ~ q{
        in vec4 vertexColor;
        in vec2 vertexTextureCoordinate;
        uniform sampler2D texture0;

        out vec4 fragmentColor;
        void main() {
            fragmentColor = vertexColor * texture(texture0, vertexTextureCoordinate);
        }
    };

    // example code https://github.com/extrawurst/unecht/tree/master/source/unecht/gl
    class OGL33RenderVisitor : Visitor
    {
        import bindbc.opengl;

        Window window;
        Shader vertexShader;
        Shader fragmentShader;
        Program program;
        mat4[] modelViewStack;
        this(Window window)
        {
            this.window = window;
            vertexShader = new Shader(Shader.Type.vertex, vertexShaderSource);
            fragmentShader = new Shader(Shader.Type.fragment, fragmentShaderSource);
            program = new Program(vertexShader, fragmentShader);
            program.use();
        }

        override void visit(Node n)
        {
            foreach (child; n.childs)
            {
                child.accept(this);
            }
        }

        override void visit(Scene n)
        {
            n.ensureRenderThread;

            glClearColor(1, 0, 0, 1);
            checkOglError();
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            checkOglError();
            glFrontFace(GL_CCW);
            checkOglError();
            glCullFace(GL_BACK);
            checkOglError();
            glEnable(GL_CULL_FACE);
            checkOglError();
            // glDisable(GL_CULL_FACE);
            glDisable(GL_DITHER);
            checkOglError();
            glDisable(GL_DEPTH_TEST);
            checkOglError();
            //  glDepthFunc(GL_LESS);
            checkOglError();
            // glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
            checkOglError();
            glViewport(0, 0, window.getWidth, window.getHeight);
            checkOglError();

            visit(cast(Node)(n));
        }

        override void visit(ProjectionNode n)
        {
            program.setUniform("projection", n.getProjection.getProjectionMatrix(window.getWidth, window.getHeight));
            visit(cast(Node) n);
        }

        override void visit(Observer n)
        {
            modelViewStack = [mat4.identity * n.getCameraTransformation];
            visit(cast(ProjectionNode) n);
        }

        override void visit(TransformationNode n)
        {
            auto old = modelViewStack;
            modelViewStack ~= modelViewStack[$-1]*n.getTransformation;
            foreach (child; n.childs)
            {
                child.accept(this);
            }
            modelViewStack = old;
        }

        class Buffers : CustomData {
            VAO vao;
            VBO positions;
            VBO colors;
            VBO textureCoordinates;
            this() {
                vao = new VAO();
                positions = new VBO();
                colors = new VBO();
                textureCoordinates = new VBO();
            }
            auto bind() {
                vao.bind();
                return this;
            }
            override void free() {
                // TODO
            }
        }
        class VAO {
            GLuint vertexArray;
            this() {
                1.glGenVertexArrays(&vertexArray);
                checkOglError;
            }
            void free() {
                // TODO
            }
            auto bind() {
                vertexArray.glBindVertexArray();
                checkOglError;
                return this;
            }
        }
        class VBO {
            GLuint buffer;
            this() {
                1.glGenBuffers(&buffer);
                checkOglError;
            }
            void free() {
                // TODO
            }
            auto bind() {
                GL_ARRAY_BUFFER.glBindBuffer(buffer);
                checkOglError;
                return this;
            }
            auto data(T)(T data) {
                GL_ARRAY_BUFFER.glBufferData(data.length*T.sizeof, cast(void*)data.ptr, GL_STATIC_DRAW);
                checkOglError;
                return this;
            }
        }
        void prepareBuffers(TriangleArray triangles) {
            if (auto buffers = cast(Buffers)triangles.customData) {
                buffers.bind();
            } else {
                auto buffers = new Buffers().bind();
                buffers.positions.bind.data(triangles.coordinates);
                auto position = program.getAttribute("position");
                position.glVertexAttribPointer(3,
                                               GL_FLOAT,
                                               GL_FALSE, // normalized
                                               vec3.sizeof, // stride
                                               cast(void*)0); // offset of the first
                checkOglError;
                position.glEnableVertexAttribArray();
                checkOglError;

                buffers.colors.bind.data(triangles.colors);
                auto color = program.getAttribute("color");
                color.glVertexAttribPointer(4,
                                            GL_FLOAT,
                                            GL_FALSE,
                                            vec4.sizeof,
                                            cast(void*)0);
                checkOglError;
                color.glEnableVertexAttribArray();
                checkOglError;

                buffers.textureCoordinates.bind.data(triangles.textureCoordinates);
                auto textureCoordinate = program.getAttribute("textureCoordinate");
                textureCoordinate.glVertexAttribPointer(2,
                                                        GL_FLOAT,
                                                        GL_FALSE,
                                                        vec2.sizeof,
                                                        cast(void*)0);
                checkOglError;
                textureCoordinate.glEnableVertexAttribArray();
                checkOglError;

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

            override void free()
            {
            }
        }

        private TextureName createAndLoadTexture(Texture texture)
        {
            auto image = texture.image;
            GLuint textureName;
            glGenTextures(1, &textureName);
            checkOglError();
            glBindTexture(GL_TEXTURE_2D, textureName);
            checkOglError();
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            checkOglError();
            glTexImage2D(GL_TEXTURE_2D, // target
                    0, // level
                    GL_RGB, // internalFormat
                    image.w, // width
                    image.h, // height
                    0, // border
                    GL_RGB, // format
                    GL_UNSIGNED_BYTE, // type
                    image.buf8.ptr // pixels
                    );
            checkOglError();
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            checkOglError();
            auto result = new TextureName(textureName);
            texture.customData = result;
            return result;
        }

        private void activate(Texture texture)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, texture.wrapS ? GL_REPEAT : GL_CLAMP_TO_EDGE);
            checkOglError();
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, texture.wrapT ? GL_REPEAT : GL_CLAMP_TO_EDGE);
            checkOglError();
            // dfmt off
            auto textureName = cast(TextureName) texture.customData is null ?
                createAndLoadTexture(texture)
                : cast(TextureName) texture.customData;
            // dfmt on
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, textureName.textureName);
            checkOglError();
        }

        override void visit(Shape n)
        {
            program.setUniform("modelView", modelViewStack[$-1]);

            if (auto appearance = n.appearance)
            {
                activate(appearance.textures[0]);
            }

            if (auto triangles = cast(TriangleArray) n.geometry)
            {
                prepareBuffers(triangles);
                GL_TRIANGLES.glDrawArrays(0, cast(int)triangles.coordinates.length);
                checkOglError;
            }
        }

        alias visit = Visitor.visit;
    }
}
