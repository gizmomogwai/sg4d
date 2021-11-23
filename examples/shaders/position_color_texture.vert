#version 330 core

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
