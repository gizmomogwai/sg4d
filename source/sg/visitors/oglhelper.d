module sg.visitors.oglhelper;

import bindbc.opengl : glGetError, GLenum, GL_NO_ERROR, GL_INVALID_ENUM,
    GL_INVALID_VALUE, GL_INVALID_OPERATION, GL_OUT_OF_MEMORY, glGetIntegerv;
import std.array : join;
import std.string : format;

void checkOglErrors()
{
    string[] errors;
    GLenum error = glGetError();
    while (error != GL_NO_ERROR)
    {
        errors ~= "OGL error %s (%s)".format(error, glGetErrorString(error));
        error = glGetError();
    }
    if (errors.length > 0)
    {
        throw new Exception(errors.join("\n"));
    }
}

private string glGetErrorString(GLenum error)
{
    switch (error)
    {
    case GL_INVALID_ENUM:
        return "GL_INVALID_ENUM";
    case GL_INVALID_VALUE:
        return "GL_INVALID_VALUE";
    case GL_INVALID_OPERATION:
        return "GL_INVALID_OPERATION";
        //case GL_INVALID_FRAMEBUFFER_OPERATION:
        //return "GL_INVALID_FRAMEBUFFER_OPERATION";
    case GL_OUT_OF_MEMORY:
        return "GL_OUT_OF_MEMORY";
    default:
        throw new Exception("Unknown OpenGL error code %s".format(error));
    }
}

int glGetInt(GLenum what)
{
    int result;
    glGetIntegerv(what, &result);
    checkOglErrors();
    return result;
}
