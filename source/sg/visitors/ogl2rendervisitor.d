module sg.visitors.ogl2rendervisitor;

version (Default)
{

    import sg;
    import sg.visitors;
    import sg.window;
    import std;

    // opengl version till 2.1
    /++
 + https://austinmorlan.com/posts/opengl_matrices/
 + gl3n stores row major -> all matrices need to be transposed either
 + manually for opengl2 or with setting GL_TRUE when passing to a shader
 +/
    class OGL2RenderVisitor : Visitor
    {
        import bindbc.opengl;

        Window window;
        this(Window window)
        {
            this.window = window;
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
            glColor3f(1, 1, 1);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glFrontFace(GL_CCW);
            glCullFace(GL_BACK);
            glEnable(GL_CULL_FACE);
            // glDisable(GL_CULL_FACE);
            glDisable(GL_DITHER);
            glDisable(GL_DEPTH_TEST);
            //  glDepthFunc(GL_LESS);
            glDisable(GL_LIGHTING);
            //      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
            glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
            glViewport(0, 0, window.getWidth, window.getHeight);

            visit(cast(Node)(n));
        }

        override void visit(ProjectionNode n)
        {
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glMultMatrixf(n.getProjection.getProjectionMatrix(window.getWidth,
                    window.getHeight).transposed.value_ptr);

            glMatrixMode(GL_MODELVIEW);
            visit(cast(Node) n);
        }

        override void visit(Observer n)
        {
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();
            glMultMatrixf(n.getCameraTransformation.transposed.value_ptr);

            visit(cast(ProjectionNode) n);
        }

        override void visit(TransformationNode n)
        {
            glPushMatrix();
            glMultMatrixf(n.getTransformation.transposed.value_ptr);
            foreach (child; n.childs)
            {
                child.accept(this);
            }
            glPopMatrix();
        }

        class TextureName : CustomData
        {
            Tid renderThread;
            GLuint textureName;
            this(Tid renderThread, GLuint textureName)
            {
                this.renderThread = renderThread;
                this.textureName = textureName;
            }

            override void free()
            {
                renderThread.send(cast(shared)() {
                    import std.stdio;

                    writeln("freeing texture ", textureName);
                    glDeleteTextures(1, &textureName);
                });
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
            glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
            checkOglError();
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            checkOglError();
            auto result = new TextureName(thisTid, textureName);
            texture.customData = result;
            return result;
        }

        private void activate(Texture texture)
        {
            glEnable(GL_TEXTURE_2D);
            checkOglError();

            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, texture.wrapS ? GL_REPEAT : GL_CLAMP);
            checkOglError();
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, texture.wrapT ? GL_REPEAT : GL_CLAMP);
            checkOglError();
            // dfmt off
        auto textureName = cast(TextureName) texture.customData is null ?
            createAndLoadTexture(texture)
            : cast(TextureName) texture.customData;
        // dfmt on
            glBindTexture(GL_TEXTURE_2D, textureName.textureName);
            checkOglError();
        }

        override void visit(Shape n)
        {
            if (auto appearance = n.appearance)
            {
                activate(appearance.textures[0]);
            }

            /+ immediate mode
        if (auto triangleArray = cast(TriangleArray) n.geometry)
        {
            glBegin(GL_TRIANGLES);
            for (int i = 0; i < triangleArray.coordinates.length; ++i)
            {
                auto color = triangleArray.colors[i];
                auto coordinates = triangleArray.coordinates[i];

                if (triangleArray.textureCoordinates.length > i)
                {
                    auto textureCoordinates = triangleArray.textureCoordinates[i];
                    glTexCoord2f(textureCoordinates.x, textureCoordinates.y);
                }
                glColor3f(color.x, color.y, color.z);
                glVertex3f(coordinates.x, coordinates.y, coordinates.z);
            }
            glEnd();
        }
        +/
            if (auto g = cast(TriangleArray) n.geometry)
            {
                glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
                {
                    glEnableClientState(GL_VERTEX_ARRAY);
                    glVertexPointer(3, GL_FLOAT, 0, g.coordinates.ptr);

                    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                    glTexCoordPointer(2, GL_FLOAT, 0, g.textureCoordinates.ptr);

                    glEnableClientState(GL_COLOR_ARRAY);
                    glColorPointer(4, GL_FLOAT, 0, g.colors.ptr);

                    glDrawArrays(GL_TRIANGLES, 0, cast(int) g.coordinates.length);
                }
                glPopClientAttrib();
            }

            if (auto g = cast(IndexedInterleavedTriangleArray) n.geometry)
            {
                int stride = cast(int)(g.data.tupleSize * float.sizeof);
                glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
                {
                    glEnableClientState(GL_VERTEX_ARRAY);
                    glVertexPointer(3, GL_FLOAT, stride, g.data.data.ptr);

                    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                    glTexCoordPointer(2, GL_FLOAT, stride,
                            g.data.data.ptr + g.data.textureCoordinatesOffset);

                    if (g.data.components.COLORS)
                    {
                        glEnableClientState(GL_COLOR_ARRAY);
                        glColorPointer(4, GL_FLOAT, stride, g.data.data.ptr + g.data.colorsOffset);
                    }
                    glDrawElements(GL_TRIANGLES, cast(int) g.indices.length,
                            GL_UNSIGNED_INT, g.indices.ptr);
                }
                glPopClientAttrib();
            }
        }

        override void visit(Behavior n)
        {
        }
    }
}
