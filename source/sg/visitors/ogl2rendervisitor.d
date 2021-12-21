module sg.visitors.ogl2rendervisitor;

version (Default)
{

    import sg.visitors;
    import sg.window;
    import sg;
    import std.concurrency;
    import std.exception;
    import std.stdio;

    import autoptr.common;
    import autoptr.intrusive_ptr;

    alias TextureName = IntrusivePtr!TextureNameData;
    class TextureNameData : CustomDataData
    {
        Tid renderThread;
        GLuint textureName;
        this(Tid renderThread, GLuint textureName)
        {
            this.renderThread = renderThread;
            this.textureName = textureName;
        }

        ~this() @nogc
        {
            1.glDeleteTextures(&textureName);
        }
    }
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

        override void visit(NodeData)
        {
        }

        override void visit(GroupData g)
        {
            foreach (ref child; g.childs)
            {
                child.get.accept(this);
            }
        }

        override void visit(SceneData n)
        {
            n.ensureRenderThread;

            glClearColor(1, 0, 0, 1);
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
            glViewport(0, 0, window.getWidth(), window.getHeight());

            visit(cast(GroupData) n);
        }

        void debugMatrix(string msg, int which)
        {
            mat4 m;
            glGetFloatv(which, m.matrix[0].ptr);
            checkOglErrors;
            writeln(msg, m.transposed.toPrettyString);
        }

        override void visit(ProjectionGroupData n)
        {
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glMultMatrixf(n.getProjection.getProjectionMatrix(window.getWidth,
                    window.getHeight).transposed.value_ptr);
            glMatrixMode(GL_MODELVIEW);
            visit(cast(GroupData) n);
        }

        override void visit(ObserverData n)
        {
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();
            glMultMatrixf(n.getCameraTransformation.transposed.value_ptr);

            visit(cast(ProjectionGroupData) n);
        }

        override void visit(TransformationGroupData n)
        {
            glPushMatrix();
            {
                glMultMatrixf(n.getTransformation.transposed.value_ptr);
                visit(cast(GroupData) n);
            }
            glPopMatrix();
        }

        private TextureName createAndLoadTexture(TextureData texture)
        {
            auto image = texture.image;
            GLuint textureName;
            glGenTextures(1, &textureName);
            checkOglErrors;
            glBindTexture(GL_TEXTURE_2D, textureName);
            checkOglErrors;
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            checkOglErrors;
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
            checkOglErrors;
            GL_TEXTURE_ENV.glTexEnvf(GL_TEXTURE_ENV_MODE, GL_MODULATE);
            checkOglErrors;
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            GL_TEXTURE_2D.glTexParameteri(GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            checkOglErrors;

            auto result = TextureName.make(thisTid, textureName);
            texture.customData = result;
            return result;
        }

        private void activate(TextureData texture)
        {
            glEnable(GL_TEXTURE_2D);
            checkOglErrors;

            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, texture.wrapS ? GL_REPEAT : GL_CLAMP);
            checkOglErrors;
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, texture.wrapT ? GL_REPEAT : GL_CLAMP);
            checkOglErrors;

            auto textureName = dynCast!(TextureNameData)(texture.customData);
            if (textureName == null)
            {
                textureName = createAndLoadTexture(texture);
            }

            glBindTexture(GL_TEXTURE_2D, textureName.get.textureName);
            checkOglErrors;
        }

        void activate(AppearanceData app)
        {
            if (app.textures.length > 0)
            {
                activate(app.textures[0].get);
            }
        }

        override void visit(ShapeGroupData n)
        {
            activate(n.appearance.get);

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

            if (auto triangles = cast(IndexedInterleavedTriangleArray) n.geometry)
            {
                int stride = cast(int)(triangles.data.tupleSize * float.sizeof);
                glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
                {
                    glEnableClientState(GL_VERTEX_ARRAY);
                    glVertexPointer(3, GL_FLOAT, stride, triangles.data.data.ptr);

                    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                    glTexCoordPointer(2, GL_FLOAT, stride,
                            triangles.data.data.ptr + triangles.data.textureCoordinatesOffset);

                    if (triangles.data.components.COLORS)
                    {
                        glEnableClientState(GL_COLOR_ARRAY);
                        glColorPointer(4, GL_FLOAT, stride,
                                triangles.data.data.ptr + triangles.data.colorsOffset);
                    }

                    glDrawElements(GL_TRIANGLES, cast(int) triangles.indices.length,
                            GL_UNSIGNED_INT, triangles.indices.ptr);
                }
                glPopClientAttrib();
            }
        }

        override void visit(Behavior n)
        {
        }
    }
}
