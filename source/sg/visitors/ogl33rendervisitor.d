module sg.visitors.ogl33rendervisitor;

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

            shader = glCreateShader(type == Type.vertex ? GL_VERTEX_SHADER : GL_FRAGMENT_SHADER);
            checkOglError;

            auto stringLength = cast(int) source.length;
            const(char)* stringPointer = source.ptr;
            glShaderSource(shader, 1, &stringPointer, &stringLength);
            checkOglError;

            glCompileShader(shader);
            checkOglError;

            GLint success;
            glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
            checkOglError;
            if (!success)
            {
                GLchar[1024] InfoLog;
                GLsizei logLen;
                glGetShaderInfoLog(shader, 1024, &logLen, InfoLog.ptr);
                checkOglError;

                auto errors = (InfoLog[0 .. logLen - 1]).to!string;
                writeln("Error compiling shader: '%s'", errors);
            }
        }

        ~this()
        {
            glDeleteShader(shader);
            checkOglError;
        }
    }
    // https://github.com/Circular-Studios/Dash/blob/develop/source/dash/graphics/shaders/glsl/package.d
    enum glslVersionSource = "#version 330 core\n";

    immutable string vertexShaderSource = glslVersionSource ~ q{
        layout (location = 0) in vec3 vertex;
        void main()
        {
            gl_Position = vec4(vertex, 1.0);
        }
    };

    // example code https://github.com/extrawurst/unecht/tree/master/source/unecht/gl
    class OGL33RenderVisitor : Visitor
    {
        import bindbc.opengl;

        Window window;
        Shader vertexShader;
        this(Window window)
        {
            this.window = window;
            vertexShader = new Shader(Shader.Type.vertex, vertexShaderSource);
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

            glClearColor(0, 0, 0, 1);
            checkOglError();
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
            //      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
            checkOglError();
            glViewport(0, 0, window.getWidth, window.getHeight);
            checkOglError();

            visit(cast(Node)(n));
        }

        override void visit(ProjectionNode n)
        {
            /+ TODO
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glMultMatrixf(n.getProjection.getProjectionMatrix(window.getWidth,
                    window.getHeight).transposed.value_ptr);

            glMatrixMode(GL_MODELVIEW);
            visit(cast(Node) n);
            +/
        }

        alias visit = Visitor.visit;
    }
}
